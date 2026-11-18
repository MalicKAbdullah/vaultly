import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vaultkey/src/features/share/providers/share_providers.dart';

/// A QR code on a white quiet zone, so it scans in dark mode too.
class ShareQrPanel extends StatelessWidget {
  const ShareQrPanel({required this.data, required this.caption, super.key});

  final String data;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return VaultCard(
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: QrImageView(
              data: data,
              size: 260,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The camera, square and rounded, reporting each QR code it reads.
class ShareScanner extends ConsumerWidget {
  const ShareScanner({required this.onCode, super.key});

  final ValueChanged<String> onCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: AspectRatio(
          aspectRatio: 1,
          child: ref.watch(qrScannerProvider)(onCode),
        ),
      );
}

/// One line of explanation above a step.
class ShareHint extends StatelessWidget {
  const ShareHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Text(
          text,
          style: AppTextStyles.body.copyWith(
            color: SuiteColors.of(context).textSecondary,
          ),
        ),
      );
}
