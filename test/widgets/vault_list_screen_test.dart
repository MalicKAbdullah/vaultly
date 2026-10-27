import 'dart:async';

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/vault_list_screen.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

import '../fakes/fakes.dart';
import '../perf/vault_fixture.dart';
import 'helpers.dart';

void main() {
  final entries = [
    makeEntry(
      id: '1',
      title: 'GitHub',
      username: 'octocat',
      url: 'github.com',
      updatedAt: DateTime(2026, 7, 1),
    ),
    makeEntry(
      id: '2',
      title: 'Bank of Dartland',
      username: 'jo@example.com',
      url: 'bank.example',
      favorite: true,
      category: EntryCategory.card,
      updatedAt: DateTime(2026, 6, 1),
    ),
    makeEntry(
      id: '3',
      title: 'Email',
      username: 'jo@example.com',
      url: 'mail.example',
      updatedAt: DateTime(2026, 5, 1),
    ),
  ];

  Future<void> pumpList(
    WidgetTester tester, {
    List<VaultEntry>? seed,
    VaultNotifier Function()? vault,
    bool settle = true,
  }) async {
    // A tall phone, so the overview and every row are laid out at once.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider
              .overrideWith(vault ?? () => FakeVaultNotifier(seed ?? entries)),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 7, 5)),
          ),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
        ],
        child: const MaterialApp(home: VaultListScreen()),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('shows every entry from the vault', (tester) async {
    await pumpList(tester);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Bank of Dartland'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('search narrows the list by title', (tester) async {
    await pumpList(tester);
    await tester.enterText(find.byType(TextField).first, 'git');
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Bank of Dartland'), findsNothing);
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('search matches usernames too', (tester) async {
    await pumpList(tester);
    await tester.enterText(find.byType(TextField).first, 'jo@example');
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Bank of Dartland'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('a search with no hits shows the no-results state',
      (tester) async {
    await pumpList(tester);
    await tester.enterText(find.byType(TextField).first, 'zzz-nothing');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches your search.'), findsOneWidget);
  });

  testWidgets('favorites filter keeps only starred entries', (tester) async {
    await pumpList(tester);
    await tester.tap(find.widgetWithText(AppChip, 'Favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Bank of Dartland'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('category filter keeps only that category', (tester) async {
    await pumpList(tester);
    await tester.ensureVisible(find.widgetWithText(AppChip, 'Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppChip, 'Card'));
    await tester.pumpAndSettle();

    expect(find.text('Bank of Dartland'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('an empty vault shows the getting-started message',
      (tester) async {
    await pumpList(tester, seed: const []);
    expect(
      find.textContaining('Your vault is empty'),
      findsOneWidget,
    );
  });

  testWidgets('delete asks for confirmation and removes the entry',
      (tester) async {
    await pumpList(tester);
    // Open the overflow menu on the first tile (GitHub, most recent).
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(EntryTile, 'GitHub'),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Delete "GitHub"?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Bank of Dartland'), findsOneWidget);
  });

  testWidgets('while the vault loads it shows skeleton rows, never "empty"',
      (tester) async {
    await pumpList(tester, vault: _PendingVault.new, settle: false);
    await tester.pump();
    expect(find.textContaining('Your vault is empty'), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);
  });

  testWidgets('a vault that failed to open shows an error, not "empty"',
      (tester) async {
    await pumpList(tester, vault: _BrokenVault.new);
    expect(find.textContaining('Your vault is empty'), findsNothing);
    expect(find.text('Your vault could not be opened'), findsOneWidget);
  });

  testWidgets('a 1,000-item vault builds only the rows on screen',
      (tester) async {
    final big = realisticVault(1000);
    await pumpList(tester, seed: big);
    final built = find.byType(EntryTile).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60));
    // The overview has its numbers once the background analysis is in.
    expect(find.byType(Skeleton), findsNothing);
  });
}

class _PendingVault extends VaultNotifier {
  @override
  Future<List<VaultEntry>> build() => Completer<List<VaultEntry>>().future;
}

class _BrokenVault extends VaultNotifier {
  @override
  List<VaultEntry> build() => throw StateError('decrypt failed');
}
