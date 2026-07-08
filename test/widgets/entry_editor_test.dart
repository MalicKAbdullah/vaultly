import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_editor_screen.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  late FakeVaultNotifier notifier;
  late ProviderContainer container;

  Future<void> pumpEditor(WidgetTester tester, {String? entryId}) async {
    notifier = FakeVaultNotifier(
      entryId == null ? [] : [makeEntry(id: entryId, title: 'Existing')],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/new',
          builder: (_, __) => const EntryEditorScreen(),
        ),
        GoRoute(
          path: '/edit/:id',
          builder: (_, state) =>
              EntryEditorScreen(entryId: state.pathParameters['id']),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => notifier),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.text('home')),
    );
    // Let the vault finish its initial (async) load before interacting, as
    // it would have in the real app where the list screen loads it first.
    await container.read(vaultEntriesProvider.future);
    router.push(entryId == null ? '/new' : '/edit/$entryId');
    await tester.pumpAndSettle();
  }

  testWidgets('saving without a title shows validation and saves nothing',
      (tester) async {
    await pumpEditor(tester);
    await tester.ensureVisible(find.text('Add to vault'));
    await tester.tap(find.text('Add to vault'));
    await tester.pumpAndSettle();

    expect(find.text('Give this entry a name.'), findsOneWidget);
    expect(container.read(vaultEntriesProvider).valueOrNull, isEmpty);
    // Still on the editor.
    expect(find.text('New entry'), findsOneWidget);
  });

  testWidgets('a valid entry is created and the editor closes', (tester) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Personal email'),
      'My site',
    );
    await tester.ensureVisible(find.text('Add to vault'));
    await tester.tap(find.text('Add to vault'));
    await tester.pumpAndSettle();

    final saved = container.read(vaultEntriesProvider).valueOrNull!;
    expect(saved.single.title, 'My site');
    // Back on home after saving.
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the inline generator fills the password field', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.casino_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Use this password'), findsOneWidget);
    await tester.ensureVisible(find.text('Use this password'));
    await tester.tap(find.text('Use this password'));
    await tester.pumpAndSettle();

    // Save and check the generated password landed on the entry.
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Personal email'),
      'Generated entry',
    );
    await tester.ensureVisible(find.text('Add to vault'));
    await tester.tap(find.text('Add to vault'));
    await tester.pumpAndSettle();

    final saved = container.read(vaultEntriesProvider).valueOrNull!;
    expect(saved.single.password.length, 20);
  });

  testWidgets('editing loads the existing entry and applies changes',
      (tester) async {
    await pumpEditor(tester, entryId: 'e1');

    expect(
      find.widgetWithText(TextField, 'Existing'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Existing'),
      'Renamed',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = container.read(vaultEntriesProvider).valueOrNull!;
    expect(saved.single.title, 'Renamed');
  });
}
