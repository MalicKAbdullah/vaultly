import 'dart:convert';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// This device's identity in pairings: a random id and a display name.
@immutable
final class LocalDevice {
  const LocalDevice({required this.id, required this.name});

  final String id;
  final String name;
}

/// A device this one has paired with, and the 32-byte key both share.
@immutable
final class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.key,
    required this.pairedAt,
    this.lastSyncAt,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        key: base64.decode(json['key'] as String),
        pairedAt: DateTime.parse(json['pairedAt'] as String),
        lastSyncAt: json['lastSyncAt'] == null
            ? null
            : DateTime.parse(json['lastSyncAt'] as String),
      );

  final String id;
  final String name;
  final Uint8List key;
  final DateTime pairedAt;
  final DateTime? lastSyncAt;

  PairedDevice syncedAt(DateTime at) => PairedDevice(
        id: id,
        name: name,
        key: key,
        pairedAt: pairedAt,
        lastSyncAt: at,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': base64.encode(key),
        'pairedAt': pairedAt.toIso8601String(),
        if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toIso8601String(),
      };
}

/// Sync bookkeeping in secure storage: the device identity, paired devices
/// with their keys, and tombstones for deleted items.
final class SyncLedger {
  SyncLedger({
    required ISecureStorage storage,
    required String Function() newDeviceId,
    required String defaultDeviceName,
  })  : _storage = storage,
        _newDeviceId = newDeviceId,
        _defaultName = defaultDeviceName;

  final ISecureStorage _storage;
  final String Function() _newDeviceId;
  final String _defaultName;

  /// This device's identity, created on first use.
  Future<LocalDevice> device() async {
    final raw = await _storage.read(key: VaultKeyKeys.syncDevice);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return LocalDevice(
        id: json['id'] as String,
        name: json['name'] as String,
      );
    }
    final id = _newDeviceId();
    final device = LocalDevice(
      id: id,
      name: '$_defaultName · ${id.substring(0, 4).toUpperCase()}',
    );
    await _storage.write(
      key: VaultKeyKeys.syncDevice,
      value: jsonEncode({'id': device.id, 'name': device.name}),
    );
    return device;
  }

  Future<List<PairedDevice>> peers() async {
    final raw = await _storage.read(key: VaultKeyKeys.syncPeers);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(PairedDevice.fromJson)
        .toList();
  }

  Future<PairedDevice?> peer(String id) async {
    for (final p in await peers()) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds [device], replacing an earlier pairing with the same id.
  Future<void> savePeer(PairedDevice device) async => _writePeers([
        for (final p in await peers())
          if (p.id != device.id) p,
        device,
      ]);

  Future<void> removePeer(String id) async => _writePeers([
        for (final p in await peers())
          if (p.id != id) p
      ]);

  Future<void> markSynced(String id, DateTime at) async => _writePeers([
        for (final p in await peers()) p.id == id ? p.syncedAt(at) : p,
      ]);

  Future<void> _writePeers(List<PairedDevice> peers) => _storage.write(
        key: VaultKeyKeys.syncPeers,
        value: jsonEncode(peers.map((p) => p.toJson()).toList()),
      );

  Future<Map<String, DateTime>> tombstones() async {
    final raw = await _storage.read(key: VaultKeyKeys.syncTombstones);
    if (raw == null) return const {};
    return {
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        e.key: DateTime.parse(e.value as String),
    };
  }

  Future<void> replaceTombstones(Map<String, DateTime> tombstones) =>
      _storage.write(
        key: VaultKeyKeys.syncTombstones,
        value: jsonEncode({
          for (final t in tombstones.entries) t.key: t.value.toIso8601String(),
        }),
      );

  /// Records a vault write from [before] to [after]: items that disappeared
  /// get a tombstone at [at] (an existing one keeps its time), and items
  /// that exist again lose theirs.
  Future<void> trackWrite({
    required List<VaultEntry> before,
    required List<VaultEntry> after,
    required DateTime at,
  }) async {
    final current = await tombstones();
    final present = {for (final e in after) e.id};
    final next = <String, DateTime>{
      for (final t in current.entries)
        if (!present.contains(t.key)) t.key: t.value,
      for (final e in before)
        if (!present.contains(e.id) && !current.containsKey(e.id)) e.id: at,
    };
    if (mapEquals(next, current)) return;
    await replaceTombstones(next);
  }
}
