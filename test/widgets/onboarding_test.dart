import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/screens/onboarding_screen.dart';
import 'package:vaultkey/src/features/auth/screens/setup_screen.dart';
import 'package:vaultkey/src/features/auth/screens/unlock_screen.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:flutter/material.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late InMemoryFileStore fileStore;

  setUp(() {
    storage = FakeSecureStorage();
    fileStore = InMemoryFileStore();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          fileStoreProvider.overrideWithValue(fileStore),
          keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 7))),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
          autofillBridgeProvider
              .overrideWithValue(FakeAutofillBridge(supported: false)),
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
  }

  testWidgets(
      'first run shows the intro pages, completing them lands on '
      'master-password setup', (tester) async {
    await pumpApp(tester);

    // Intro page 1 of 3.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('All your passwords, one vault'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Yours alone'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Back up anywhere'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('Welcome to Vaultly'), findsOneWidget);
    expect(storage.store[VaultKeyKeys.onboardingDone], 'true');
  });

  testWidgets('Skip jumps straight to setup and still stores the flag',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(storage.store[VaultKeyKeys.onboardingDone], 'true');
  });

  testWidgets('a second run with the flag set (no vault yet) skips the intro',
      (tester) async {
    storage.store[VaultKeyKeys.onboardingDone] = 'true';
    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('a second run with an existing vault goes straight to unlock',
      (tester) async {
    storage.store[VaultKeyKeys.onboardingDone] = 'true';
    await MasterAuthService(
      storage: storage,
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
      fileStore: fileStore,
      clock: FixedClock(DateTime(2026, 7, 7)),
    ).setup('correct horse');

    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byType(UnlockScreen), findsOneWidget);
  });
}
