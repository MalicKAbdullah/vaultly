import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// One device's side of a sync: its items and when it deleted items.
@immutable
final class SyncSnapshot {
  const SyncSnapshot({required this.entries, required this.tombstones});

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) => SyncSnapshot(
        entries: (json['entries'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(VaultEntry.fromJson)
            .toList(),
        tombstones: {
          for (final e in (json['tombstones'] as Map<String, dynamic>).entries)
            e.key: DateTime.parse(e.value as String),
        },
      );

  final List<VaultEntry> entries;

  /// Deleted item id → when it was deleted.
  final Map<String, DateTime> tombstones;

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'tombstones': {
          for (final t in tombstones.entries) t.key: t.value.toIso8601String(),
        },
      };
}

/// The merged vault both devices converge on, and how many items differ
/// from what either device had before.
@immutable
final class SyncMergeResult {
  const SyncMergeResult({
    required this.snapshot,
    required this.changes,
  });

  final SyncSnapshot snapshot;

  /// Items whose final state differs from at least one device's previous
  /// state. Both devices compute the same number.
  final int changes;
}

/// Per-item last-writer-wins merge with tombstones.
///
/// The result depends only on the two snapshots, never on which device runs
/// it, so both phones reach the same vault from one exchange:
/// - an item on one side only is kept unless a tombstone at or after its
///   `updatedAt` deletes it;
/// - an item on both sides keeps the newer `updatedAt` (ties broken by the
///   item's canonical JSON); the other version's password, when different,
///   is saved in the winner's password history, and both histories are
///   joined;
/// - tombstones are joined, keeping the later time per id, and dropped for
///   items that outlive them.
abstract final class SyncMerge {
  static SyncMergeResult merge({
    required SyncSnapshot local,
    required SyncSnapshot remote,
  }) {
    final localById = {for (final e in local.entries) e.id: e};
    final remoteById = {for (final e in remote.entries) e.id: e};
    final ids = <String>{
      ...localById.keys,
      ...remoteById.keys,
      ...local.tombstones.keys,
      ...remote.tombstones.keys,
    };

    final merged = <String, VaultEntry>{};
    final tombstones = <String, DateTime>{};
    var changes = 0;
    for (final id in ids) {
      final l = localById[id];
      final r = remoteById[id];
      final lt = local.tombstones[id];
      final rt = remote.tombstones[id];
      final deletedAt =
          lt == null ? rt : (rt == null || lt.isAfter(rt) ? lt : rt);

      var candidate = l != null && r != null ? resolve(l, r) : (l ?? r);
      if (candidate != null &&
          deletedAt != null &&
          !deletedAt.isBefore(candidate.updatedAt)) {
        candidate = null;
      }
      if (candidate != null) {
        merged[id] = candidate;
      } else if (deletedAt != null) {
        tombstones[id] = deletedAt;
      }
      if (candidate != l || candidate != r) changes++;
    }

    // Keep the local order, then items new from the remote in its order.
    final entries = [
      for (final e in local.entries)
        if (merged.containsKey(e.id)) merged[e.id]!,
      for (final e in remote.entries)
        if (!localById.containsKey(e.id) && merged.containsKey(e.id))
          merged[e.id]!,
    ];
    return SyncMergeResult(
      snapshot: SyncSnapshot(entries: entries, tombstones: tombstones),
      changes: changes,
    );
  }

  /// The surviving version of an item both devices have.
  static VaultEntry resolve(VaultEntry a, VaultEntry b) {
    if (a == b) return a;
    final aWins = switch (a.updatedAt.compareTo(b.updatedAt)) {
      > 0 => true,
      < 0 => false,
      _ => _canonical(a).compareTo(_canonical(b)) > 0,
    };
    final winner = aWins ? a : b;
    final loser = aWins ? b : a;

    final history = <PasswordHistoryEntry>{
      ...winner.history,
      ...loser.history,
    }.toList();
    final known = {winner.password, ...history.map((h) => h.password)};
    if (loser.password.isNotEmpty && !known.contains(loser.password)) {
      history.add(PasswordHistoryEntry(
        password: loser.password,
        replacedAt: loser.updatedAt,
      ));
    }
    history.sort((x, y) {
      final byTime = y.replacedAt.compareTo(x.replacedAt);
      return byTime != 0 ? byTime : x.password.compareTo(y.password);
    });
    if (listEquals(history, winner.history)) return winner;
    return winner.copyWith(history: history);
  }

  static String _canonical(VaultEntry e) => jsonEncode(e.toJson());
}
