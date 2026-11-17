import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import 'fakes/fakes.dart';

/// The main activity and the Credential Manager activity each run their own
/// Flutter engine: two isolates, two `VaultFile` queues, one file on disk.
/// Each `ProviderContainer` here stands for one engine.
void main() {
  const password = 'correct horse';

  late FakeSecureStorage storage;
  late InMemoryFileStore fileStore;

  setUp(() async {
    storage = FakeSecureStorage();
    fileStore = InMemoryFileStore();
    final setup = await MasterAuthService(
      storage: storage,
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
      fileStore: fileStore,
      clock: FixedClock(DateTime(2026, 7, 5)),
    ).setup(password);
    await VaultRepository(
      file: VaultFile(fileStore),
      cipher: const CipherService(),
      worker: const InlineWorker(),
    ).save([makeEntry(id: 'a', title: 'GitHub')], setup.key, setup.salt);
  });

  ProviderContainer engine() {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        fileStoreProvider.overrideWithValue(fileStore),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
        systemClipboardProvider.overrideWithValue(FakeClipboard()),
      ],
    );
    addTearDown(container.dispose);
    container
      ..listen(sessionProvider, (_, __) {})
      ..listen(vaultEntriesProvider, (_, __) {});
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<VaultNotifier> unlock(ProviderContainer c) async {
    await c.read(sessionProvider.notifier).unlock(password);
    return c.read(vaultEntriesProvider.notifier);
  }

  List<String> titles(ProviderContainer c) =>
      c.read(vaultEntriesProvider).requireValue.map((e) => e.title).toList();

  test(
      'an entry saved by another engine while this one is locked is opened '
      'by the next unlock and survives the next save', () async {
    final main = engine();
    await settle();
    expect(main.read(sessionProvider), AuthStatus.locked);

    final other = engine();
    await settle();
    await (await unlock(other)).create(
      title: 'Saved elsewhere',
      username: 'u',
      password: 'p',
      url: 'example.com',
      notes: '',
      category: EntryCategory.login,
    );

    final vault = await unlock(main);
    expect(titles(main), ['GitHub', 'Saved elsewhere']);

    await vault.toggleFavorite('a');
    final reopened = engine();
    await settle();
    await unlock(reopened);
    expect(titles(reopened), ['GitHub', 'Saved elsewhere']);
  });

  test('a vault file deleted by another engine opens as empty', () async {
    final main = engine();
    await settle();
    await engine().read(vaultFileProvider).delete();

    await unlock(main);
    expect(titles(main), isEmpty);
  });
}
