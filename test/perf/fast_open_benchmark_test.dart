import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/sliver_row_group.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/vault_list_screen.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

import '../fakes/fakes.dart';
import '../widgets/helpers.dart';
import 'naive.dart';
import 'vault_fixture.dart';

/// Fast-open benchmarks on a realistic 1,000-item vault. Numbers are
/// printed (see docs/PERFORMANCE.md); assertions are only loose sanity
/// checks so CI stays stable.
void main() {
  const size = 1000;
  const runs = 7;
  final entries = realisticVault(size);
  final now = DateTime(2026, 10, 20);

  int median(List<int> xs) => (List.of(xs)..sort())[xs.length ~/ 2];

  /// Runs [body] while a 1 ms heartbeat on this isolate records its longest
  /// gap: how long the UI isolate could not run anything else.
  Future<({int totalUs, int stallUs})> measure(
    Future<void> Function() body,
  ) async {
    var last = Stopwatch()..start();
    var stall = 0;
    final beat = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final gap = last.elapsedMicroseconds;
      if (gap > stall) stall = gap;
      last = Stopwatch()..start();
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));
    stall = 0;
    last = Stopwatch()..start();
    final total = Stopwatch()..start();
    await body();
    total.stop();
    // The gap that was still open when the work finished.
    if (last.elapsedMicroseconds > stall) stall = last.elapsedMicroseconds;
    beat.cancel();
    return (totalUs: total.elapsedMicroseconds, stallUs: stall);
  }

  Future<void> report(
    String label,
    Future<void> Function() body,
  ) async {
    final totals = <int>[];
    final stalls = <int>[];
    await body(); // warm-up
    for (var i = 0; i < runs; i++) {
      final r = await measure(body);
      totals.add(r.totalUs);
      stalls.add(r.stallUs);
    }
    // ignore: avoid_print
    print(
      '$label: total ${(median(totals) / 1000).toStringAsFixed(1)} ms, '
      'UI isolate blocked ${(median(stalls) / 1000).toStringAsFixed(1)} ms',
    );
  }

  group('decrypt + parse $size entries', () {
    late Uint8List key;
    late EncryptedPayload payload;

    setUpAll(() async {
      key = Uint8List.fromList(List.generate(32, (i) => i));
      final salt = Uint8List(32);
      final fileStore = InMemoryFileStore();
      await VaultRepository(
        fileStore: fileStore,
        cipher: const CipherService(),
        worker: const InlineWorker(),
      ).save(entries, key, salt);
      payload = EncryptedPayload.fromBytes(fileStore.bytes!);
    });

    test('UI isolate vs worker isolate', () async {
      Future<void> decodeOn(IBackgroundWorker worker) async {
        final repo = VaultRepository(
          fileStore: InMemoryFileStore(),
          cipher: const CipherService(),
          worker: worker,
        );
        final opened = await repo.open(payload, key);
        expect(opened, hasLength(size));
      }

      await report('decode, UI isolate', () => decodeOn(const InlineWorker()));
      await report(
        'decode, worker isolate',
        () => decodeOn(const IsolateWorker()),
      );
    });
  });

  test('health analysis of $size entries', () async {
    await report('health, naive on UI isolate', () async {
      Naive.analyze(entries, now: now);
    });
    await report('health, memoised on UI isolate', () async {
      VaultHealthAnalyzer.analyze(entries, now: now);
    });
    await report('health, worker isolate', () async {
      await VaultHealthAnalyzer.analyzeOn(
        const IsolateWorker(),
        entries,
        now: now,
      );
    });
  });

  group('first vault-list frame, $size entries', () {
    Widget tile(VaultEntry e) => EntryTile(
          key: ValueKey(e.id),
          entry: e,
          onTap: () {},
          onCopyPassword: () {},
          onCopyUsername: () {},
          onEdit: () {},
          onDelete: () {},
        );

    Widget app(Widget sliver) => MaterialApp(
          theme: AppTheme.build(Brightness.light, accent: AppAccents.vaultly),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                  ),
                  sliver: sliver,
                ),
              ],
            ),
          ),
        );

    Future<int> firstFrameUs(
      WidgetTester tester,
      Widget Function() build,
    ) async {
      final times = <int>[];
      for (var i = 0; i < runs; i++) {
        await tester.pumpWidget(const SizedBox());
        final sw = Stopwatch()..start();
        await tester.pumpWidget(build());
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      return median(times);
    }

    testWidgets('eager RowGroup vs lazy SliverRowGroup', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.reset);

      final eager = await firstFrameUs(
        tester,
        () => app(
          SliverToBoxAdapter(
            child: RowGroup(
              separatorIndent: 74,
              children: [for (final e in entries) tile(e)],
            ),
          ),
        ),
      );
      final eagerTiles = find.byType(EntryTile).evaluate().length;

      final lazy = await firstFrameUs(
        tester,
        () => app(
          SliverRowGroup(
            separatorIndent: 74,
            itemCount: entries.length,
            itemBuilder: (_, i) => tile(entries[i]),
          ),
        ),
      );
      final lazyTiles = find.byType(EntryTile).evaluate().length;

      // ignore: avoid_print
      print(
        'list frame, eager RowGroup: ${(eager / 1000).toStringAsFixed(1)} ms '
        '($eagerTiles tiles built)\n'
        'list frame, lazy SliverRowGroup: '
        '${(lazy / 1000).toStringAsFixed(1)} ms ($lazyTiles tiles built)',
      );
      expect(lazy, lessThanOrEqualTo(eager));
      expect(lazyTiles, lessThan(eagerTiles));
    });

    testWidgets('whole VaultListScreen', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.reset);

      final us = await firstFrameUs(
        tester,
        () => ProviderScope(
          overrides: [
            vaultEntriesProvider.overrideWith(() => FakeVaultNotifier(entries)),
            secureStorageProvider.overrideWithValue(FakeSecureStorage()),
            backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
            clockProvider.overrideWithValue(FixedClock(now)),
            systemClipboardProvider.overrideWithValue(FakeClipboard()),
          ],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light, accent: AppAccents.vaultly),
            home: const VaultListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print(
        'list frame, whole VaultListScreen (lazy): '
        '${(us / 1000).toStringAsFixed(1)} ms',
      );

      // The old overview estimated every password's strength on each build.
      final sw = Stopwatch()..start();
      Naive.analyze(entries, now: now);
      // ignore: avoid_print
      print(
        'overview build, strength of every password (no longer per build): '
        '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms',
      );
    });
  });
}
