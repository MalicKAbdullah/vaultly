import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// A shared entry could not be read. [message] is safe to show.
final class ShareException implements Exception {
  const ShareException(this.message);

  final String message;

  @override
  String toString() => 'ShareException: $message';
}

/// What one shared entry carries, as plaintext before encryption.
///
/// Passkeys are never shared (a copied passkey is a cloned credential) and
/// password history never leaves the phone. The 2FA secret goes only when
/// the sender switches it on.
abstract final class SharedEntry {
  /// Encodes [entry]. A passkey entry has no share path in the UI, so one
  /// arriving here is a programming error.
  static Uint8List encode(VaultEntry entry, {required bool includeTotp}) {
    if (entry.passkey != null) {
      throw ArgumentError.value(entry.id, 'entry', 'Passkeys cannot be shared');
    }
    return utf8.encode(jsonEncode({
      'format': VaultRepository.formatVersion,
      'entry': {
        'title': entry.title,
        'username': entry.username,
        'password': entry.password,
        'url': entry.url,
        'notes': entry.notes,
        'category': entry.category.name,
        if (includeTotp && entry.totp != null) 'totp': entry.totp!.toJson(),
        if (entry.card != null) 'card': entry.card!.toJson(),
        if (entry.identity != null) 'identity': entry.identity!.toJson(),
      },
    }));
  }

  /// A new vault entry from shared [bytes]: its own id and timestamps, so
  /// it is added beside anything already in the vault, never merged.
  static VaultEntry decode(
    List<int> bytes, {
    required String id,
    required DateTime now,
  }) {
    final Map<String, dynamic> doc;
    try {
      doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on Object {
      throw const ShareException('This is not a Vaultly shared entry.');
    }
    final format = doc['format'];
    if (format is! int || doc['entry'] is! Map<String, dynamic>) {
      throw const ShareException('This is not a Vaultly shared entry.');
    }
    if (format > VaultRepository.formatVersion) {
      throw const ShareException(
        'This entry comes from a newer Vaultly. Update Vaultly, then try '
        'again.',
      );
    }
    final e = doc['entry'] as Map<String, dynamic>;
    try {
      final category = EntryCategory.parse(e['category'] as String);
      // Senders never share passkeys; a payload claiming one is forged.
      if (category == EntryCategory.passkey) throw const FormatException();
      return VaultEntry(
        id: id,
        title: e['title'] as String,
        username: e['username'] as String,
        password: e['password'] as String,
        url: e['url'] as String,
        notes: e['notes'] as String,
        category: category,
        totp: e['totp'] == null
            ? null
            : TotpConfig.fromJson(e['totp'] as Map<String, dynamic>),
        card: e['card'] == null
            ? null
            : CardDetails.fromJson(e['card'] as Map<String, dynamic>),
        identity: e['identity'] == null
            ? null
            : IdentityDetails.fromJson(e['identity'] as Map<String, dynamic>),
        createdAt: now,
        updatedAt: now,
        passwordChangedAt: now,
      );
    } on Object {
      throw const ShareException('This is not a Vaultly shared entry.');
    }
  }
}
