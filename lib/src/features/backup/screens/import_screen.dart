import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/backup/services/file_transfer.dart';
import 'package:vaultkey/src/features/backup/services/vault_merge.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Restore a `.vkbackup` file (merge or replace) or import a CSV export
/// from another password manager.
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

  Future<void> _importCsv() async {
    final file = await FileTransfer.pickTextFile();
    if (file == null || !mounted) return;
    final List<CsvImportRow> rows;
    try {
      rows = CsvCodec.parseImport(file.content);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (rows.isEmpty) {
      setState(() => _error = 'No entries found in that CSV file.');
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${rows.length} '
            'entr${rows.length == 1 ? 'y' : 'ies'}?'),
        content: Text(
          'Found ${rows.length} entr${rows.length == 1 ? 'y' : 'ies'} in '
          '"${file.name}". They will be added to your vault as new '
          'entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (!(proceed ?? false) || !mounted) return;

    final notifier = ref.read(vaultEntriesProvider.notifier);
    for (final row in rows) {
      await notifier.create(
        title: row.name,
        username: row.username,
        password: row.password,
        url: row.url,
        notes: row.note,
        category: EntryCategory.login,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${rows.length} entries imported.')),
    );
    context.pop();
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
            const SizedBox(height: AppSpacing.smd),
            VaultCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CardTitle(
                    icon: Icons.table_chart_outlined,
                    color: c.info,
                    title: 'CSV from another app',
                    body: 'Works with exports from Chrome, Bitwarden, and '
                        'most other password managers.',
                  ),
                  const SizedBox(height: AppSpacing.mdl),
                  VaultButton(
                    label: 'Choose CSV file',
                    icon: Icons.upload_file_rounded,
                    variant: VaultButtonVariant.secondary,
                    onPressed: _importCsv,
                  ),
                ],
              ),
            ),
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
              Text(title, style: AppTextStyles.h3.copyWith(color: c.textPrimary)),
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
