import 'package:core_crypto/core_crypto.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Scans the recovery key QR code from a printed emergency kit. Pops with
/// the key as read, or null when the user goes back.
class RecoveryKeyScanner extends StatefulWidget {
  const RecoveryKeyScanner({super.key});

  static Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const RecoveryKeyScanner()),
      );

  @override
  State<RecoveryKeyScanner> createState() => _RecoveryKeyScannerState();
}

class _RecoveryKeyScannerState extends State<RecoveryKeyScanner> {
  bool _done = false;

  void _onScan(Code code) {
    final text = code.text;
    // Other QR codes in view are ignored; only a recovery key ends the scan.
    if (_done || !code.isValid || text == null) return;
    if (RecoveryKey.normalize(text) == null) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan recovery key')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          Text(
            'Point the camera at the code on your emergency kit.',
            style: AppTextStyles.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AspectRatio(
              aspectRatio: 1,
              child: ReaderWidget(
                codeFormat: Format.qrCode,
                showGallery: false,
                showToggleCamera: false,
                onScan: _onScan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
