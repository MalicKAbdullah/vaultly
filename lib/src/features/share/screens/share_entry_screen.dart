import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/share/crypto/entry_share.dart';
import 'package:vaultkey/src/features/share/providers/share_providers.dart';
import 'package:vaultkey/src/features/share/services/shared_entry.dart';
import 'package:vaultkey/src/features/share/widgets/share_widgets.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

enum _Step { choose, scan, sealing, showQr, fileCode }

/// Sends one entry to another phone, offline: as a QR code to a phone
/// nearby, or as an encrypted file with a one-time code sent separately.
class ShareEntryScreen extends ConsumerStatefulWidget {
  const ShareEntryScreen({required this.entryId, super.key});

  final String entryId;

  @override
  ConsumerState<ShareEntryScreen> createState() => _ShareEntryScreenState();
}

class _ShareEntryScreenState extends ConsumerState<ShareEntryScreen> {
  _Step _step = _Step.choose;
  bool _includeTotp = false;
  bool _scanned = false;
  String? _sealedQr;
  String? _file;
  String? _code;
  String? _error;

  VaultEntry get _entry => ref.read(entryByIdProvider(widget.entryId))!;

  List<int> _plaintext() =>
      SharedEntry.encode(_entry, includeTotp: _includeTotp);

  Future<void> _onScan(String raw) async {
    if (_scanned || !raw.startsWith(QrShare.inviteScheme)) return;
    _scanned = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Share ${_entry.title}?'),
        content: const Text(
          'It goes to the phone you just scanned. Only that phone can open '
          'the code you show next.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      setState(() {
        _scanned = false;
        _step = _Step.choose;
      });
      return;
    }
    setState(() => _step = _Step.sealing);
    try {
      final sealed = await QrShare.sealForInvite(raw, _plaintext());
      if (!mounted) return;
      setState(() {
        _sealedQr = sealed;
        _step = _Step.showQr;
      });
    } on ShareException catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  Future<void> _asFile() async {
    setState(() {
      _step = _Step.sealing;
      _error = null;
    });
    final code = FileShare.newCode();
    final file = await ref.read(fileShareProvider).seal(_plaintext(), code);
    if (mounted) {
      setState(() {
        _code = code;
        _file = file;
        _step = _Step.fileCode;
      });
    }
  }

  Future<void> _sendFile() => ref.read(shareFileSenderProvider)(
        _file!,
        '${_safeName(_entry.title)}.${FileShare.extension}',
      );

  /// A file name from the title: letters, digits, spaces and dashes only.
  static String _safeName(String title) {
    final name = title.replaceAll(RegExp(r'[^\w \-]'), '').trim();
    return name.isEmpty ? 'Vaultly entry' : name;
  }

  Future<void> _copyCode() async {
    final guard = ref.read(clipboardGuardProvider);
    await guard.copySensitive(_code!);
    if (mounted) {
      showCopiedSnack(context, what: 'Code', clearsAfter: guard.clearAfter);
    }
  }

  void _fail(String message) => setState(() {
        _error = message;
        _scanned = false;
        _step = _Step.choose;
      });

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(entryByIdProvider(widget.entryId));
    if (entry == null) return const Scaffold(body: SizedBox.shrink());
    final c = SuiteColors.of(context);
    final done = _step == _Step.showQr || _step == _Step.fileCode;

    return Scaffold(
      appBar: AppBar(title: Text('Share ${entry.title}')),
      bottomNavigationBar: done
          ? BottomActionBar(
              primary: _step == _Step.fileCode
                  ? VaultButton(
                      label: 'Send file',
                      icon: Icons.ios_share_rounded,
                      onPressed: _sendFile,
                    )
                  : VaultButton(
                      label: 'Done',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          if (_error != null) ...[
            AppBanner(
              kind: BannerKind.error,
              title: 'Not shared',
              message: _error,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...switch (_step) {
            _Step.choose => [
                const ShareHint(
                  'Sends this entry to another phone with Vaultly, without '
                  'the internet. Password history stays on this phone.',
                ),
                if (entry.totp != null) ...[
                  RowGroup(
                    children: [
                      SettingsTile(
                        icon: Icons.pin_outlined,
                        title: 'Include 2FA secret',
                        subtitle: 'The other phone can then make your codes',
                        showChevron: false,
                        trailing: Switch(
                          value: _includeTotp,
                          onChanged: (v) => setState(() => _includeTotp = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                VaultButton(
                  label: 'To a phone nearby',
                  icon: Icons.qr_code_scanner_rounded,
                  onPressed: () => setState(() {
                    _error = null;
                    _step = _Step.scan;
                  }),
                ),
                const SizedBox(height: AppSpacing.smd),
                VaultButton(
                  label: 'As a file',
                  icon: Icons.insert_drive_file_outlined,
                  variant: VaultButtonVariant.secondary,
                  onPressed: _asFile,
                ),
              ],
            _Step.scan => [
                const ShareHint(
                  'On the other phone, open Vault, then Receive an entry. '
                  'Scan the code it shows.',
                ),
                ShareScanner(onCode: _onScan),
              ],
            _Step.sealing => const [
                Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            _Step.showQr => [
                const ShareHint('On the other phone, tap Scan their code.'),
                ShareQrPanel(
                  data: _sealedQr!,
                  caption: 'Only the phone you scanned can open this code.',
                ),
              ],
            _Step.fileCode => [
                const ShareHint(
                  'The file opens only with this code. Send the code a '
                  'different way than the file: say it, or use another app.',
                ),
                VaultCard(
                  child: Column(
                    children: [
                      SelectableText(
                        _code!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.code.copyWith(
                          color: c.textPrimary,
                          fontSize: 20,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      VaultButton(
                        label: 'Copy code',
                        icon: Icons.copy_rounded,
                        variant: VaultButtonVariant.secondary,
                        onPressed: _copyCode,
                      ),
                    ],
                  ),
                ),
              ],
          },
        ],
      ),
    );
  }
}
