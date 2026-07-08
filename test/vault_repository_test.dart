import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

void main() {
  late InMemoryFileStore fileStore;
  late VaultRepository repo;
  late Uint8List key;
  late Uint8List salt;

  setUp(() async {
    fileStore = InMemoryFileStore();
    repo = VaultRepository(fileStore: fileStore, cipher: const CipherService());
    salt = Uint8List.fromList(List.generate(32, (i) => i));
    key = await FakeKeyDerivation().deriveKey(password: 'pw', salt: salt);
  });

  group('VaultRepository', () {
    test('load returns empty list when no vault file exists', () async {
      expect(await repo.load(key), isEmpty);
    });

    test('save/load round-trips entries with all fields and history', () async {
      final entries = [
        makeEntry(
          id: 'a',
          title: 'Email',
          notes: 'multi\nline',
          favorite: true,
          history: [
            PasswordHistoryEntry(
              password: 'previous-1',
              replacedAt: DateTime(2026, 4, 1),
            ),
            PasswordHistoryEntry(
              password: 'previous-2',
              replacedAt: DateTime(2026, 2, 1),
            ),
          ],
        ),
        makeEntry(id: 'b', category: EntryCategory.identity),
      ];
      await repo.save(entries, key, salt);
      expect(await repo.load(key), entries);
    });

    test('vault file bytes never contain plaintext passwords', () async {
      await repo.save([makeEntry(id: 'a')], key, salt);
      final raw = String.fromCharCodes(fileStore.bytes!);
      expect(raw.contains('kV9#mQ2x!pW7zR4t'), isFalse);
      expect(raw.contains('Example'), isFalse);
    });

    test('a wrong key cannot decrypt the vault', () async {
      await repo.save([makeEntry(id: 'a')], key, salt);
      final wrongKey =
          await FakeKeyDerivation().deriveKey(password: 'other', salt: salt);
      expect(() => repo.load(wrongKey), throwsA(anything));
    });

    test('tampered file bytes fail AES-GCM authentication', () async {
      await repo.save([makeEntry(id: 'a')], key, salt);
      final tampered = Uint8List.fromList(fileStore.bytes!);
      tampered[tampered.length - 1] ^= 0xFF;
      fileStore.bytes = tampered;
      expect(() => repo.load(key), throwsA(anything));
    });

    test('saving again replaces the previous vault content', () async {
      await repo.save([makeEntry(id: 'a')], key, salt);
      await repo.save([makeEntry(id: 'b', title: 'Only')], key, salt);
      final loaded = await repo.load(key);
      expect(loaded.single.id, 'b');
      expect(fileStore.writeCount, 2);
    });
  });
}
