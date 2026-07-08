import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/backup/services/vault_merge.dart';

import 'fakes/fakes.dart';

void main() {
  group('VaultMerge.merge', () {
    test('keeps entries unique to either side', () {
      final current = [makeEntry(id: 'a')];
      final incoming = [makeEntry(id: 'b')];
      final merged = VaultMerge.merge(current: current, incoming: incoming);
      expect(merged.map((e) => e.id), ['a', 'b']);
    });

    test('newer updatedAt wins when both sides share an id', () {
      final older = makeEntry(
        id: 'a',
        title: 'Old title',
        updatedAt: DateTime(2026, 1, 1),
      );
      final newer = makeEntry(
        id: 'a',
        title: 'New title',
        updatedAt: DateTime(2026, 6, 1),
      );

      final incomingWins =
          VaultMerge.merge(current: [older], incoming: [newer]);
      expect(incomingWins.single.title, 'New title');

      final currentWins = VaultMerge.merge(current: [newer], incoming: [older]);
      expect(currentWins.single.title, 'New title');
    });

    test('tie on updatedAt keeps the current entry', () {
      final when = DateTime(2026, 3, 1);
      final current = makeEntry(id: 'a', title: 'Current', updatedAt: when);
      final incoming = makeEntry(id: 'a', title: 'Incoming', updatedAt: when);
      final merged = VaultMerge.merge(current: [current], incoming: [incoming]);
      expect(merged.single.title, 'Current');
    });

    test('merging an empty incoming list changes nothing', () {
      final current = [makeEntry(id: 'a'), makeEntry(id: 'b')];
      expect(
        VaultMerge.merge(current: current, incoming: const []),
        current,
      );
    });
  });

  group('VaultMerge.apply', () {
    test('replace mode discards the current vault entirely', () {
      final result = VaultMerge.apply(
        mode: ImportMode.replace,
        current: [makeEntry(id: 'a')],
        incoming: [makeEntry(id: 'b')],
      );
      expect(result.map((e) => e.id), ['b']);
    });

    test('merge mode delegates to merge semantics', () {
      final result = VaultMerge.apply(
        mode: ImportMode.merge,
        current: [makeEntry(id: 'a')],
        incoming: [makeEntry(id: 'b')],
      );
      expect(result.length, 2);
    });
  });
}
