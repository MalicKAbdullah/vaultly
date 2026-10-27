import 'dart:convert';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/backup/services/file_transfer.dart';
import 'package:vaultkey/src/features/backup/services/vault_merge.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/parsers/import_detector.dart';
import 'package:vaultkey/src/features/importers/screens/csv_mapping_screen.dart';
import 'package:vaultkey/src/features/importers/screens/import_preview_screen.dart';
import 'package:vaultkey/src/features/importers/screens/migration_scan_screen.dart';
import 'package:vaultkey/src/features/importers/services/import_files.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Restore a `.vkbackup` file (merge or replace) or import from another
/// password manager or authenticator.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _passphraseController = TextEditingController();
  PickedFile? _file;
  BackupPreview? _preview;
  ImportMode _mode = ImportMode.merge;
  bool _busy = false;
  String? _error;
  String? _appImportError;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _pickBackup() async {
    final file = await FileTransfer.pickTextFile();
    if (file == null) return;
    try {
      final preview = ref.read(backupCodecProvider).peek(file.content);
      setState(() {
        _file = file;
        _preview = preview;
        _error = null;
      });
    } on BackupFormatException catch (e) {
      setState(() {
        _file = null;
        _preview = null;
        _error = e.message;
      });
    }
  }

  Future<void> _import() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final incoming = await ref.read(backupCodecProvider).decode(
            content: file.content,
            passphrase: _passphraseController.text,
          );
      final notifier = ref.read(vaultEntriesProvider.notifier);
      final current = ref.read(vaultEntriesProvider).valueOrNull ?? const [];
      await notifier.replaceAll(
        VaultMerge.apply(mode: _mode, current: current, incoming: incoming),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == ImportMode.merge
                ? 'Backup merged into your vault.'
                : 'Vault replaced from backup.',
          ),
        ),
      );
      context.pop();
    } on BackupPassphraseException {
      setState(() => _error = 'That passphrase is not right.');
    } on BackupFormatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reads an export file and opens the column matcher or the preview.
  /// The file's bytes are wiped as soon as they are parsed.
  Future<void> _importFromApp({bool forceMapping = false}) async {
    final picked = await ImportFiles.pickExport();
    if (picked == null || !mounted) return;
    final ImportReadResult result;
    try {
      if (forceMapping) {
        final table = CsvTable.parse(utf8.decode(picked.bytes));
        result = ImportNeedsMapping(
          table,
          CsvImporters.guessMapping(table.header),
        );
      } else {
        result =
            ImportDetector.read(fileName: picked.name, bytes: picked.bytes);
      }
    } on ImportFormatException catch (e) {
      setState(() => _appImportError = e.message);
      return;
    } on FormatException {
      setState(() => _appImportError = 'That file is not a CSV export.');
      return;
    } finally {
      picked.wipe();
    }
    setState(() => _appImportError = null);
    final Widget next = switch (result) {
      ImportReady(:final batch) => ImportPreviewScreen(batch: batch),
      ImportNeedsMapping(:final table, :final suggested) =>
        CsvMappingScreen(table: table, suggested: suggested),
    };
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VaultCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CardTitle(
                    icon: Icons.restore_rounded,
                    color: c.accent,
                    title: 'Vaultly backup',
                    body: 'Restore a .vkbackup file using the passphrase it '
                        'was created with.',
                  ),
                  const SizedBox(height: AppSpacing.mdl),
                  VaultButton(
                    label: _file == null ? 'Choose backup file' : _file!.name,
                    icon: Icons.file_open_outlined,
                    variant: VaultButtonVariant.secondary,
                    onPressed: _pickBackup,
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppBanner(
                      kind: BannerKind.info,
                      icon: Icons.inventory_2_outlined,
                      title: '${preview.entryCount} '
                          'entr${preview.entryCount == 1 ? 'y' : 'ies'}',
                      message: 'Backed up '
                          '${DateFormat.yMMMd().add_jm().format(preview.createdAt.toLocal())}',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Backup passphrase',
                      controller: _passphraseController,
                      obscureText: true,
                      errorText: _error,
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _import(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppSegmentedControl<ImportMode>(
                      height: 44,
                      segments: const [
                        AppSegment(
                          value: ImportMode.merge,
                          label: 'Merge',
                          icon: Icons.merge_type_rounded,
                        ),
                        AppSegment(
                          value: ImportMode.replace,
                          label: 'Replace',
                          icon: Icons.swap_horiz_rounded,
                        ),
                      ],
                      selected: _mode,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _mode == ImportMode.merge
                          ? 'Keeps everything; when an entry exists in both, '
                              'the newer version wins.'
                          : 'Deletes the current vault and restores only the '
                              'backup.',
                      style: AppTextStyles.caption.copyWith(
                        color: _mode == ImportMode.replace
                            ? c.negative
                            : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    VaultButton(
                      label: 'Import backup',
                      isLoading: _busy,
                      onPressed: _busy ? null : _import,
                    ),
                  ] else if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.negative,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'From another app',
              subtitle: 'Read from the file you choose; nothing is uploaded',
            ),
            RowGroup(
              separatorIndent: 66,
              children: [
                SettingsTile(
                  icon: Icons.public_rounded,
                  title: 'Chrome / Google Password Manager',
                  subtitle: 'CSV export',
                  onTap: _importFromApp,
                ),
                SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Bitwarden',
                  subtitle: 'Unencrypted JSON or CSV export',
                  onTap: _importFromApp,
                ),
                SettingsTile(
                  icon: Icons.key_rounded,
                  title: '1Password',
                  subtitle: '.1pux or CSV export',
                  onTap: _importFromApp,
                ),
                SettingsTile(
                  icon: Icons.table_chart_outlined,
                  title: 'Other CSV',
                  subtitle: 'Match the columns yourself',
                  onTap: () => _importFromApp(forceMapping: true),
                ),
                SettingsTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Google Authenticator',
                  subtitle: 'Scan the Transfer accounts QR code',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MigrationScanScreen(),
                    ),
                  ),
                ),
              ],
            ),
            if (_appImportError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _appImportError!,
                style: AppTextStyles.bodySmall.copyWith(color: c.negative),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icon badge, title and explanation at the top of an import card.
class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(icon: icon, color: color, size: 44),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppTextStyles.h3.copyWith(color: c.textPrimary)),
              const SizedBox(height: 4),
              Text(
                body,
                style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
