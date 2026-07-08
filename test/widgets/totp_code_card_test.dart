import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/totp_generator.dart';
import 'package:vaultkey/src/features/totp/widgets/totp_code_card.dart';

import '../fakes/fakes.dart';

void main() {
  const config = TotpConfig(secret: 'JBSWY3DPEHPK3PXP');
  // Start exactly on a period boundary so pumping 30 s lands on the next.
  final start = DateTime.fromMillisecondsSinceEpoch(1750000020 * 1000);

  late FixedClock clock;
  late FakeClipboard clipboard;

  Future<void> pumpCard(
    WidgetTester tester, {
    TotpConfig cardConfig = config,
  }) async {
    clock = FixedClock(start);
    clipboard = FakeClipboard();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(clock),
          systemClipboardProvider.overrideWithValue(clipboard),
        ],
        child: MaterialApp(
          home: Scaffold(body: TotpCodeCard(config: cardConfig)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the current code grouped as "123 456"', (tester) async {
    await pumpCard(tester);
    final expected = TotpGenerator.group(TotpGenerator.codeAt(config, start));
    expect(expected, matches(RegExp(r'^\d{3} \d{3}$')));
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('rolls to the next code when the period ends', (tester) async {
    await pumpCard(tester);
    final first = TotpGenerator.group(TotpGenerator.codeAt(config, start));

    // Advance the wall clock and let the countdown animation complete.
    clock.advance(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 300));

    final second = TotpGenerator.group(
      TotpGenerator.codeAt(config, start.add(const Duration(seconds: 30))),
    );
    expect(second, isNot(first));
    expect(find.text(second), findsOneWidget);
  });

  testWidgets('tap copies the ungrouped code via the clipboard guard',
      (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byType(TotpCodeCard));
    await tester.pump();

    expect(clipboard.text, TotpGenerator.codeAt(config, start));
    expect(find.textContaining('Code copied'), findsOneWidget);

    // Drain the 30 s auto-clear timer; the sensitive code must be wiped.
    await tester.pump(const Duration(seconds: 31));
    expect(clipboard.text, '');
  });

  testWidgets('an unreadable secret shows a friendly error instead of a code',
      (tester) async {
    await pumpCard(
      tester,
      cardConfig: const TotpConfig(secret: 'not base32 at all!'),
    );
    expect(find.textContaining('not readable'), findsOneWidget);
  });
}
