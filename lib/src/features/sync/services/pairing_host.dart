import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/pairing.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';
import 'package:vaultkey/src/features/sync/services/sync_ledger.dart';
import 'package:vaultkey/src/features/sync/services/sync_network.dart';

/// The inviting side of pairing: a fresh key pair and one-time secret for
/// the QR code, and a listener that accepts exactly one joiner.
final class PairingHost {
  PairingHost._(this.invite, this._keyPair, this._server);

  static Future<PairingHost> open(LocalDevice device) async {
    final hosts = await SyncNetwork.localAddresses();
    if (hosts.isEmpty) {
      throw const SyncProtocolException(
        'Connect this device to Wi-Fi first.',
      );
    }
    final keyPair = await SyncPrimitives.x25519.newKeyPair();
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    return PairingHost._(
      PairingInvite(
        deviceId: device.id,
        deviceName: device.name,
        publicKey: await SyncPrimitives.publicKeyOf(keyPair),
        secret: SyncPrimitives.randomBytes(32),
        hosts: hosts,
        port: server.port,
      ),
      keyPair,
      server,
    );
  }

  final PairingInvite invite;
  final SimpleKeyPair _keyPair;
  final ServerSocket _server;

  /// Waits for the first device to connect and runs the handshake with it.
  /// The listener closes afterwards either way, so the code works once.
  Future<(FrameChannel, PairingResult)> accept() async {
    final socket = await _server.first;
    await _server.close();
    final channel = SyncNetwork.channelFor(socket);
    try {
      final result = await Pairing.inviterHandshake(
        channel: channel,
        keyPair: _keyPair,
        invite: invite,
      );
      return (channel, result);
    } on Object {
      await channel.close();
      rethrow;
    }
  }

  Future<void> close() => _server.close();
}
