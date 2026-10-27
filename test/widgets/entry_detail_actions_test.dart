import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';

void main() {
  for (final width in [360.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('action buttons show full labels at ${width}dp x$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.light, accent: AppAccents.vaultly),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: DetailActionButtons(
                  children: [
                    VaultButton(
                      label: 'Copy password',
                      icon: Icons.copy_rounded,
                      onPressed: () {},
                    ),
                    VaultButton(
                      label: 'Open site',
                      icon: Icons.open_in_new_rounded,
                      variant: VaultButtonVariant.secondary,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Stacked full-width buttons leave each label the whole row, so
        // neither can truncate; side by side they would share it.
        final copy = tester.getRect(find.byType(VaultButton).first);
        final open = tester.getRect(find.byType(VaultButton).last);
        expect(open.top, greaterThanOrEqualTo(copy.bottom));
        expect(open.width, copy.width);
        expect(copy.width, width - 2 * AppSpacing.gutter);
        expect(find.text('Copy password'), findsOneWidget);
        expect(find.text('Open site'), findsOneWidget);
      });
    }
  }

  testWidgets('action buttons share a row when there is room', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailActionButtons(
            children: [
              VaultButton(label: 'Copy password', onPressed: () {}),
              VaultButton(label: 'Open site', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    final copy = tester.getRect(find.byType(VaultButton).first);
    final open = tester.getRect(find.byType(VaultButton).last);
    expect(open.top, copy.top);
  });
}
