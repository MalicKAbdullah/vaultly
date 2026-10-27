import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/providers/credential_providers.dart';
import 'package:vaultkey/src/features/passkeys/screens/credential_request_screen.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';

import '../fakes/fake_credential_bridge.dart';
import '../fakes/fakes.dart';
import '../fakes/passkey_fixtures.dart';
import 'helpers.dart';

void main() {
  late FakeCredentialBridge bridge;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Widget home,
    CredentialRequest? request,
    List<VaultEntry> entries = const [],
    bool settle = true,
  }) async {
    bridge = FakeCredentialBridge(request: request);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => FakeVaultNotifier(entries)),
          credentialBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          systemClipboardProvider.overrideWithValue(FakeClipboard()),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 10, 27))),
        ],
        child: MaterialApp(home: home),
      ),
    );
    // Answering a request leaves a progress indicator up until Android
    // closes the activity, so those screens never settle.
    settle ? await tester.pumpAndSettle() : await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byWidget(home)));
  }

  group('CredentialRequestScreen', () {
    testWidgets('saving a passkey stores it and answers the site',
        (tester) async {
      final c = await pump(
        tester,
        home: const CredentialRequestScreen(),
        request: registration,
      );
      expect(find.text('Save a passkey for WebAuthn.io?'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);

      await tester.tap(find.text('Save passkey'));
      await tester.pump();
      await tester.pump();

      expect(bridge.calls, ['register', 'finishRegistration']);
      final saved = c.read(vaultEntriesProvider).requireValue.single;
      expect(saved.passkey!.credentialId, 'bmV3LWNyZWQ');
    });

    testWidgets('an excluded passkey already in the vault is not duplicated',
        (tester) async {
      await pump(
        tester,
        home: const CredentialRequestScreen(),
        request: const PasskeyRegistrationRequest(
          rpId: 'webauthn.io',
          rpName: 'WebAuthn.io',
          userName: 'alice',
          userDisplayName: 'Alice',
          userHandle: 'bmV3',
          excludeCredentialIds: ['c3RvcmVk'],
          caller: 'webauthn.io',
        ),
        entries: [storedPasskey()],
      );
      expect(find.text('Already saved in Vaultly'), findsOneWidget);
      expect(find.text('Save passkey'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(bridge.calls, ['cancel']);
      expect(bridge.cancelledExcluded, isTrue);
    });

    testWidgets('a refused request explains why and reports back on close',
        (tester) async {
      await pump(
        tester,
        home: const CredentialRequestScreen(),
        request: const RejectedCredentialRequest(
          'evil.example cannot use a passkey for bank.example.',
        ),
      );
      expect(
        find.text('evil.example cannot use a passkey for bank.example.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(bridge.calls, ['cancel']);
      expect(bridge.cancelledExcluded, isFalse);
    });

    testWidgets('a passkey sign-in answers without further input',
        (tester) async {
      await pump(
        tester,
        home: const CredentialRequestScreen(),
        request: const PasskeySignInRequest(
          credentialId: 'c3RvcmVk',
          rpId: 'webauthn.io',
          caller: 'webauthn.io',
        ),
        entries: [storedPasskey()],
        settle: false,
      );
      await tester.pump();
      expect(bridge.calls, ['signIn']);
    });
  });

  group('passkey detail', () {
    testWidgets('shows the account but never the private key', (tester) async {
      await pump(
        tester,
        home: const EntryDetailScreen(entryId: 'pk-1'),
        entries: [storedPasskey()],
      );
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('webauthn.io'), findsWidgets);
      expect(find.textContaining('cHJpdg'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      await tester.scrollUntilVisible(find.text('Delete passkey'), 200);
      expect(find.text('Delete passkey'), findsOneWidget);
    });
  });
}
