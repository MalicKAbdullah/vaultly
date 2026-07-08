import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/screens/unlock_screen.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';

import '../fakes/fakes.dart';

void main() {
  const password = 'correct horse';
  late FakeSecureStorage storage;
  late InMemoryFileStore fileStore;
  late FixedClock clock;
  late MasterAuthService auth;

  setUp(() async {
    storage = FakeSecureStorage();
    fileStore = InMemoryFileStore();
    clock = FixedClock(DateTime(2026, 7, 5, 12));
    auth = MasterAuthService(
      storage: storage,
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
      fileStore: fileStore,
      clock: clock,
    );
    await auth.setup(password);
  });

  Future<void> pumpUnlock(
    WidgetTester tester, {
    FakeBiometricAuthenticator? biometrics,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          fileStoreProvider.overrideWithValue(fileStore),
          keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
          clockProvider.overrideWithValue(clock),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
          biometricAuthenticatorProvider.overrideWithValue(
            biometrics ?? FakeBiometricAuthenticator(supported: false),
          ),
        ],
        child: const MaterialApp(home: UnlockScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(UnlockScreen)));

  testWidgets('wrong password shows a friendly error and stays locked',
      (tester) async {
    await pumpUnlock(tester);

    await tester.enterText(find.byType(TextField).first, 'not the password');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('That password is not right.'), findsOneWidget);
    expect(containerOf(tester).read(sessionProvider), AuthStatus.locked);
  });

  testWidgets('correct password unlocks the session', (tester) async {
    await pumpUnlock(tester);

    await tester.enterText(find.byType(TextField).first, password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(sessionProvider), AuthStatus.unlocked);
  });

  testWidgets('biometric button is hidden when biometrics are not enabled',
      (tester) async {
    await pumpUnlock(tester);
    expect(find.text('Unlock with biometrics'), findsNothing);
  });

  testWidgets('biometric button unlocks when enabled and prompt succeeds',
      (tester) async {
    // Enable biometrics: wrap the real derived key in storage.
    final setup = await auth.unlock(password) as UnlockSuccess;
    final biometrics = FakeBiometricAuthenticator();
    await BiometricUnlockService(
      storage: storage,
      authenticator: biometrics,
    ).enable(setup.key);

    await pumpUnlock(tester, biometrics: biometrics);
    expect(find.text('Unlock with biometrics'), findsOneWidget);

    await tester.tap(find.text('Unlock with biometrics'));
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(sessionProvider), AuthStatus.unlocked);
  });

  testWidgets('a persisted cooldown disables the unlock button',
      (tester) async {
    for (var i = 0; i < 5; i++) {
      await auth.unlock('wrong attempt $i');
    }
    // Pump without settling: pumpAndSettle would fast-forward through the
    // whole countdown.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          fileStoreProvider.overrideWithValue(fileStore),
          keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
          clockProvider.overrideWithValue(clock),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
          biometricAuthenticatorProvider.overrideWithValue(
            FakeBiometricAuthenticator(supported: false),
          ),
        ],
        child: const MaterialApp(home: UnlockScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The cooldown notice is visible and Unlock is disabled.
    expect(find.textContaining('Too many attempts'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, password);
    await tester.tap(find.text('Unlock'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      containerOf(tester).read(sessionProvider),
      isNot(AuthStatus.unlocked),
    );

    // Drain the countdown timer cleanly.
    await tester.pumpAndSettle(const Duration(seconds: 31));
  });
}
