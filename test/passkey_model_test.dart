import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

const _passkey = PasskeyCredential(
  rpId: 'webauthn.io',
  rpName: 'WebAuthn.io',
  userName: 'alice',
  userDisplayName: 'Alice',
  credentialId: 'Y3JlZC1pZA',
  userHandle: 'dXNlci00Mg',
  publicKey: 'cHVibGljLWtleQ',
  privateKey: 'UFJJVkFURS1LRVktREVS',
);

VaultEntry passkeyEntry({DateTime? lastUsedAt}) => VaultEntry(
      id: 'pk-1',
      title: 'WebAuthn.io',
      username: 'alice',
      url: 'webauthn.io',
      category: EntryCategory.passkey,
      passkey: lastUsedAt == null ? _passkey : _passkey.usedAt(lastUsedAt),
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      passwordChangedAt: DateTime(2026, 9, 1),
    );

void main() {
  group('passkey entries in the vault model', () {
    test('vaults written before passkeys still load, with no passkey', () {
      const legacy = '''
      {"version": 1, "entries": [{
        "id": "legacy-1", "title": "Mail", "username": "jo", "password": "pw",
        "url": "mail.example.com", "notes": "", "category": "login",
        "favorite": false, "createdAt": "2026-01-10T09:00:00.000",
        "updatedAt": "2026-01-10T09:00:00.000",
        "passwordChangedAt": "2026-01-10T09:00:00.000", "history": []
      }]}
      ''';
      final entry = VaultRepository.decodeEntries(legacy).single;
      expect(entry.passkey, isNull);
      expect(entry.category, EntryCategory.login);
      expect(entry.toJson().containsKey('passkey'), isFalse);
    });

    test('a passkey entry round-trips through the vault document', () {
      final entry = passkeyEntry(lastUsedAt: DateTime(2026, 10, 2, 8, 30));
      final decoded = VaultRepository.decodeEntries(
        VaultRepository.encodeEntries([entry, makeEntry()]),
      );
      expect(decoded.first, entry);
      expect(decoded.first.category, EntryCategory.passkey);
      expect(decoded.first.passkey!.privateKey, _passkey.privateKey);
      expect(decoded.first.passkey!.lastUsedAt, DateTime(2026, 10, 2, 8, 30));
      expect(decoded.last.passkey, isNull);
    });

    test('an unused passkey writes no lastUsedAt', () {
      final json = passkeyEntry().toJson()['passkey'] as Map<String, dynamic>;
      expect(json.containsKey('lastUsedAt'), isFalse);
      expect(PasskeyCredential.fromJson(json), _passkey);
    });

    test('copyWith keeps the passkey', () {
      final entry = passkeyEntry().copyWith(favorite: true);
      expect(entry.passkey, _passkey);
    });

    test('the private key is only in the encrypted vault file', () async {
      final store = InMemoryFileStore();
      final repo = VaultRepository(
        file: VaultFile(store),
        cipher: const CipherService(),
        worker: const IsolateWorker(),
      );
      const cipher = CipherService();
      final key = await FakeKeyDerivation()
          .deriveKey(password: 'master', salt: await cipher.generateSalt());
      await repo.save([passkeyEntry()], key, await cipher.generateSalt());

      final raw = latin1.decode(store.bytes!);
      expect(raw, isNot(contains(_passkey.privateKey)));
      expect((await repo.load(key)).single.passkey, _passkey);
    });
  });

  group('backup and export', () {
    test('encrypted backups carry passkeys', () async {
      final codec = BackupCodec(
        keyDerivation: FakeKeyDerivation(),
        cipher: const CipherService(),
        appVersion: () async => '9.9.9',
      );
      final content = await codec.encode(
        entries: [passkeyEntry(), makeEntry()],
        passphrase: 'backup passphrase',
        createdAt: DateTime.utc(2026, 10, 1),
      );
      expect(content, isNot(contains(_passkey.privateKey)));
      final restored =
          await codec.decode(content: content, passphrase: 'backup passphrase');
      expect(restored.first, passkeyEntry());
    });

    test('plain CSV export leaves passkeys out', () {
      final csv = CsvCodec.export([
        passkeyEntry(),
        makeEntry(title: 'Mail', password: 'pw'),
      ]);
      expect(csv, isNot(contains('WebAuthn.io')));
      expect(csv, isNot(contains(_passkey.privateKey)));
      expect(csv.trim().split('\r\n'), hasLength(2)); // header + Mail
    });
  });
}
