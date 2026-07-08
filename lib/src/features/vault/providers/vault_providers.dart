import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/backup/providers/backup_providers.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

const _uuid = Uuid();

final vaultEntriesProvider =
    AsyncNotifierProvider<VaultNotifier, List<VaultEntry>>(VaultNotifier.new);

/// Loads and mutates the decrypted vault for the current session. Every
/// mutation is persisted (re-encrypted) immediately.
class VaultNotifier extends AsyncNotifier<List<VaultEntry>> {
  @override
  Future<List<VaultEntry>> build() async {
    final status = ref.watch(sessionProvider);
    if (status != AuthStatus.unlocked) return const [];

    final session = ref.read(sessionProvider.notifier);
    final entries =
        await ref.read(vaultRepositoryProvider).load(session.vaultKey);

    // Scheduled auto-backup piggybacks on unlock; it never blocks loading.
    unawaited(
      ref.read(autoBackupControllerProvider.notifier).runIfDue(entries),
    );
    return entries;
  }

  List<VaultEntry> get _current => state.valueOrNull ?? const [];

  DateTime _now() => ref.read(clockProvider).now();

  /// Creates a new entry and returns it.
  Future<VaultEntry> create({
    required String title,
    required String username,
    required String password,
    required String url,
    required String notes,
    required EntryCategory category,
    TotpConfig? totp,
    bool favorite = false,
  }) async {
    final now = _now();
    final entry = VaultEntry(
      id: _uuid.v4(),
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      category: category,
      favorite: favorite,
      totp: totp,
      createdAt: now,
      updatedAt: now,
      passwordChangedAt: now,
    );
    await commit([..._current, entry]);
    return entry;
  }

  /// Applies edits to an existing entry. When the password changed, the old
  /// one is pushed into the entry's history.
  Future<void> applyEdit(
    String id, {
    required String title,
    required String username,
    required String password,
    required String url,
    required String notes,
    required EntryCategory category,
    TotpConfig? totp,
  }) async {
    final now = _now();
    await commit([
      for (final e in _current)
        if (e.id == id)
          e.withNewPassword(password, now).copyWith(
                title: title,
                username: username,
                url: url,
                notes: notes,
                category: category,
                totp: () => totp,
                updatedAt: now,
              )
        else
          e,
    ]);
  }

  Future<void> toggleFavorite(String id) async {
    final now = _now();
    await commit([
      for (final e in _current)
        if (e.id == id)
          e.copyWith(favorite: !e.favorite, updatedAt: now)
        else
          e,
    ]);
  }

  Future<void> delete(String id) async {
    await commit(_current.where((e) => e.id != id).toList());
  }

  /// Replaces the whole vault (backup import).
  Future<void> replaceAll(List<VaultEntry> entries) => commit(entries);

  /// Persists [entries] and publishes them as the new state.
  @protected
  @visibleForOverriding
  Future<void> commit(List<VaultEntry> entries) async {
    final session = ref.read(sessionProvider.notifier);
    await ref
        .read(vaultRepositoryProvider)
        .save(entries, session.vaultKey, session.salt);
    state = AsyncData(entries);
  }
}

/// Sort order for the vault list.
enum VaultSort {
  recent('Recently updated'),
  alphabetical('A to Z');

  const VaultSort(this.label);

  final String label;
}

/// Search/filter/sort state for the vault list.
final vaultQueryProvider =
    NotifierProvider<VaultQueryNotifier, VaultQuery>(VaultQueryNotifier.new);

@immutable
final class VaultQuery {
  const VaultQuery({
    this.search = '',
    this.category,
    this.favoritesOnly = false,
    this.sort = VaultSort.recent,
  });

  final String search;
  final EntryCategory? category;
  final bool favoritesOnly;
  final VaultSort sort;

  VaultQuery copyWith({
    String? search,
    EntryCategory? Function()? category,
    bool? favoritesOnly,
    VaultSort? sort,
  }) =>
      VaultQuery(
        search: search ?? this.search,
        category: category == null ? this.category : category(),
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        sort: sort ?? this.sort,
      );
}

final class VaultQueryNotifier extends Notifier<VaultQuery> {
  @override
  VaultQuery build() => const VaultQuery();

  void setSearch(String value) => state = state.copyWith(search: value);

  void setCategory(EntryCategory? category) =>
      state = state.copyWith(category: () => category);

  void toggleFavoritesOnly() =>
      state = state.copyWith(favoritesOnly: !state.favoritesOnly);

  void setSort(VaultSort sort) => state = state.copyWith(sort: sort);
}

/// The vault list after search, filters, and sorting are applied.
final filteredEntriesProvider = Provider<List<VaultEntry>>((ref) {
  final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
  final query = ref.watch(vaultQueryProvider);

  final needle = query.search.trim().toLowerCase();
  var result = entries.where((e) {
    if (query.favoritesOnly && !e.favorite) return false;
    if (query.category != null && e.category != query.category) return false;
    if (needle.isEmpty) return true;
    return e.title.toLowerCase().contains(needle) ||
        e.username.toLowerCase().contains(needle) ||
        e.url.toLowerCase().contains(needle);
  }).toList();

  result = switch (query.sort) {
    VaultSort.recent => result
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    VaultSort.alphabetical => result
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
  };
  return result;
});

/// Looks up one entry by id (detail screen).
final entryByIdProvider = Provider.family<VaultEntry?, String>((ref, id) {
  final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
  for (final entry in entries) {
    if (entry.id == id) return entry;
  }
  return null;
});
