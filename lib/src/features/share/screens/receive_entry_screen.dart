import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/share/crypto/entry_share.dart';
import 'package:vaultkey/src/features/share/providers/share_providers.dart';
import 'package:vaultkey/src/features/share/services/shared_entry.dart';
import 'package:vaultkey/src/features/share/widgets/share_widgets.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

enum _Step { showInvite, scan, enterCode, opening, preview }

/// Receives one entry from another phone: shows a one-time code for the
/// sender to scan, then scans the sender's reply; or, given a shared file
/// ([fileContent]), asks for its code. Either way the entry is previewed
/// and added as a new item, never merged over an existing one.
class ReceiveEntryScreen extends ConsumerStatefulWidget {
  const ReceiveEntryScreen({this.fileContent, super.key});

  /// A `.vaultlyshare` file's text, when receiving a file.
  final String? fileContent;

  @override
  ConsumerState<ReceiveEntryScreen> createState() => _ReceiveEntryScreenState();
}

class _ReceiveEntryScreenState extends ConsumerState<ReceiveEntryScreen> {
  late _Step _step =
      widget.fileContent == null ? _Step.showInvite : _Step.enterCode;
  ShareInvite? _invite;
  bool _scanned = false;
  VaultEntry? _entry;
  String? _error;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.fileContent == null) {
      // The key pair lives only as long as this screen.
      ShareInvite.create().then((invite) {
        if (mounted) setState(() => _invite = invite);
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  VaultEntry _decode(List<int> bytes) => SharedEntry.decode(
        bytes,
        id: const Uuid().v4(),
        now: ref.read(clockProvider).now(),
      );

  Future<void> _onScan(String raw) async {
    if (_scanned || !raw.startsWith(QrShare.shareScheme)) return;
    _scanned = true;
    setState(() => _step = _Step.opening);
    try {
      final entry = _decode(await _invite!.open(raw));
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _step = _Step.preview;
      });
    } on ShareException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _scanned = false;
          _step = _Step.scan;
        });
      }
    }
  }

  Future<void> _openFile() async {
    setState(() {
      _step = _Step.opening;
      _error = null;
    });
    try {
      final bytes = await ref
          .read(fileShareProvider)
          .open(widget.fileContent!, _code.text);
      final entry = _decode(bytes);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _step = _Step.preview;
      });
    } on ShareException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _step = _Step.enterCode;
        });
      }
    }
  }

  Future<void> _add() async {
    await ref.read(vaultEntriesProvider.notifier).add(_entry!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_entry!.title} added to your vault.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Widget? action = switch (_step) {
      _Step.showInvite => VaultButton(
          label: 'Scan their code',
          icon: Icons.qr_code_scanner_rounded,
          onPressed:
              _invite == null ? null : () => setState(() => _step = _Step.scan),
        ),
      _Step.enterCode => VaultButton(label: 'Open', onPressed: _openFile),
      _Step.preview => VaultButton(label: 'Add to vault', onPressed: _add),
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Receive an entry')),
      bottomNavigationBar:
          action == null ? null : BottomActionBar(primary: action),
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
              title: 'Not received',
              message: _error,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...switch (_step) {
            _Step.showInvite => [
                const ShareHint(
                  'On the other phone, open the entry, tap Share, then To a '
                  'phone nearby, and scan this code.',
                ),
                if (_invite == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ShareQrPanel(
                    data: _invite!.uri,
                    caption: 'This code works only while this screen is open.',
                  ),
              ],
            _Step.scan => [
                const ShareHint('Scan the code the other phone now shows.'),
                ShareScanner(onCode: _onScan),
              ],
            _Step.enterCode => [
                const ShareHint('Type the code the sender gave you.'),
                AppTextField(
                  label: 'Code',
                  controller: _code,
                  hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                  monospace: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _openFile(),
                ),
              ],
            _Step.opening => const [
                Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            _Step.preview => [_Preview(entry: _entry!)],
          },
        ],
      ),
    );
  }
}

/// What will be added: name, kind, and which details came with it. Secrets
/// are named, never shown.
class _Preview extends StatelessWidget {
  const _Preview({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final card = entry.card;
    final identity = entry.identity;
    final details = [
      if (entry.username.isNotEmpty) entry.username,
      if (entry.url.isNotEmpty) entry.url,
      if (card != null && card.number.isNotEmpty) card.maskedLabel,
      if (identity != null && identity.fullName.isNotEmpty) identity.fullName,
      if (entry.password.isNotEmpty) 'Password',
      if (entry.totp != null) '2FA codes',
      if (entry.notes.isNotEmpty) 'Notes',
    ];
    return VaultCard(
      child: Row(
        children: [
          EntryAvatar(entry: entry, size: 52),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: AppTextStyles.h3.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  [entry.category.label, ...details].join(' · '),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
