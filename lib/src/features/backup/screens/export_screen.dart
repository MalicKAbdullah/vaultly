import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_service.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/backup/services/file_transfer.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Export the vault: encrypted `.vkbackup` (share or save) or plain CSV
/// behind a strong warning.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassphrase() {
    if (_passphraseController.text.length < BackupCodec.minPassphraseLength) {
      return 'Use at least ${BackupCodec.minPassphraseLength} characters.';
    }
    if (_passphraseController.text != _confirmController.text) {
      return 'The passphrases do not match.';
    }
    return null;
  }

  Future<String?> _buildBackup() async {
    final error = _validatePassphrase();
    if (error != null) {
      setState(() => _error = error);
      return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final entries = ref.read(vaultEntriesProvider).valueOrNull ?? const [];
    final content = await ref.read(backupCodecProvider).encode(
          entries: entries,
          passphrase: _passphraseController.text,
          createdAt: ref.read(clockProvider).now(),
        );
    if (mounted) setState(() => _busy = false);
    return content;
  }

  Future<void> _shareBackup() async {
    final content = await _buildBackup();
    if (content == null) return;
    await FileTransfer.shareAsFile(
      content: content,
      fileName: AutoBackupService.fileNameFor(ref.read(clockProvider).now()),
    );
  }

  Future<void> _saveBackup() async {
    final content = await _buildBackup();
    if (content == null) return;
    final saved = await FileTransfer.saveAs(
      content: content,
      fileName: AutoBackupService.fileNameFor(ref.read(clockProvider).now()),
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup saved.')),
      );
    }
  }

  Future<void> _exportCsv() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export without encryption?'),
        content: const Text(
          'A CSV file contains every password in plain, readable text. '
          'Anyone who gets the file can read them all. Only continue if '
          'you know exactly where this file will live — and delete it '
          'when you are done.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I understand, export'),
          ),
        ],
      ),
    );
    if (!(proceed ?? false) || !mounted) return;

    final entries = ref.read(vaultEntriesProvider).valueOrNull ?? const [];
    final saved = await FileTransfer.saveAs(
      content: CsvCodec.export(entries),
      fileName: 'vaultly-export.csv',
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV exported. Remember to delete it when done.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entryCount =
        (ref.watch(vaultEntriesProvider).valueOrNull ?? const []).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Encrypted backup', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Protects all $entryCount entries with a passphrase of its '
              'own. This is the safe way to move or back up your vault.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            VaultTextField(
              label: 'Backup passphrase',
              controller: _passphraseController,
              obscureText: true,
              hint: 'At least 8 characters',
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            StrengthMeter(password: _passphraseController.text),
            const SizedBox(height: AppSpacing.md),
            VaultTextField(
              label: 'Confirm passphrase',
              controller: _confirmController,
              obscureText: true,
              errorText: _error,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _shareBackup,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _saveBackup,
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Save to folder'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const Text('Plain CSV', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'For moving to another password manager. The file is not '
              'protected — treat it like a written-down list of all your '
              'passwords.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _exportCsv,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }
}
