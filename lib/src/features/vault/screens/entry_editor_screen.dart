import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/features/generator/widgets/generator_panel.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Create or edit a vault entry, with the generator one tap away.
class EntryEditorScreen extends ConsumerStatefulWidget {
  const EntryEditorScreen({this.entryId, super.key});

  final String? entryId;

  @override
  ConsumerState<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends ConsumerState<EntryEditorScreen> {
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();
  final _totpController = TextEditingController();
  EntryCategory _category = EntryCategory.login;
  bool _obscure = true;
  bool _busy = false;
  String? _titleError;
  String? _totpError;
  bool _loadedExisting = false;

  bool get _isEditing => widget.entryId != null;

  /// Populates the form once the entry is available (the vault loads
  /// asynchronously, so this may happen on a later build).
  void _maybeLoadExisting() {
    if (!_isEditing || _loadedExisting) return;
    final entry = ref.watch(entryByIdProvider(widget.entryId!));
    if (entry == null) return;
    _loadedExisting = true;
    _titleController.text = entry.title;
    _usernameController.text = entry.username;
    _passwordController.text = entry.password;
    _urlController.text = entry.url;
    _notesController.text = entry.notes;
    _totpController.text = _totpFieldText(entry.totp);
    _category = entry.category;
  }

  /// Shows a stored two-factor secret back to the user: the bare secret
  /// when it uses standard settings, the full setup link otherwise (so
  /// custom digits/period/algorithm survive an edit round-trip).
  static String _totpFieldText(TotpConfig? totp) {
    if (totp == null) return '';
    const defaults = TotpConfig(secret: '');
    if (totp.algorithm == defaults.algorithm &&
        totp.digits == defaults.digits &&
        totp.period == defaults.period) {
      return totp.secret;
    }
    return OtpauthParser.toUri(totp);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _openGenerator() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.gutter,
          right: AppSpacing.gutter,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: GeneratorPanel(
          onUse: (password) {
            setState(() => _passwordController.text = password);
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Give this entry a name.');
      return;
    }
    TotpConfig? totp;
    if (_totpController.text.trim().isNotEmpty) {
      try {
        totp = OtpauthParser.parseUserInput(_totpController.text);
      } on FormatException catch (e) {
        setState(() => _totpError = e.message);
        return;
      }
    }
    setState(() {
      _busy = true;
      _titleError = null;
      _totpError = null;
    });
    final notifier = ref.read(vaultEntriesProvider.notifier);
    if (_isEditing) {
      await notifier.applyEdit(
        widget.entryId!,
        title: title,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        url: _urlController.text.trim(),
        notes: _notesController.text.trim(),
        category: _category,
        totp: totp,
      );
    } else {
      await notifier.create(
        title: title,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        url: _urlController.text.trim(),
        notes: _notesController.text.trim(),
        category: _category,
        totp: totp,
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _maybeLoadExisting();
    final c = SuiteColors.of(context);
    const gap = SizedBox(height: AppSpacing.smd);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit entry' : 'New entry'),
      ),
      bottomNavigationBar: BottomActionBar(
        primary: VaultButton(
          label: _isEditing ? 'Save changes' : 'Add to vault',
          isLoading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ),
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
            AppSegmentedControl<EntryCategory>(
              height: 44,
              segments: [
                // Passkeys come only from Credential Manager.
                for (final category in EntryCategory.values)
                  if (category != EntryCategory.passkey)
                    AppSegment(value: category, label: category.label),
              ],
              selected: _category,
              onChanged: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Title',
              controller: _titleController,
              hint: 'e.g. Personal email',
              errorText: _titleError,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Sign-in'),
            AppTextField(
              label: 'Username / email',
              controller: _usernameController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.person_outline_rounded,
            ),
            gap,
            AppTextField(
              label: 'Password',
              controller: _passwordController,
              obscureText: _obscure,
              monospace: true,
              prefixIcon: Icons.key_rounded,
              onChanged: (_) => setState(() {}),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    tooltip: 'Generate password',
                    icon: Icon(Icons.casino_outlined, color: c.accent),
                    onPressed: _openGenerator,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.smd),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: StrengthMeter(password: _passwordController.text),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Website',
              controller: _urlController,
              hint: 'example.com',
              keyboardType: TextInputType.url,
              prefixIcon: Icons.language_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Two-factor',
              subtitle: 'If this account shows you rolling 6-digit codes, '
                  'paste its setup link or secret key here and Vaultly will '
                  'show the codes too.',
            ),
            AppTextField(
              label: 'Two-factor authentication (TOTP)',
              controller: _totpController,
              hint: 'Setup link (otpauth://…) or secret key — optional',
              errorText: _totpError,
              monospace: true,
              prefixIcon: Icons.pin_outlined,
              onChanged: (_) {
                if (_totpError != null) {
                  setState(() => _totpError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Notes'),
            AppTextField(
              label: 'Notes',
              controller: _notesController,
              hint: 'Anything else worth remembering',
              maxLines: 5,
              minLines: 3,
              clearable: false,
              keyboardType: TextInputType.multiline,
            ),
          ],
        ),
      ),
    );
  }
}
