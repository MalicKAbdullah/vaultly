import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/vault_list_screen.dart';

import '../fakes/fakes.dart';
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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider
              .overrideWith(() => FakeVaultNotifier(seed ?? entries)),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 7, 5)),
          ),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
        ],
        child: const MaterialApp(home: VaultListScreen()),
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Bank of Dartland'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('category filter keeps only that category', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('Card'));
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
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Delete "GitHub"?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Bank of Dartland'), findsOneWidget);
  });
}
