import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// How an import is applied to the current vault.
enum ImportMode { merge, replace }

/// Pure merge semantics for backup imports.
abstract final class VaultMerge {
  /// Merges [incoming] into [current] by entry id: entries unique to either
  /// side are kept, and when both sides have the same id, the one with the
  /// newer `updatedAt` wins. Order: current entries first (possibly
  /// replaced), then new incoming ones.
  static List<VaultEntry> merge({
    required List<VaultEntry> current,
    required List<VaultEntry> incoming,
  }) {
    final incomingById = {for (final e in incoming) e.id: e};
    final result = <VaultEntry>[];

    for (final entry in current) {
      final candidate = incomingById.remove(entry.id);
      if (candidate == null) {
        result.add(entry);
      } else {
        result.add(
          candidate.updatedAt.isAfter(entry.updatedAt) ? candidate : entry,
        );
      }
    }
    result.addAll(incomingById.values);
    return result;
  }

  static List<VaultEntry> apply({
    required ImportMode mode,
    required List<VaultEntry> current,
    required List<VaultEntry> incoming,
  }) =>
      switch (mode) {
        ImportMode.merge => merge(current: current, incoming: incoming),
        ImportMode.replace => List.of(incoming),
      };
}
