import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/sync/services/sync_ledger.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late SyncLedger ledger;
  final at = DateTime.utc(2026, 10, 2);

  setUp(() {
    storage = FakeSecureStorage();
    ledger = SyncLedger(
      storage: storage,
      newDeviceId: () => 'abcd1234-device',
      defaultDeviceName: 'Android',
    );
  });

  test('the device identity is created once and then kept', () async {
    final first = await ledger.device();
    expect(first.id, 'abcd1234-device');
    expect(first.name, 'Android · ABCD');
    final again = await SyncLedger(
      storage: storage,
      newDeviceId: () => 'other',
      defaultDeviceName: 'x',
    ).device();
    expect(again.id, first.id);
  });

  test('peers are saved, replaced by id, marked synced and removed', () async {
    final key = Uint8List.fromList(List.filled(32, 7));
    await ledger.savePeer(PairedDevice(
      id: 'p1',
      name: 'Pixel',
      key: key,
      pairedAt: at,
    ));
    await ledger.savePeer(PairedDevice(
      id: 'p1',
      name: 'Pixel renamed',
      key: key,
      pairedAt: at,
    ));
    expect((await ledger.peers()).single.name, 'Pixel renamed');
    await ledger.markSynced('p1', at);
    expect((await ledger.peer('p1'))!.lastSyncAt, at);
    expect((await ledger.peer('p1'))!.key, key);
    await ledger.removePeer('p1');
    expect(await ledger.peers(), isEmpty);
  });

  group('trackWrite', () {
    final a = makeEntry(id: 'a');
    final b = makeEntry(id: 'b');

    test('a removed item gets a tombstone', () async {
      await ledger.trackWrite(before: [a, b], after: [a], at: at);
      expect(await ledger.tombstones(), {'b': at});
    });

    test('an existing tombstone keeps its time', () async {
      final earlier = DateTime.utc(2026, 9, 1);
      await ledger.replaceTombstones({'b': earlier});
      await ledger.trackWrite(before: [a, b], after: [a], at: at);
      expect(await ledger.tombstones(), {'b': earlier});
    });

    test('an item that exists again loses its tombstone', () async {
      await ledger.replaceTombstones({'b': at});
      await ledger.trackWrite(before: [a], after: [a, b], at: at);
      expect(await ledger.tombstones(), isEmpty);
    });

    test('a write that removes nothing does not touch storage', () async {
      await ledger.trackWrite(before: [a], after: [a, b], at: at);
      expect(storage.store.containsKey(VaultKeyKeys.syncTombstones), isFalse);
    });
  });

  test('erase-all clears the sync keys', () {
    expect(
      VaultKeyKeys.all,
      containsAll([
        VaultKeyKeys.syncDevice,
        VaultKeyKeys.syncPeers,
        VaultKeyKeys.syncTombstones,
      ]),
    );
  });
}
