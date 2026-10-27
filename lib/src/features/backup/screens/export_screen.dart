import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
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
      fileName: ref
          .read(autoBackupServiceProvider)
          .fileNameFor(ref.read(clockProvider).now()),
    );
  }

  Future<void> _saveBackup() async {
    final content = await _buildBackup();
    if (content == null) return;
    final saved = await FileTransfer.saveAs(
      content: content,
      fileName: ref
          .read(autoBackupServiceProvider)
          .fileNameFor(ref.read(clockProvider).now()),
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
    final c = SuiteColors.of(context);
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
    final entryCount = entries.length;
    final passkeyCount = entries.where((e) => e.passkey != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
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
                    icon: Icons.lock_rounded,
                    color: c.accent,
                    title: 'Encrypted backup',
                    body: 'Protects all $entryCount entries, passkeys '
                        'included, with a passphrase of its own. This is the '
                        'safe way to move or back up your vault.',
                  ),
                  const SizedBox(height: AppSpacing.mdl),
                  AppTextField(
                    label: 'Backup passphrase',
                    controller: _passphraseController,
                    obscureText: true,
                    hint: 'At least 8 characters',
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.smd),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: StrengthMeter(password: _passphraseController.text),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Confirm passphrase',
                    controller: _confirmController,
                    obscureText: true,
                    errorText: _error,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.mdl),
                  Row(
                    children: [
                      Expanded(
                        child: VaultButton(
                          label: 'Share',
                          icon: Icons.ios_share_rounded,
                          variant: VaultButtonVariant.secondary,
                          onPressed: _busy ? null : _shareBackup,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smd),
                      Expanded(
                        child: VaultButton(
                          label: 'Save to folder',
                          icon: Icons.folder_outlined,
                          onPressed: _busy ? null : _saveBackup,
                        ),
                      ),
                    ],
                  ),
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
                    color: c.warning,
                    title: 'Plain CSV',
                    body: 'For moving to another password manager. The file '
                        'is not protected — treat it like a written-down '
                        'list of all your passwords.',
                  ),
                  if (passkeyCount > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppBanner(
                      title: passkeyCount == 1
                          ? 'Your passkey is not included'
                          : 'Your $passkeyCount passkeys are not included',
                      message: 'A passkey is a private key, and Vaultly never '
                          'writes one to an unencrypted file. Use an encrypted '
                          'backup to move passkeys.',
                      icon: Icons.key_rounded,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.mdl),
                  VaultButton(
                    label: 'Export CSV',
                    icon: Icons.download_rounded,
                    variant: VaultButtonVariant.secondary,
                    onPressed: _exportCsv,
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

/// Icon badge, title and explanation at the top of a backup card.
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
