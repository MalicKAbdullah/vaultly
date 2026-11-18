import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/share/crypto/entry_share.dart';
import 'package:vaultkey/src/features/share/providers/share_providers.dart';
import 'package:vaultkey/src/features/share/screens/receive_entry_screen.dart';
import 'package:vaultkey/src/features/share/screens/share_entry_screen.dart';
import 'package:vaultkey/src/features/share/services/shared_entry.dart';
import 'package:vaultkey/src/features/share/widgets/share_widgets.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';
import '../widgets/helpers.dart';

void main() {
  final entry = makeEntry(
    id: 'gh',
    title: 'GitHub',
    username: 'octo',
    password: 'Qm7#vR2!kT9pL4xZ',
    totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
  );

  late ProviderContainer container;
  late String nextScan;
  final sentFiles = <(String, String)>[];

  Future<void> pump(WidgetTester tester, Widget home) async {
    sentFiles.clear();
    container = ProviderContainer(
      overrides: [
        vaultEntriesProvider.overrideWith(() => FakeVaultNotifier([entry])),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 18))),
        systemClipboardProvider.overrideWithValue(FakeClipboard()),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        shareFileSenderProvider.overrideWithValue(
          (content, name) async => sentFiles.add((content, name)),
        ),
        qrScannerProvider.overrideWithValue(
          (onCode) => TextButton(
            onPressed: () => onCode(nextScan),
            child: const Text('fake-scan'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultEntriesProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  testWidgets('a file share opens with the code shown, and only with it',
      (tester) async {
    await pump(tester, const ShareEntryScreen(entryId: 'gh'));
    await tester.tap(find.text('As a file'));
    await settle(tester, until: find.text('Copy code'));

    final code =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(RecoveryKey.normalize(code), isNotNull);
    await tester.tap(find.text('Send file'));
    await tester.pump();
    final (content, name) = sentFiles.single;
    expect(name, 'GitHub.vaultlyshare');
    expect(content, isNot(contains('Qm7#vR2!kT9pL4xZ')));

    final share = container.read(fileShareProvider);
    final opened = await tester.runAsync(() => share.open(content, code));
    final got = SharedEntry.decode(opened!, id: 'x', now: DateTime(2026));
    expect(got.password, 'Qm7#vR2!kT9pL4xZ');
    // The 2FA switch was left off.
    expect(got.totp, isNull);
  });

  testWidgets('QR: receiver invite → sender code → new entry in the vault',
      (tester) async {
    await pump(tester, const ReceiveEntryScreen());
    await settle(tester, until: find.byType(ShareQrPanel));
    final inviteUri =
        tester.widget<ShareQrPanel>(find.byType(ShareQrPanel)).data;
    expect(inviteUri, startsWith(QrShare.inviteScheme));

    // The sender, on top of the receiver (one test, one invite key pair).
    unawaited(tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
            builder: (_) => const ShareEntryScreen(entryId: 'gh'),
          ),
        ));
    await settle(tester, until: find.text('To a phone nearby'));
    await tester.tap(find.text('To a phone nearby'));
    await settle(tester, until: find.text('fake-scan'));

    // A stray QR code is ignored.
    nextScan = 'https://example.com';
    await tester.tap(find.text('fake-scan'));
    await settle(tester);
    expect(find.text('Share GitHub?'), findsNothing);

    nextScan = inviteUri;
    await tester.tap(find.text('fake-scan'));
    await settle(tester, until: find.text('Share GitHub?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await settle(
      tester,
      until: find.textContaining('Only the phone you scanned'),
    );
    // The receiver's panel stays in the tree under the sender's route.
    final sealed =
        tester.widget<ShareQrPanel>(find.byType(ShareQrPanel).last).data;
    expect(sealed, startsWith(QrShare.shareScheme));
    await tester.tap(find.text('Done'));
    for (var i = 0;
        i < 50 && find.byType(ShareEntryScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ShareEntryScreen), findsNothing);

    await tester.tap(find.text('Scan their code'));
    await settle(tester, until: find.text('fake-scan'));
    nextScan = sealed;
    await tester.tap(find.text('fake-scan'));
    await settle(tester, until: find.text('Add to vault'));
    expect(find.textContaining('octo'), findsOneWidget);
    await tester.tap(find.text('Add to vault'));
    await settle(tester);

    final vault = container.read(vaultEntriesProvider).requireValue;
    expect(vault, hasLength(2));
    final received = vault.last;
    expect(received.id, isNot('gh'));
    expect(received.title, 'GitHub');
    expect(received.password, 'Qm7#vR2!kT9pL4xZ');
    expect(received.history, isEmpty);
  });

  testWidgets('a shared file with the wrong code is refused', (tester) async {
    final share = FileShare(
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
    );
    final file = (await tester.runAsync(() => share.seal(
          SharedEntry.encode(entry, includeTotp: false),
          FileShare.newCode(),
        )))!;
    await pump(tester, ReceiveEntryScreen(fileContent: file));
    await tester.enterText(find.byType(TextField), FileShare.newCode());
    await tester.tap(find.text('Open'));
    await settle(tester,
        until: find.text('That code does not open this file.'));
    expect(container.read(vaultEntriesProvider).requireValue, hasLength(1));
  });
}

/// Pumps frames, letting real async crypto run between them, until
/// [until] finds something (or a frame budget runs out).
Future<void> settle(WidgetTester tester, {Finder? until}) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (until == null ? i > 3 : until.evaluate().isNotEmpty) return;
  }
  if (until != null) expect(until, findsWidgets);
}
