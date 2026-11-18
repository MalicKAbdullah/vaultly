import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/screens/save_login_screen.dart';
import 'package:vaultkey/src/features/health/services/fix_it.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  Future<(FakeAutofillBridge, ProviderContainer)> pump(
    WidgetTester tester,
    CapturedLogin login,
    List seed, {
    FixTarget? fix,
  }) async {
    final bridge = FakeAutofillBridge()..save = login;
    final container = ProviderContainer(
      overrides: [
        autofillBridgeProvider.overrideWithValue(bridge),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
        vaultEntriesProvider.overrideWith(
          () => FakeVaultNotifier([...seed.cast()]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(fixTargetProvider.notifier).state = fix;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SaveLoginScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (bridge, container);
  }

  testWidgets('a new login is saved and the screen closes', (tester) async {
    final (bridge, container) = await pump(
      tester,
      const CapturedLogin(username: 'ada', password: 'pw', host: 'a.com'),
      const [],
    );
    expect(find.text('Save password to Vaultly?'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();
    final saved = container.read(vaultEntriesProvider).requireValue.single;
    expect((saved.title, saved.username, saved.password, saved.url),
        ('a.com', 'ada', 'pw', 'a.com'));
    expect(bridge.finishedSaves, ['Saved to Vaultly']);
  });

  testWidgets('a changed password updates the entry and keeps the old one', (
    tester,
  ) async {
    final entry = makeEntry(
      id: 'a',
      title: 'A',
      username: 'ada',
      password: 'old',
      url: 'a.com',
    );
    final (bridge, container) = await pump(
      tester,
      const CapturedLogin(username: 'ada', password: 'new', host: 'a.com'),
      [entry],
    );
    expect(find.text('Update A?'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump();
    final e = container.read(vaultEntriesProvider).requireValue.single;
    expect(e.password, 'new');
    expect(e.history.single.password, 'old');
    expect(bridge.finishedSaves, ['Password updated']);
  });

  testWidgets('a login that is already saved only offers Done', (tester) async {
    final entry = makeEntry(
      id: 'a',
      username: 'ada',
      password: 'same',
      url: 'a.com',
    );
    final (bridge, container) = await pump(
      tester,
      const CapturedLogin(username: 'ada', password: 'same', host: 'a.com'),
      [entry],
    );
    expect(find.text('Already saved'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(bridge.finishedSaves, ['Already saved']);
    expect(container.read(vaultEntriesProvider).requireValue.length, 1);
  });

  testWidgets('Not now leaves the vault untouched', (tester) async {
    final (bridge, container) = await pump(
      tester,
      const CapturedLogin(username: 'ada', password: 'pw', host: 'a.com'),
      const [],
    );
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(bridge.finishedSaves, [null]);
    expect(container.read(vaultEntriesProvider).requireValue, isEmpty);
  });

  testWidgets('a fix target sends the new password to that entry', (
    tester,
  ) async {
    final ada = makeEntry(id: 'a', title: 'A', username: 'ada', url: 'a.com');
    final bob = makeEntry(id: 'b', title: 'B', username: 'bob', url: 'a.com');
    final (_, container) = await pump(
      tester,
      const CapturedLogin(username: 'ada', password: 'new', host: 'a.com'),
      [ada, bob],
      fix: FixTarget(
        entryId: 'b',
        host: 'a.com',
        expiresAt: DateTime(2026, 7, 5, 0, 10),
      ),
    );
    expect(find.text('Update B?'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump();
    final entries = container.read(vaultEntriesProvider).requireValue;
    expect(entries.firstWhere((e) => e.id == 'b').password, 'new');
    expect(entries.firstWhere((e) => e.id == 'a').password, ada.password);
  });

  testWidgets('an expired fix target is ignored', (tester) async {
    final ada = makeEntry(id: 'a', title: 'A', username: 'ada', url: 'a.com');
    final bob = makeEntry(id: 'b', title: 'B', username: 'bob', url: 'a.com');
    await pump(
      tester,
      const CapturedLogin(username: 'zed', password: 'new', host: 'a.com'),
      [ada, bob],
      fix: FixTarget(
        entryId: 'b',
        host: 'a.com',
        expiresAt: DateTime(2026, 7, 4),
      ),
    );
    expect(find.text('Save password to Vaultly?'), findsOneWidget);
  });
}
