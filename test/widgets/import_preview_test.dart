import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/screens/import_preview_screen.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  const batch = ImportBatch(
    source: ImportSource.chrome,
    items: [
      ImportedItem(
        title: 'GitHub',
        url: 'https://github.com',
        username: 'user@example.com',
        password: 'new-pw',
      ),
      ImportedItem(title: 'Fresh', url: 'fresh.example', username: 'me'),
    ],
    authenticators: [
      ImportedAuthenticator(
        config: TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
        issuer: 'Slack',
        account: 'me',
      ),
    ],
    warnings: ['"Odd": the two-factor secret was not recognised.'],
  );

  Future<FakeVaultNotifier> pump(WidgetTester tester) async {
    final notifier = FakeVaultNotifier([
      makeEntry(id: 'gh', title: 'GitHub', url: 'github.com'),
    ]);
    final router = GoRouter(
      initialLocation: '/preview',
      routes: [
        GoRoute(
          path: '/preview',
          builder: (_, __) => const ImportPreviewScreen(batch: batch),
        ),
        GoRoute(
          path: '/vault',
          builder: (_, __) => const Scaffold(body: Text('vault')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => notifier),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 10, 1))),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('shows counts, duplicates and warnings; skip imports the rest',
      (tester) async {
    final notifier = await pump(tester);
    expect(find.text('2 items · 1 authenticator code'), findsOneWidget);
    expect(find.text('Duplicates'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('1 record needs attention'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Import 2 changes'));
    await tester.pumpAndSettle();

    expect(find.text('vault'), findsOneWidget);
    final entries = notifier.state.value!;
    expect(entries.map((e) => e.title), ['GitHub', 'Fresh', 'Slack']);
    expect(entries.first.password, isNot('new-pw'));
  });

  testWidgets('merge updates the duplicate instead', (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 3 changes'));
    await tester.pumpAndSettle();

    final gh = notifier.state.value!.firstWhere((e) => e.id == 'gh');
    expect(gh.password, 'new-pw');
    expect(gh.history.first.password, 'kV9#mQ2x!pW7zR4t');
  });
}
