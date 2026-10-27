import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/otpauth_migration.dart';
import 'package:vaultkey/src/features/importers/screens/import_preview_screen.dart';
import 'package:vaultkey/src/features/importers/services/import_files.dart';

/// Scans Google Authenticator's "Transfer accounts" QR codes, by camera or
/// from a screenshot, collecting every code of a multi-part export before
/// the preview.
class MigrationScanScreen extends StatefulWidget {
  const MigrationScanScreen({super.key});

  @override
  State<MigrationScanScreen> createState() => _MigrationScanScreenState();
}

class _MigrationScanScreenState extends State<MigrationScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// Scanned codes by (batch id, index), so a code seen twice counts once.
  final _batches = <(int, int), MigrationBatch>{};
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _expected {
    final sizes = <int, int>{
      for (final b in _batches.values) b.batchId: b.batchSize,
    };
    return sizes.values.fold(0, (sum, n) => sum + n);
  }

  bool get _complete => _batches.isNotEmpty && _batches.length >= _expected;

  void _accept(Iterable<Barcode> codes) {
    var added = false;
    for (final code in codes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      if (!OtpauthMigration.looksLikeMigration(raw)) {
        setState(() => _error = 'That is not a Google Authenticator export '
            'code. In Authenticator, choose Transfer accounts → Export.');
        continue;
      }
      try {
        final batch = OtpauthMigration.parse(raw);
        final key = (batch.batchId, batch.batchIndex);
        if (_batches.containsKey(key)) continue;
        added = true;
        setState(() {
          _batches[key] = batch;
          _error = null;
        });
      } on ImportFormatException catch (e) {
        setState(() => _error = e.message);
      }
    }
    if (added && _complete) _review();
  }

  Future<void> _pickImage() async {
    final capture = await ImportFiles.withPickedImage(
      (path) => _controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      ),
    );
    if (!mounted) return;
    if (capture == null || capture.barcodes.isEmpty) {
      setState(() => _error = 'No QR code found in that image.');
      return;
    }
    _accept(capture.barcodes);
  }

  void _review() {
    final ordered = _batches.entries.toList()
      ..sort((a, b) => a.key.$1 != b.key.$1
          ? a.key.$1.compareTo(b.key.$1)
          : a.key.$2.compareTo(b.key.$2));
    final batch = ImportBatch(
      source: ImportSource.googleAuthenticator,
      authenticators: [
        for (final e in ordered) ...e.value.authenticators,
      ],
      warnings: [for (final e in ordered) ...e.value.warnings],
    );
    _controller.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ImportPreviewScreen(batch: batch),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final scanned = _batches.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Authenticator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'In Google Authenticator, open the menu → Transfer accounts → '
            'Export accounts, then scan the code shown. Large exports show '
            'several codes; scan each one.',
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) => _accept(capture.barcodes),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (scanned > 0)
            AppBanner(
              kind: BannerKind.info,
              icon: Icons.qr_code_2_rounded,
              title: 'Scanned $scanned of $_expected',
              message: _complete ? null : 'Scan the next code.',
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: AppTextStyles.bodySmall.copyWith(color: c.negative),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          VaultButton(
            label: 'Choose a screenshot',
            icon: Icons.image_outlined,
            variant: VaultButtonVariant.secondary,
            onPressed: _pickImage,
          ),
          if (scanned > 0 && !_complete) ...[
            const SizedBox(height: AppSpacing.sm),
            VaultButton(
              label: 'Review what I scanned',
              variant: VaultButtonVariant.secondary,
              onPressed: _review,
            ),
          ],
        ],
      ),
    );
  }
}
