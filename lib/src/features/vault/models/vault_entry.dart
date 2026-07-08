import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';

/// The kind of item stored in the vault.
enum EntryCategory {
  login('Login'),
  card('Card'),
  identity('Identity'),
  note('Note');

  const EntryCategory(this.label);

  final String label;

  static EntryCategory parse(String? raw) => EntryCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => EntryCategory.login,
      );
}

/// A password the entry used in the past, kept when the password changes.
@immutable
final class PasswordHistoryEntry {
  const PasswordHistoryEntry(
      {required this.password, required this.replacedAt});

  factory PasswordHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PasswordHistoryEntry(
        password: json['password'] as String,
        replacedAt: DateTime.parse(json['replacedAt'] as String),
      );

  final String password;

  /// When this password stopped being the current one.
  final DateTime replacedAt;

  Map<String, dynamic> toJson() => {
        'password': password,
        'replacedAt': replacedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is PasswordHistoryEntry &&
      other.password == password &&
      other.replacedAt == replacedAt;

  @override
  int get hashCode => Object.hash(password, replacedAt);
}

/// A single vault item. Immutable; use [copyWith] and [withNewPassword].
@immutable
final class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.passwordChangedAt,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.category = EntryCategory.login,
    this.favorite = false,
    this.totp,
    this.history = const [],
  });

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        category: EntryCategory.parse(json['category'] as String?),
        favorite: json['favorite'] as bool? ?? false,
        // Vaults written before 1.1 have no totp field; a missing value
        // simply means "no two-factor secret" so old files keep loading.
        totp: json['totp'] == null
            ? null
            : TotpConfig.fromJson(json['totp'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        passwordChangedAt: DateTime.parse(
          (json['passwordChangedAt'] ?? json['createdAt']) as String,
        ),
        history: ((json['history'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PasswordHistoryEntry.fromJson)
            .toList(),
      );

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final EntryCategory category;
  final bool favorite;

  /// Two-factor (TOTP) secret and parameters, when the account has 2FA.
  final TotpConfig? totp;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// When the current password was set (used by vault health "old" checks).
  final DateTime passwordChangedAt;

  /// Previous passwords, most recent first.
  final List<PasswordHistoryEntry> history;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'category': category.name,
        'favorite': favorite,
        if (totp != null) 'totp': totp!.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'passwordChangedAt': passwordChangedAt.toIso8601String(),
        'history': history.map((h) => h.toJson()).toList(),
      };

  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    EntryCategory? category,
    bool? favorite,
    TotpConfig? Function()? totp,
    DateTime? updatedAt,
    DateTime? passwordChangedAt,
    List<PasswordHistoryEntry>? history,
  }) =>
      VaultEntry(
        id: id,
        title: title ?? this.title,
        username: username ?? this.username,
        password: password ?? this.password,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        favorite: favorite ?? this.favorite,
        totp: totp == null ? this.totp : totp(),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        passwordChangedAt: passwordChangedAt ?? this.passwordChangedAt,
        history: history ?? this.history,
      );

  /// Returns a copy with [newPassword], pushing the current password into
  /// [history] (when non-empty) and stamping [now] on the change fields.
  VaultEntry withNewPassword(String newPassword, DateTime now) {
    if (newPassword == password) return this;
    return copyWith(
      password: newPassword,
      updatedAt: now,
      passwordChangedAt: now,
      history: [
        if (password.isNotEmpty)
          PasswordHistoryEntry(password: password, replacedAt: now),
        ...history,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VaultEntry &&
      other.id == id &&
      other.title == title &&
      other.username == username &&
      other.password == password &&
      other.url == url &&
      other.notes == notes &&
      other.category == category &&
      other.favorite == favorite &&
      other.totp == totp &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.passwordChangedAt == passwordChangedAt &&
      listEquals(other.history, history);

  @override
  int get hashCode => Object.hash(id, title, username, password, url, notes,
      category, favorite, totp, createdAt, updatedAt, passwordChangedAt);
}
