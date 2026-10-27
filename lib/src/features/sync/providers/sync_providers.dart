import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';
import 'package:vaultkey/src/features/sync/services/sync_exchange.dart';
import 'package:vaultkey/src/features/sync/services/sync_ledger.dart';
import 'package:vaultkey/src/features/sync/services/sync_merge.dart';
import 'package:vaultkey/src/features/sync/services/sync_network.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

final localDeviceProvider = FutureProvider<LocalDevice>(
  (ref) => ref.watch(syncLedgerProvider).device(),
);

final pairedDevicesProvider = FutureProvider<List<PairedDevice>>(
  (ref) => ref.watch(syncLedgerProvider).peers(),
);

enum SyncPhase { idle, listening, syncing, done, failed }

@immutable
final class SyncStatus {
  const SyncStatus(this.phase, [this.message]);

  final SyncPhase phase;
  final String? message;
}

/// Runs sync while the Sync screen is open: listens for paired devices,
/// announces this one over mDNS, and syncs with each paired device found.
/// Disposed (and the listener closed) when the screen goes away, including
/// when the vault locks.
final syncControllerProvider =
    NotifierProvider.autoDispose<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends AutoDisposeNotifier<SyncStatus> {
  ServerSocket? _server;
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  LocalDevice? _device;

  /// Peers with a session in progress; a second connection is dropped.
  final _busy = <String>{};

  /// Peers already synced since [start]; rediscovery does not repeat them.
  final _synced = <String>{};

  /// The device with the smaller id connects first; the other waits this
  /// long for that connection before trying itself.
  static const _fallbackDelay = Duration(seconds: 5);

  SyncLedger get _ledger => ref.read(syncLedgerProvider);

  /// Set once the screen is gone; late network callbacks then stop
  /// touching state.
  bool _disposed = false;

  @override
  SyncStatus build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_stop());
    });
    return const SyncStatus(SyncPhase.idle);
  }

  void _set(SyncStatus status) {
    if (!_disposed) state = status;
  }

  Future<void> start() async {
    await _stop();
    _synced.clear();
    final peers = await _ledger.peers();
    if (peers.isEmpty) {
      _set(const SyncStatus(
        SyncPhase.idle,
        'Pair a device first, then sync.',
      ));
      return;
    }
    try {
      final device = _device = await _ledger.device();
      final server =
          _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      server.listen(_onIncoming);
      _registration = await SyncNetwork.announce(
        deviceId: device.id,
        port: server.port,
      );
      _discovery = await SyncNetwork.discover(_onFound);
      _set(const SyncStatus(
        SyncPhase.listening,
        'Looking for your devices. Open Vaultly → Sync on the other device '
        'too, on the same Wi-Fi.',
      ));
    } on Object catch (e) {
      await _stop();
      _set(SyncStatus(SyncPhase.failed, _describe(e)));
    }
  }

  Future<void> _stop() async {
    final discovery = _discovery;
    final registration = _registration;
    _discovery = null;
    _registration = null;
    if (discovery != null) {
      await SyncNetwork.stopDiscovery(discovery).catchError((Object _) {});
    }
    if (registration != null) {
      await SyncNetwork.withdraw(registration).catchError((Object _) {});
    }
    await _server?.close();
    _server = null;
  }

  Future<void> _onIncoming(Socket socket) async {
    final channel = SyncNetwork.channelFor(socket);
    final device = _device;
    try {
      if (device == null) return;
      final (secure, peerId) = await SyncHandshake.respond(
        channel: channel,
        myId: device.id,
        keyFor: (id) async => (await _ledger.peer(id))?.key,
      );
      if (_busy.contains(peerId)) return;
      await _session(secure, peerId);
    } on Object catch (e) {
      _fail(e);
    } finally {
      await channel.close();
    }
  }

  Future<void> _onFound(SyncPeerAnnouncement found) async {
    final device = _device;
    if (device == null || found.deviceId == device.id) return;
    final peer = await _ledger.peer(found.deviceId);
    if (peer == null) return;
    if (device.id.compareTo(peer.id) > 0) {
      await Future<void>.delayed(_fallbackDelay);
    }
    if (_disposed ||
        _server == null ||
        _busy.contains(peer.id) ||
        _synced.contains(peer.id)) {
      return;
    }
    FrameChannel? channel;
    try {
      channel = SyncNetwork.channelFor(
        await SyncNetwork.connect(found.hosts, found.port),
      );
      final secure = await SyncHandshake.initiate(
        channel: channel,
        myId: device.id,
        peerId: peer.id,
        pairingKey: peer.key,
      );
      await _session(secure, peer.id);
    } on Object catch (e) {
      _fail(e);
    } finally {
      await channel?.close();
    }
  }

  Future<void> _session(SecureChannel secure, String peerId) async {
    _busy.add(peerId);
    try {
      // The screen closes on lock, but a session that was already
      // connecting must never read or write a locked vault.
      if (ref.read(sessionProvider) != AuthStatus.unlocked) {
        throw const SyncProtocolException('Unlock Vaultly to sync.');
      }
      final peer = await _ledger.peer(peerId);
      if (peer == null) return;
      _set(SyncStatus(SyncPhase.syncing, 'Syncing with ${peer.name}…'));
      final vault = ref.read(vaultEntriesProvider.notifier);
      final local = SyncSnapshot(
        entries: await ref.read(vaultEntriesProvider.future),
        tombstones: await _ledger.tombstones(),
      );
      final result = await SyncExchange.run(secure, local);
      await _ledger.replaceTombstones(result.snapshot.tombstones);
      if (!listEquals(result.snapshot.entries, local.entries)) {
        await vault.replaceAll(result.snapshot.entries);
      }
      await _ledger.markSynced(peerId, ref.read(clockProvider).now());
      _synced.add(peerId);
      ref.invalidate(pairedDevicesProvider);
      final n = result.changes;
      _set(SyncStatus(
        SyncPhase.done,
        'Synced $n ${n == 1 ? 'change' : 'changes'} with ${peer.name}.',
      ));
    } finally {
      _busy.remove(peerId);
    }
  }

  void _fail(Object error) =>
      _set(SyncStatus(SyncPhase.failed, _describe(error)));

  static String _describe(Object error) => switch (error) {
        SyncProtocolException(:final message) => message,
        SocketException() =>
          'The network connection failed. Check both devices are on the '
              'same Wi-Fi.',
        _ => 'Sync stopped unexpectedly. Try again.',
      };
}
