import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  late FakeClipboard clipboard;

  Future<void> pumpDetail(WidgetTester tester, VaultEntry entry) async {
    clipboard = FakeClipboard();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => FakeVaultNotifier([entry])),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
          systemClipboardProvider.overrideWithValue(clipboard),
        ],
        child: MaterialApp(home: EntryDetailScreen(entryId: entry.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  final card = makeEntry(
    id: 'visa',
    title: 'Visa',
    username: '',
    password: '',
    url: '',
    category: EntryCategory.card,
    card: const CardDetails(
      holder: 'Ada Lovelace',
      number: '4242424242424242',
      expMonth: '07',
      expYear: '2030',
      cvc: '987',
    ),
  );

  testWidgets('card number and code stay masked until revealed',
      (tester) async {
    await pumpDetail(tester, card);

    expect(find.text('•••• •••• •••• 4242'), findsOneWidget);
    expect(find.text('4242 4242 4242 4242'), findsNothing);
    expect(find.text('987'), findsNothing);
    expect(find.text('07/30'), findsOneWidget);

    await tester.tap(find.byTooltip('Reveal card number'));
    await tester.pumpAndSettle();
    expect(find.text('4242 4242 4242 4242'), findsOneWidget);

    await tester.tap(find.byTooltip('Reveal security code'));
    await tester.pumpAndSettle();
    expect(find.text('987'), findsOneWidget);
  });

  testWidgets('copying the card number clears like a password', (tester) async {
    await pumpDetail(tester, card);

    await tester.tap(find.text('Copy card number'));
    await tester.pump();
    expect(clipboard.text, '4242424242424242');
    expect(find.textContaining('It clears in 30 seconds'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy security code'));
    await tester.pump();
    expect(clipboard.text, '987');
    expect(find.textContaining('It clears in 30 seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    expect(clipboard.text, '');
  });

  testWidgets('an identity shows contact and address', (tester) async {
    await pumpDetail(
      tester,
      makeEntry(
        id: 'home',
        title: 'Home',
        username: '',
        password: '',
        url: '',
        category: EntryCategory.identity,
        identity: const IdentityDetails(
          fullName: 'Ada Lovelace',
          phone: '+44 20 7946 0000',
          address1: '12 St James Square',
          city: 'London',
          postalCode: 'SW1Y 4JH',
        ),
      ),
    );

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('+44 20 7946 0000'), findsOneWidget);
    expect(find.text('12 St James Square\nLondon SW1Y 4JH'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password changed'), findsNothing);
  });
}
