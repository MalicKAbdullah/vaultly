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
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Vaultly backup', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Restore a .vkbackup file using the passphrase it was '
              'created with.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickBackup,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(
                _file == null ? 'Choose backup file' : _file!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (preview != null) ...[
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading:
                      Icon(Icons.inventory_2_outlined, color: scheme.primary),
                  title: Text(
                    '${preview.entryCount} '
                    'entr${preview.entryCount == 1 ? 'y' : 'ies'}',
                    style: AppTextStyles.h4,
                  ),
                  subtitle: Text(
                    'Backed up '
                    '${DateFormat.yMMMd().add_jm().format(preview.createdAt.toLocal())}',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              VaultTextField(
                label: 'Backup passphrase',
                controller: _passphraseController,
                obscureText: true,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _import(),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<ImportMode>(
                segments: const [
                  ButtonSegment(
                    value: ImportMode.merge,
                    label: Text('Merge'),
                    icon: Icon(Icons.merge_type),
                  ),
                  ButtonSegment(
                    value: ImportMode.replace,
                    label: Text('Replace'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _mode == ImportMode.merge
                    ? 'Keeps everything; when an entry exists in both, the '
                        'newer version wins.'
                    : 'Deletes the current vault and restores only the '
                        'backup.',
                style: AppTextStyles.caption
                    .copyWith(color: scheme.onSurfaceVariant),
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
                style: AppTextStyles.bodySmall.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const Text('CSV from another app', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Works with exports from Chrome, Bitwarden, and most other '
              'password managers.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _importCsv,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Choose CSV file'),
            ),
          ],
        ),
      ),
    );
  }
}
