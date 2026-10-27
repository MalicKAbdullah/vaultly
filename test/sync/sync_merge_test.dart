import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/sync/services/sync_merge.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import '../fakes/fakes.dart';

DateTime t(int day) => DateTime.utc(2026, 10, day);

SyncSnapshot snap(
  List<VaultEntry> entries, [
  Map<String, DateTime> tombstones = const {},
]) =>
    SyncSnapshot(entries: entries, tombstones: tombstones);

VaultEntry item(
  String id, {
  String title = 'Site',
  String password = 'pw-1',
  int day = 1,
  List<PasswordHistoryEntry> history = const [],
}) =>
    makeEntry(
      id: id,
      title: title,
      password: password,
      createdAt: t(1),
      updatedAt: t(day),
      history: history,
    );

/// Runs the merge from both sides and checks they agree.
SyncMergeResult both(SyncSnapshot a, SyncSnapshot b) {
  final ab = SyncMerge.merge(local: a, remote: b);
  final ba = SyncMerge.merge(local: b, remote: a);
  expect(
    {for (final e in ab.snapshot.entries) e.id: e},
    {for (final e in ba.snapshot.entries) e.id: e},
    reason: 'both devices converge on the same items',
  );
  expect(ab.snapshot.tombstones, ba.snapshot.tombstones);
  expect(ab.changes, ba.changes);
  return ab;
}

void main() {
  group('SyncMerge', () {
    test('adds items that exist on one side only', () {
      final r = both(snap([item('a')]), snap([item('b')]));
      expect(r.snapshot.entries.map((e) => e.id), ['a', 'b']);
      expect(r.changes, 2);
    });

    test('identical vaults change nothing', () {
      final r = both(snap([item('a')]), snap([item('a')]));
      expect(r.changes, 0);
      expect(r.snapshot.entries.single, item('a'));
    });

    test('an edit on one side wins by updatedAt', () {
      final r = both(
        snap([item('a', title: 'Old', day: 1)]),
        snap([item('a', title: 'New', day: 2)]),
      );
      expect(r.snapshot.entries.single.title, 'New');
      expect(r.changes, 1);
    });

    test('a password change keeps the old password in history once', () {
      final old = item('a', password: 'old', day: 1);
      final edited = old.withNewPassword('new', t(2));
      final r = both(snap([old]), snap([edited]));
      final merged = r.snapshot.entries.single;
      expect(merged.password, 'new');
      expect(merged.history.map((h) => h.password), ['old']);
    });

    test('a conflict keeps the newest and saves the other password', () {
      final mine = item('a', title: 'Mine', password: 'mine-pw', day: 3);
      final theirs = item('a', title: 'Theirs', password: 'their-pw', day: 4);
      final merged = both(snap([mine]), snap([theirs])).snapshot.entries.single;
      expect(merged.title, 'Theirs');
      expect(merged.password, 'their-pw');
      expect(merged.history.single.password, 'mine-pw');
      expect(merged.history.single.replacedAt, t(3));
      expect(merged.updatedAt, t(4));
    });

    test('a conflict joins both password histories', () {
      final h1 = PasswordHistoryEntry(password: 'h1', replacedAt: t(2));
      final h2 = PasswordHistoryEntry(password: 'h2', replacedAt: t(3));
      final merged = both(
        snap([
          item('a', password: 'x', day: 5, history: [h1])
        ]),
        snap([
          item('a', password: 'y', day: 6, history: [h2])
        ]),
      ).snapshot.entries.single;
      expect(merged.history.map((h) => h.password), ['x', 'h2', 'h1']);
    });

    test('a same-time conflict resolves the same way on both devices', () {
      both(
        snap([item('a', title: 'Left', day: 2)]),
        snap([item('a', title: 'Right', day: 2)]),
      );
    });

    test('a deletion removes the item and keeps the tombstone', () {
      final r = both(snap([item('a', day: 1)]), snap([], {'a': t(2)}));
      expect(r.snapshot.entries, isEmpty);
      expect(r.snapshot.tombstones, {'a': t(2)});
      expect(r.changes, 1);
    });

    test('an edit newer than the deletion survives it', () {
      final r = both(snap([item('a', day: 3)]), snap([], {'a': t(2)}));
      expect(r.snapshot.entries.single.id, 'a');
      expect(r.snapshot.tombstones, isEmpty);
    });

    test('a deletion at the same moment as the edit wins', () {
      final r = both(snap([item('a', day: 2)]), snap([], {'a': t(2)}));
      expect(r.snapshot.entries, isEmpty);
    });

    test('tombstones from both sides are joined, keeping the later time', () {
      final r = both(
        snap([], {'a': t(2), 'b': t(5)}),
        snap([], {'a': t(3), 'c': t(1)}),
      );
      expect(r.snapshot.tombstones, {'a': t(3), 'b': t(5), 'c': t(1)});
      expect(r.changes, 0);
    });

    test('syncing the result again is a no-op (idempotent)', () {
      final a = snap(
        [item('a', day: 2), item('b', password: 'b1', day: 3)],
        {'z': t(1)},
      );
      final b = snap(
        [item('b', password: 'b2', day: 4), item('c')],
        {'a': t(5)},
      );
      final first = both(a, b).snapshot;
      final again = both(first, first);
      expect(again.changes, 0);
      expect(again.snapshot.entries, first.entries);
      expect(again.snapshot.tombstones, first.tombstones);
      // And merging the result with either original side converges too.
      expect(both(first, a).snapshot.entries.toSet(), first.entries.toSet());
      expect(both(first, b).snapshot.entries.toSet(), first.entries.toSet());
    });

    test('snapshot JSON round-trips', () {
      final s = snap([item('a', day: 2)], {'b': t(3)});
      final back = SyncSnapshot.fromJson(s.toJson());
      expect(back.entries, s.entries);
      expect(back.tombstones, s.tombstones);
    });
  });
}
