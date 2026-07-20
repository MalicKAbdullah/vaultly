import 'dart:typed_data';

import 'package:core_backup/core_backup.dart';
import 'package:core_storage/core_storage.dart';
import 'package:vaultkey/src/core/clock.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/core/interfaces/key_derivation.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/core/services/clipboard_guard.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// In-memory ISecureStorage — no platform channels.
final class FakeSecureStorage implements ISecureStorage {
  final Map<String, String> store = {};

  @override
  Future<void> write({required String key, required String value}) async {
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => store[key];

  @override
  Future<void> delete({required String key}) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll() async => store.clear();

  @override
  Future<Map<String, String>> readAll() async => Map.of(store);
}

/// In-memory vault file.
final class InMemoryFileStore implements IVaultFileStore {
  Uint8List? bytes;
  int writeCount = 0;

  @override
  Future<Uint8List?> read() async => bytes;

  @override
  Future<void> write(Uint8List data) async {
    bytes = Uint8List.fromList(data);
    writeCount++;
  }

  @override
  Future<void> delete() async {
    bytes = null;
  }
}

/// Fast deterministic KDF (FNV-1a over password+salt) standing in for
/// Argon2id. Different passwords or salts yield different 32-byte keys.
final class FakeKeyDerivation implements IKeyDerivation {
  @override
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
  }) async {
    final input = [...password.codeUnits, ...salt];
    final key = Uint8List(32);
    var hash = 0x811c9dc5;
    for (var i = 0; i < key.length; i++) {
      for (final byte in input) {
        hash ^= byte ^ i;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      key[i] = hash & 0xFF;
    }
    return key;
  }
}

/// Clock whose current time is controlled by the test.
final class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  void advance(Duration duration) => current = current.add(duration);

  @override
  DateTime now() => current;
}

/// In-memory clipboard.
final class FakeClipboard implements ISystemClipboard {
  String? text;

  @override
  Future<String?> getText() async => text;

  @override
  Future<void> setText(String value) async => text = value;
}

/// In-memory backup folder that records written files.
final class FakeBackupFolder implements IBackupFolder {
  BackupFolderSelection? selection =
      const BackupFolderSelection(uri: 'fake://backups', name: 'Backups');
  final Map<String, Uint8List> files = {};
  bool failWrites = false;

  @override
  Future<BackupFolderSelection?> pickFolder() async => selection;

  @override
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (failWrites) {
      throw Exception('folder unavailable');
    }
    files[fileName] = bytes;
  }
}

/// Scripted biometric prompt.
final class FakeBiometricAuthenticator implements IBiometricAuthenticator {
  FakeBiometricAuthenticator({this.supported = true, this.result = true});

  bool supported;
  bool result;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async => result;
}

/// Scripted autofill platform bridge; records what Flutter handed back.
final class FakeAutofillBridge implements IAutofillBridge {
  FakeAutofillBridge(
      {this.request, this.supported = true, this.enabled = false});

  AutofillFillRequest? request;
  bool supported;
  bool enabled;

  ({String username, String password, String label})? completed;
  bool cancelled = false;
  int openSettingsCalls = 0;

  @override
  Future<AutofillFillRequest?> pendingRequest() async => request;

  @override
  Future<bool> complete({
    required String username,
    required String password,
    required String label,
  }) async {
    completed = (username: username, password: password, label: label);
    return true;
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}

/// Builds a [VaultEntry] with sensible defaults for tests.
VaultEntry makeEntry({
  String id = 'id-1',
  String title = 'Example',
  String username = 'user@example.com',
  String password = 'kV9#mQ2x!pW7zR4t',
  String url = 'example.com',
  String notes = '',
  EntryCategory category = EntryCategory.login,
  bool favorite = false,
  TotpConfig? totp,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? passwordChangedAt,
  List<PasswordHistoryEntry> history = const [],
}) {
  final created = createdAt ?? DateTime(2026, 6, 1);
  return VaultEntry(
    id: id,
    title: title,
    username: username,
    password: password,
    url: url,
    notes: notes,
    category: category,
    favorite: favorite,
    totp: totp,
    createdAt: created,
    updatedAt: updatedAt ?? created,
    passwordChangedAt: passwordChangedAt ?? created,
    history: history,
  );
}
