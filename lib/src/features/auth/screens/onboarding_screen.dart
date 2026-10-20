import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';

/// Three quick pages shown once, on the very first launch, before the
/// master password is created. Skippable; the router moves on to the
/// setup screen as soon as the "seen" flag is stored.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.key_rounded,
      headline: 'All your passwords, one vault',
      body: 'Save every login once and find it in seconds. '
          'One master password unlocks them all.',
    ),
    (
      icon: Icons.phonelink_lock_rounded,
      headline: 'Yours alone',
      body: 'Everything stays on this device, encrypted. '
          'No accounts, no servers, no tracking.',
    ),
    (
      icon: Icons.cloud_upload_rounded,
      headline: 'Back up anywhere',
      body: 'Keep a protected backup wherever you like — '
          'even straight to your Drive folder.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() =>
      ref.read(onboardingSeenProvider.notifier).markSeen();

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(duration: AppMotion.base, curve: AppMotion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  const SuiteAppIcon(app: SuiteApp.vaultly, size: 36),
                  const SizedBox(width: AppSpacing.smd),
                  Text(
                    'Vaultly',
                    style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    _OnboardingPage(
                      step: i + 1,
                      of: _pages.length,
                      icon: _pages[i].icon,
                      headline: _pages[i].headline,
                      body: _pages[i].body,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: AppMotion.base,
                        curve: AppMotion.standard,
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _page ? 24 : 8,
                        height: 8,
                        decoration: ShapeDecoration(
                          color: i == _page ? c.accent : c.border,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    const Spacer(),
                    VaultButton(
                      label: _isLast ? 'Get started' : 'Next',
                      icon: _isLast ? null : Icons.arrow_forward_rounded,
                      isFullWidth: false,
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.step,
    required this.of,
    required this.icon,
    required this.headline,
    required this.body,
  });

  final int step;
  final int of;
  final IconData icon;
  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xxl,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: c.accentContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                ),
                child: Icon(icon, size: 40, color: c.accent),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Step $step of $of',
                style: AppTextStyles.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                header: true,
                child: Text(
                  headline,
                  style: AppTextStyles.display.copyWith(
                    color: c.textPrimary,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.mdl),
              Text(
                body,
                style: AppTextStyles.body.copyWith(
                  color: c.textSecondary,
                  fontSize: 18,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
