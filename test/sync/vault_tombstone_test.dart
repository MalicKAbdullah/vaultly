import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';

void main() {
  test('deleting an entry records a sync tombstone; re-adding clears it',
      () async {
    final clock = FixedClock(DateTime.utc(2026, 10, 5, 9));
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      fileStoreProvider.overrideWithValue(InMemoryFileStore()),
      keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
      clockProvider.overrideWithValue(clock),
      backupFolderProvider.overrideWithValue(FakeBackupFolder()),
    ]);
    addTearDown(container.dispose);

    container.read(sessionProvider);
    await Future<void>.delayed(Duration.zero);
    await container.read(sessionProvider.notifier).setup('correct horse 42');
    await container.read(vaultEntriesProvider.future);
    final vault = container.read(vaultEntriesProvider.notifier);
    final ledger = container.read(syncLedgerProvider);

    final entry = await vault.create(
      title: 'Doomed',
      username: 'me',
      password: 'pw',
      url: '',
      notes: '',
      category: EntryCategory.login,
    );
    expect(await ledger.tombstones(), isEmpty);

    clock.advance(const Duration(minutes: 1));
    await vault.delete(entry.id);
    expect(await ledger.tombstones(), {entry.id: clock.now()});

    await vault.replaceAll([entry]);
    expect(await ledger.tombstones(), isEmpty);
  });
}
