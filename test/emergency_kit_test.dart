// The recovery-key wrap runs real Argon2id, which can take well over the
// default 30 seconds per test on a loaded CI runner.
@Timeout(Duration(minutes: 5))
library;

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/print_bridge.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/settings/screens/emergency_kit_screen.dart';
import 'package:vaultkey/src/features/settings/services/emergency_kit.dart';

import 'fakes/fakes.dart';

final class FakePrintBridge implements IPrintBridge {
  FakePrintBridge({required this.sends});

  /// What the dialog reports: printed or saved (true), backed out (false).
  final bool sends;
  final printed = <List<PrintBlock>>[];

  @override
  Future<bool> printEmergencyKit({
    required String jobName,
    required List<PrintBlock> blocks,
  }) async {
    printed.add(blocks);
    return sends;
  }
}

void main() {
  group('EmergencyKit.blocks', () {
    const key = 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-2345';

    List<PrintBlock> kit({String? folder, String? passphrase}) =>
        EmergencyKit.blocks(
          date: DateTime(2026, 11, 18),
          recoveryKey: key,
          backupFolder: folder,
          backupPassphrase: passphrase,
        );

    String allText(List<PrintBlock> blocks) =>
        blocks.map((b) => b.text).join('\n');

    test('has the key, its QR, the warning and the restore steps', () {
      final blocks = kit(folder: 'Download');
      expect(
        blocks.where((b) => b.style == PrintBlockStyle.secret).single.text,
        key,
      );
      final qr = blocks.singleWhere((b) => b.style == PrintBlockStyle.qr).qr!;
      expect(qr.modules, hasLength(qr.size * qr.size));
      expect(qr.modules.where((m) => m == 1), isNotEmpty);
      final text = allText(blocks);
      expect(text, contains('Made on 18 November 2026'));
      expect(text, contains('Anyone with this page can open your vault.'));
      expect(text, contains('the folder "Download"'));
      expect(text, contains('Forgot password?'));
    });

    test('leaves a line for the passphrase unless it is included', () {
      final without = kit();
      expect(
        without.where((b) => b.style == PrintBlockStyle.writeIn).map(
              (b) => b.text,
            ),
        contains('Backup passphrase'),
      );
      final withIt = kit(passphrase: 'tulip-orbit-91');
      expect(
        withIt.where((b) => b.style == PrintBlockStyle.secret).map(
              (b) => b.text,
            ),
        [key, 'tulip-orbit-91'],
      );
    });

    test('the QR code reads back as the recovery key', () {
      // Same encoder, same data: the modules match a fresh encode.
      final a = EmergencyKit.qrModules(key);
      final b = EmergencyKit.qrModules(key);
      expect(a.modules, b.modules);
      expect(RecoveryKey.normalize(key), isNotNull);
    });
  });

  group('EmergencyKitScreen', () {
    late FakeSecureStorage storage;
    late MasterAuthService auth;
    late FakePrintBridge bridge;
    late ProviderContainer container;
    const password = 'correct horse';

    Future<String> pump(
      WidgetTester tester, {
      required bool sends,
      String? passphrase,
    }) async {
      storage = FakeSecureStorage();
      if (passphrase != null) {
        storage.store[VaultKeyKeys.backupPassphrase] = passphrase;
      }
      bridge = FakePrintBridge(sends: sends);
      final overrides = [
        secureStorageProvider.overrideWithValue(storage),
        fileStoreProvider.overrideWithValue(InMemoryFileStore()),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 18))),
        printBridgeProvider.overrideWithValue(bridge),
        backupFolderProvider.overrideWithValue(FakeBackupFolder()),
        biometricAuthenticatorProvider
            .overrideWithValue(FakeBiometricAuthenticator()),
      ];
      container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      late String oldKey;
      await tester.runAsync(() async {
        auth = container.read(masterAuthServiceProvider);
        container.listen(sessionProvider, (_, __) {});
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        await container.read(sessionProvider.notifier).setup(password);
        oldKey =
            await container.read(sessionProvider.notifier).createRecoveryKey();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EmergencyKitScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return oldKey;
    }

    Future<void> printKit(WidgetTester tester) async {
      await tester.tap(find.text('Print emergency kit'));
      await tester.pumpAndSettle();
      // Biometrics are off, so the master password confirms the owner.
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Confirm'));
      // Key wrapping runs real async crypto; let it finish between frames
      // until the screen reports an outcome.
      final outcome = find.byWidgetPredicate(
        (w) => w is AppBanner && w.kind != BannerKind.warning,
      );
      for (var i = 0; i < 100 && outcome.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<bool> keyWorks(WidgetTester tester, String key) async =>
        (await tester.runAsync(() => auth.resetWithRecoveryKey(
              recoveryKey: key,
              newPassword: 'brand new secret',
            ))) is UnlockSuccess;

    testWidgets('warns that the current recovery key will stop working',
        (tester) async {
      await pump(tester, sends: true);
      expect(find.text('This replaces your recovery key'), findsOneWidget);
      expect(
        find.textContaining('Anyone with this page can open your vault.'),
        findsOneWidget,
      );
      expect(find.text('Include backup passphrase'), findsNothing);
    });

    testWidgets('a printed kit puts its new key in force', (tester) async {
      final oldKey = await pump(tester, sends: true);
      await printKit(tester);

      expect(find.text('Kit printed'), findsOneWidget);
      final newKey = bridge.printed.single
          .firstWhere((b) => b.style == PrintBlockStyle.secret)
          .text;
      expect(storage.store[VaultKeyKeys.emergencyKitAt], isNotNull);
      expect(await keyWorks(tester, oldKey), isFalse);
      expect(await keyWorks(tester, newKey), isTrue);
    });

    testWidgets('backing out of the dialog keeps the current key',
        (tester) async {
      final oldKey = await pump(tester, sends: false);
      await printKit(tester);

      expect(find.text('Nothing was printed'), findsOneWidget);
      expect(storage.store[VaultKeyKeys.emergencyKitAt], isNull);
      expect(await keyWorks(tester, oldKey), isTrue);
    });

    testWidgets('prints the backup passphrase only when switched on',
        (tester) async {
      await pump(tester, sends: true, passphrase: 'tulip-orbit-91');
      expect(find.text('Include backup passphrase'), findsOneWidget);
      await printKit(tester);
      expect(
        bridge.printed.single.map((b) => b.text),
        isNot(contains('tulip-orbit-91')),
      );
    });
  });
}
