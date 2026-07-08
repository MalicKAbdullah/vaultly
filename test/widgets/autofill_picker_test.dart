import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/autofill/screens/autofill_picker_screen.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  final entries = [
    makeEntry(
      id: 'gh',
      title: 'GitHub',
      username: 'octocat',
      password: 'gh-secret',
      url: 'github.com',
    ),
    makeEntry(
      id: 'bank',
      title: 'Bank of Dartland',
      username: 'jo@example.com',
      password: 'bank-secret',
      url: 'bank.example',
    ),
  ];

  group('AutofillPickerScreen', () {
    late FakeAutofillBridge bridge;

    Future<void> pumpPicker(
      WidgetTester tester, {
      AutofillFillRequest? request,
    }) async {
      bridge = FakeAutofillBridge(
        request: request ?? const AutofillFillRequest(domain: 'github.com'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultEntriesProvider.overrideWith(() => FakeVaultNotifier(entries)),
            autofillBridgeProvider.overrideWithValue(bridge),
            secureStorageProvider.overrideWithValue(FakeSecureStorage()),
            systemClipboardProvider.overrideWithValue(FakeClipboard()),
            clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 7))),
          ],
          child: const MaterialApp(home: AutofillPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('pre-filters the list by the requesting domain',
        (tester) async {
      await pumpPicker(tester);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Bank of Dartland'), findsNothing);
      expect(find.textContaining('github.com'), findsOneWidget);
    });

    testWidgets('falls back to the full list when nothing matches',
        (tester) async {
      await pumpPicker(
        tester,
        request: const AutofillFillRequest(domain: 'unknown.example'),
      );
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Bank of Dartland'), findsOneWidget);
    });

    testWidgets('searching looks through the whole vault', (tester) async {
      await pumpPicker(tester);
      await tester.enterText(find.byType(TextField), 'bank');
      await tester.pumpAndSettle();
      expect(find.text('Bank of Dartland'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
    });

    testWidgets('picking an entry hands its credentials to the platform',
        (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(bridge.completed, isNotNull);
      expect(bridge.completed!.username, 'octocat');
      expect(bridge.completed!.password, 'gh-secret');
      expect(bridge.completed!.label, 'GitHub');
    });

    testWidgets('the close button abandons the fill request', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(bridge.cancelled, isTrue);
      expect(bridge.completed, isNull);
    });
  });

  group('autofill launch flow (unlock → picker → fill)', () {
    const password = 'correct horse';

    testWidgets(
        'an autofill launch shows the unlock screen, then the picker, '
        'and filling returns the credentials', (tester) async {
      final storage = FakeSecureStorage();
      final fileStore = InMemoryFileStore();
      final clock = FixedClock(DateTime(2026, 7, 7, 9));
      final kdf = FakeKeyDerivation();
      const cipher = CipherService();

      // Seed a vault exactly as 1.x would have written it.
      final auth = MasterAuthService(
        storage: storage,
        keyDerivation: kdf,
        cipher: cipher,
        fileStore: fileStore,
        clock: clock,
      );
      final setup = await auth.setup(password);
      await VaultRepository(fileStore: fileStore, cipher: cipher)
          .save(entries, setup.key, setup.salt);

      final bridge = FakeAutofillBridge(
        request: const AutofillFillRequest(domain: 'github.com'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            fileStoreProvider.overrideWithValue(fileStore),
            keyDerivationProvider.overrideWithValue(kdf),
            clockProvider.overrideWithValue(clock),
            systemClipboardProvider.overrideWithValue(FakeClipboard()),
            autofillBridgeProvider.overrideWithValue(bridge),
            biometricAuthenticatorProvider.overrideWithValue(
              FakeBiometricAuthenticator(supported: false),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              routerConfig: ref.watch(appRouterProvider),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Locked first: the vault never opens without the master password.
      expect(
          find.text('Enter your master password to unlock.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, password);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Unlocking during an autofill launch lands on the picker, not the
      // vault, pre-filtered to the requesting site.
      expect(find.byType(AutofillPickerScreen), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Bank of Dartland'), findsNothing);

      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(bridge.completed, isNotNull);
      expect(bridge.completed!.username, 'octocat');
      expect(bridge.completed!.password, 'gh-secret');
    });
  });
}
