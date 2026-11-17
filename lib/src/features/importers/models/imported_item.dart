import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Where an import came from. Drives the labels on the preview screen.
enum ImportSource {
  chrome('Chrome / Google Password Manager'),
  bitwardenJson('Bitwarden (JSON)'),
  bitwardenCsv('Bitwarden (CSV)'),
  onePassword1pux('1Password (.1pux)'),
  onePasswordCsv('1Password (CSV)'),
  genericCsv('CSV file'),
  googleAuthenticator('Google Authenticator');

  const ImportSource(this.label);

  final String label;
}

/// One vault item read from another app's export, before it gets an id and
/// timestamps in this vault.
@immutable
final class ImportedItem {
  const ImportedItem({
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.category = EntryCategory.login,
    this.favorite = false,
    this.totp,
    this.card,
    this.identity,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final EntryCategory category;
  final bool favorite;
  final TotpConfig? totp;
  final CardDetails? card;
  final IdentityDetails? identity;

  /// What tells this item apart from others with the same title; see
  /// [accountKey].
  String get account => accountKey(
        category: category,
        username: username,
        password: password,
        card: card,
        identity: identity,
      );

  VaultEntry toEntry({required String id, required DateTime now}) => VaultEntry(
        id: id,
        title: title,
        username: username,
        password: password,
        url: url,
        notes: notes,
        category: category,
        favorite: favorite,
        totp: totp,
        card: card,
        identity: identity,
        createdAt: now,
        updatedAt: now,
        passwordChangedAt: now,
      );

  @override
  bool operator ==(Object other) =>
      other is ImportedItem &&
      other.title == title &&
      other.username == username &&
      other.password == password &&
      other.url == url &&
      other.notes == notes &&
      other.category == category &&
      other.favorite == favorite &&
      other.totp == totp &&
      other.card == card &&
      other.identity == identity;

  @override
  int get hashCode => Object.hash(title, username, password, url, notes,
      category, favorite, totp, card, identity);
}

/// What tells an item apart from others with the same title: a card's
/// number, an identity's email, otherwise the username.
///
/// Cards and identities imported before they had their own fields keep the
/// number in [password] and the email in [username]; reading those keeps a
/// re-import of the same export matching them.
String accountKey({
  required EntryCategory category,
  required String username,
  required String password,
  required CardDetails? card,
  required IdentityDetails? identity,
}) =>
    switch (category) {
      EntryCategory.card => card == null ? password : card.number,
      EntryCategory.identity => identity == null ? username : identity.email,
      _ => username,
    };

/// A two-factor account from an authenticator export: no password, only the
/// code settings and the labels that say which login it belongs to.
@immutable
final class ImportedAuthenticator {
  const ImportedAuthenticator({
    required this.config,
    this.issuer = '',
    this.account = '',
  });

  final TotpConfig config;
  final String issuer;
  final String account;

  @override
  bool operator ==(Object other) =>
      other is ImportedAuthenticator &&
      other.config == config &&
      other.issuer == issuer &&
      other.account == account;

  @override
  int get hashCode => Object.hash(config, issuer, account);
}

/// Everything one export file (or one set of migration QR codes) yielded.
@immutable
final class ImportBatch {
  const ImportBatch({
    required this.source,
    this.items = const [],
    this.authenticators = const [],
    this.warnings = const [],
  });

  final ImportSource source;
  final List<ImportedItem> items;
  final List<ImportedAuthenticator> authenticators;

  /// Human-readable notes about records that could not be imported.
  final List<String> warnings;

  bool get isEmpty => items.isEmpty && authenticators.isEmpty;

  ImportBatch merge(ImportBatch other) => ImportBatch(
        source: source,
        items: [...items, ...other.items],
        authenticators: [...authenticators, ...other.authenticators],
        warnings: [...warnings, ...other.warnings],
      );
}

/// Thrown when an export file cannot be read at all (wrong format, encrypted
/// export, corrupt archive). [message] is shown to the user as-is.
final class ImportFormatException implements Exception {
  const ImportFormatException(this.message);

  final String message;

  @override
  String toString() => 'ImportFormatException: $message';
}
