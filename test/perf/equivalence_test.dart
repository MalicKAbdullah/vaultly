import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../widgets/helpers.dart';
import 'naive.dart';
import 'vault_fixture.dart';

void main() {
  final now = DateTime(2026, 10, 20);

  void expectSameReport(VaultHealthReport a, VaultHealthReport b) {
    expect(a.score, b.score);
    expect(a.analyzedCount, b.analyzedCount);
    expect(a.strongCount, b.strongCount);
    expect(a.weak.map((e) => e.id), b.weak.map((e) => e.id));
    expect(a.reused.map((e) => e.id), b.reused.map((e) => e.id));
    expect(a.old.map((e) => e.id), b.old.map((e) => e.id));
  }

  for (final seed in [1, 2, 3, 4, 5]) {
    test('health analysis matches the straightforward one (seed $seed)',
        () async {
      final entries = realisticVault(1000, seed: seed);
      final reference = Naive.analyze(entries, now: now);
      expectSameReport(
          VaultHealthAnalyzer.analyze(entries, now: now), reference);
      final viaWorker = await VaultHealthAnalyzer.analyzeOn(
        const IsolateWorker(),
        entries,
        now: now,
      );
      expectSameReport(viaWorker, reference);
      // Findings map back to the caller's own entry objects.
      for (final e in viaWorker.weak) {
        expect(entries.any((x) => identical(x, e)), isTrue);
      }
    });

    test('A-to-Z sort matches the straightforward one (seed $seed)', () {
      final entries = realisticVault(1000, seed: seed);
      final container = ProviderContainer(
        overrides: [
          vaultEntriesProvider.overrideWith(() => FakeVaultNotifier(entries)),
        ],
      );
      addTearDown(container.dispose);
      container.read(vaultQueryProvider.notifier).setSort(
            VaultSort.alphabetical,
          );
      return container.read(vaultEntriesProvider.future).then((_) {
        expect(
          container.read(filteredEntriesProvider).map((e) => e.id),
          Naive.sortAlphabetical(entries).map((e) => e.id),
        );
      });
    });
  }

  test('tally counts match per-filter passes', () async {
    final entries = realisticVault(1000);
    final container = ProviderContainer(
      overrides: [
        vaultEntriesProvider.overrideWith(() => FakeVaultNotifier(entries)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultEntriesProvider.future);
    final tally = container.read(vaultTallyProvider);
    expect(tally.total, entries.length);
    expect(tally.favorites, entries.where((e) => e.favorite).length);
    expect(tally.withTotp, entries.where((e) => e.totp != null).length);
    expect(
      tally.withPassword,
      entries.where((e) => e.password.isNotEmpty).length,
    );
    for (final c in EntryCategory.values) {
      expect(tally.byCategory[c], entries.where((e) => e.category == c).length);
    }
  });
}
