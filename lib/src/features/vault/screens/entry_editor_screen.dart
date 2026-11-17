import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/features/generator/widgets/generator_panel.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Create or edit a vault entry, with the generator one tap away.
///
/// Each category shows its own form. A section the entry already holds data
/// in stays visible whatever the category, so switching category never
/// hides (and then silently keeps or drops) anything.
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

  final _holderController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvcController = TextEditingController();

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();

  EntryCategory _category = EntryCategory.login;
  bool _obscure = true;
  bool _busy = false;
  String? _titleError;
  String? _totpError;
  String? _expiryError;
  bool _loadedExisting = false;

  /// Sections that hold data (from the stored entry or typed before a
  /// category switch), shown whatever the category.
  bool _hasSignIn = false;
  bool _hasCard = false;
  bool _hasIdentity = false;

  bool get _isEditing => widget.entryId != null;

  bool get _showSignIn =>
      _category == EntryCategory.login ||
      _category == EntryCategory.note ||
      _hasSignIn;

  bool get _showCard => _category == EntryCategory.card || _hasCard;

  bool get _showIdentity => _category == EntryCategory.identity || _hasIdentity;

  List<TextEditingController> get _controllers => [
        _titleController,
        _usernameController,
        _passwordController,
        _urlController,
        _notesController,
        _totpController,
        _holderController,
        _numberController,
        _expiryController,
        _cvcController,
        _fullNameController,
        _emailController,
        _phoneController,
        _address1Controller,
        _address2Controller,
        _cityController,
        _regionController,
        _postalCodeController,
        _countryController,
      ];

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
    _hasSignIn = entry.username.isNotEmpty ||
        entry.password.isNotEmpty ||
        entry.url.isNotEmpty ||
        entry.totp != null;

    final card = entry.card;
    if (card != null) {
      _hasCard = true;
      _holderController.text = card.holder;
      _numberController.text = card.groupedNumber;
      _expiryController.text = card.expiry;
      _cvcController.text = card.cvc;
    }
    final identity = entry.identity;
    if (identity != null) {
      _hasIdentity = true;
      _fullNameController.text = identity.fullName;
      _emailController.text = identity.email;
      _phoneController.text = identity.phone;
      _address1Controller.text = identity.address1;
      _address2Controller.text = identity.address2;
      _cityController.text = identity.city;
      _regionController.text = identity.region;
      _postalCodeController.text = identity.postalCode;
      _countryController.text = identity.country;
    }
  }

  /// Keeps every section that holds typed data on screen after the switch.
  void _switchCategory(EntryCategory category) {
    bool any(List<TextEditingController> fields) =>
        fields.any((f) => f.text.trim().isNotEmpty);
    setState(() {
      _hasSignIn = _hasSignIn ||
          (_showSignIn &&
              any([
                _usernameController,
                _passwordController,
                _urlController,
                _totpController,
              ]));
      _hasCard = _hasCard ||
          (_showCard &&
              any([
                _holderController,
                _numberController,
                _expiryController,
                _cvcController,
              ]));
      _hasIdentity = _hasIdentity ||
          (_showIdentity &&
              any([
                _fullNameController,
                _emailController,
                _phoneController,
                _address1Controller,
                _address2Controller,
                _cityController,
                _regionController,
                _postalCodeController,
                _countryController,
              ]));
      _category = category;
    });
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
    for (final c in _controllers) {
      c.dispose();
    }
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

  /// The card typed into the form, or null when the form is blank.
  CardDetails? _card(({String month, String year}) expiry) {
    final card = CardDetails(
      holder: _holderController.text.trim(),
      number: CardDetails.digitsOf(_numberController.text),
      expMonth: expiry.month,
      expYear: expiry.year,
      cvc: _cvcController.text.trim(),
    );
    return card.isEmpty ? null : card;
  }

  /// The identity typed into the form, or null when the form is blank.
  IdentityDetails? _identity() {
    final identity = IdentityDetails(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      address1: _address1Controller.text.trim(),
      address2: _address2Controller.text.trim(),
      city: _cityController.text.trim(),
      region: _regionController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      country: _countryController.text.trim(),
    );
    return identity.isEmpty ? null : identity;
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
    final expiry = CardDetails.parseExpiry(_expiryController.text);
    if (expiry == null) {
      setState(() => _expiryError = 'Use MM/YY, like 07/30.');
      return;
    }
    setState(() {
      _busy = true;
      _titleError = null;
      _totpError = null;
      _expiryError = null;
    });
    final card = _card(expiry);
    final identity = _identity();
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
        card: card,
        identity: identity,
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
        card: card,
        identity: identity,
      );
    }
    if (mounted) context.pop();
  }

  String get _titleHint => switch (_category) {
        EntryCategory.card => 'e.g. Visa debit',
        EntryCategory.identity => 'e.g. Home',
        EntryCategory.note => 'e.g. Wi-Fi codes',
        _ => 'e.g. Personal email',
      };

  @override
  Widget build(BuildContext context) {
    _maybeLoadExisting();
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
              onChanged: _switchCategory,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Title',
              controller: _titleController,
              hint: _titleHint,
              errorText: _titleError,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            if (_showCard) ..._cardSection(),
            if (_showIdentity) ..._identitySection(),
            if (_showSignIn) ..._signInSection(context),
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

  List<Widget> _cardSection() {
    const gap = SizedBox(height: AppSpacing.smd);
    return [
      const SizedBox(height: AppSpacing.lg),
      const SectionHeader(title: 'Card'),
      AppTextField(
        label: 'Name on card',
        controller: _holderController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.person_outline_rounded,
      ),
      gap,
      AppTextField(
        label: 'Card number',
        controller: _numberController,
        obscureText: true,
        monospace: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9 ]'))],
        prefixIcon: Icons.credit_card_rounded,
      ),
      gap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              label: 'Expires',
              hint: 'MM/YY',
              controller: _expiryController,
              errorText: _expiryError,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.datetime,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (_) {
                if (_expiryError != null) {
                  setState(() => _expiryError = null);
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.smd),
          Expanded(
            child: AppTextField(
              label: 'Security code',
              controller: _cvcController,
              obscureText: true,
              monospace: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _identitySection() {
    const gap = SizedBox(height: AppSpacing.smd);
    return [
      const SizedBox(height: AppSpacing.lg),
      const SectionHeader(title: 'Contact'),
      AppTextField(
        label: 'Full name',
        controller: _fullNameController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.person_outline_rounded,
      ),
      gap,
      AppTextField(
        label: 'Email',
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.mail_outline_rounded,
      ),
      gap,
      AppTextField(
        label: 'Phone',
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.phone_outlined,
      ),
      const SizedBox(height: AppSpacing.lg),
      const SectionHeader(title: 'Address'),
      AppTextField(
        label: 'Street address',
        controller: _address1Controller,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      gap,
      AppTextField(
        label: 'Flat, floor, building',
        controller: _address2Controller,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      gap,
      AppTextField(
        label: 'City',
        controller: _cityController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      gap,
      AppTextField(
        label: 'State or region',
        controller: _regionController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      gap,
      AppTextField(
        label: 'Postal code',
        controller: _postalCodeController,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        textInputAction: TextInputAction.next,
      ),
      gap,
      AppTextField(
        label: 'Country',
        controller: _countryController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
    ];
  }

  List<Widget> _signInSection(BuildContext context) {
    final c = SuiteColors.of(context);
    const gap = SizedBox(height: AppSpacing.smd);
    return [
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
    ];
  }
}
