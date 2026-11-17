import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_editor_screen.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  late FakeVaultNotifier notifier;
  late ProviderContainer container;

  Future<void> pumpEditor(
    WidgetTester tester, {
    String? entryId,
    VaultEntry? existing,
  }) async {
    notifier = FakeVaultNotifier(
      entryId == null
          ? []
          : [existing ?? makeEntry(id: entryId, title: 'Existing')],
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

  Future<void> type(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
  }

  Future<void> save(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('a new card saves its fields and hides the sign-in form',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();

    expect(find.text('Username / email'), findsNothing);
    await type(tester, 'Title', 'Visa debit');
    await type(tester, 'Name on card', 'Ada Lovelace');
    await type(tester, 'Card number', '4242 4242 4242 4242');
    await type(tester, 'Expires', '7/30');
    await type(tester, 'Security code', '123');
    await save(tester, 'Add to vault');

    final entry = container.read(vaultEntriesProvider).valueOrNull!.single;
    expect(entry.category, EntryCategory.card);
    expect(
      entry.card,
      const CardDetails(
        holder: 'Ada Lovelace',
        number: '4242424242424242',
        expMonth: '07',
        expYear: '2030',
        cvc: '123',
      ),
    );
    expect(entry.identity, isNull);
    expect(entry.password, '');
  });

  testWidgets('a bad expiry is refused and nothing is saved', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();
    await type(tester, 'Title', 'Visa');
    await type(tester, 'Expires', '13/30');
    await save(tester, 'Add to vault');

    expect(find.text('Use MM/YY, like 07/30.'), findsOneWidget);
    expect(container.read(vaultEntriesProvider).valueOrNull, isEmpty);
  });

  testWidgets('a new identity saves contact and address', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Identity'));
    await tester.pumpAndSettle();
    await type(tester, 'Title', 'Home');
    await type(tester, 'Full name', 'Ada Lovelace');
    await type(tester, 'Email', 'ada@example.com');
    await type(tester, 'City', 'London');
    await type(tester, 'Postal code', 'SW1Y 4JH');
    await save(tester, 'Add to vault');

    final entry = container.read(vaultEntriesProvider).valueOrNull!.single;
    expect(
      entry.identity,
      const IdentityDetails(
        fullName: 'Ada Lovelace',
        email: 'ada@example.com',
        city: 'London',
        postalCode: 'SW1Y 4JH',
      ),
    );
    expect(entry.card, isNull);
  });

  testWidgets('a card stored in the sign-in fields keeps them on screen',
      (tester) async {
    await pumpEditor(
      tester,
      entryId: 'old',
      existing: makeEntry(
        id: 'old',
        title: 'Old card',
        category: EntryCategory.card,
        username: 'Jo Bloggs',
        password: '4111111111111111',
        url: '',
      ),
    );
    expect(find.text('Username / email'), findsOneWidget);
    expect(find.text('Card number'), findsOneWidget);
    await save(tester, 'Save changes');

    final entry = container.read(vaultEntriesProvider).valueOrNull!.single;
    expect(entry.username, 'Jo Bloggs');
    expect(entry.password, '4111111111111111');
    expect(entry.card, isNull);
  });

  testWidgets('editing keeps a four-digit expiry year', (tester) async {
    const card = CardDetails(number: '4111', expMonth: '12', expYear: '1999');
    await pumpEditor(
      tester,
      entryId: 'c',
      existing: makeEntry(
        id: 'c',
        title: 'Old',
        category: EntryCategory.card,
        username: '',
        password: '',
        url: '',
        card: card,
      ),
    );
    await save(tester, 'Save changes');
    final entry = container.read(vaultEntriesProvider).valueOrNull!.single;
    expect(entry.card, card);
  });

  testWidgets('switching category keeps a filled card form visible',
      (tester) async {
    const card = CardDetails(number: '4242424242424242', cvc: '321');
    await pumpEditor(
      tester,
      entryId: 'c',
      existing: makeEntry(
        id: 'c',
        title: 'Card',
        category: EntryCategory.card,
        username: '',
        password: '',
        url: '',
        card: card,
      ),
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Card number'), findsOneWidget);
    await save(tester, 'Save changes');

    final entry = container.read(vaultEntriesProvider).valueOrNull!.single;
    expect(entry.category, EntryCategory.login);
    expect(entry.card, card);
  });
}
