import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/services/import_planner.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import '../fakes/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1);
  var ids = 0;
  String newId() => 'new-${ids++}';
  setUp(() => ids = 0);

  ImportOutcome run(
    List<ImportedItem> items, {
    DuplicateAction action = DuplicateAction.skip,
    List<ImportedAuthenticator> authenticators = const [],
    List<VaultEntry> current = const [],
  }) =>
      ImportPlanner.apply(
        current: current,
        batch: ImportBatch(
          source: ImportSource.genericCsv,
          items: items,
          authenticators: authenticators,
        ),
        action: action,
        now: now,
        newId: newId,
      );

  final existing = makeEntry(
    id: 'gh',
    title: 'GitHub',
    url: 'https://github.com',
    username: 'Octo',
    password: 'old-pw',
  );
  const sameSite = ImportedItem(
    title: 'github',
    url: 'https://www.github.com/login',
    username: 'octo',
    password: 'new-pw',
    notes: 'from chrome',
  );

  group('duplicate detection', () {
    test('same host (ignoring www and path) and username, any case', () {
      final o = run([sameSite], current: [existing]);
      expect(o.duplicates.single.existing.id, 'gh');
    });

    test('a different username is not a duplicate', () {
      final o = run(
        [const ImportedItem(title: 'x', url: 'github.com', username: 'bob')],
        current: [existing],
      );
      expect(o.duplicates, isEmpty);
      expect(o.added, 1);
    });

    test('falls back to the title when there is no URL', () {
      final o = run(
        [const ImportedItem(title: 'Router', username: 'admin')],
        current: [makeEntry(title: 'router', url: '', username: 'ADMIN')],
      );
      expect(o.duplicates, hasLength(1));
    });

    test('duplicates inside the same file are caught', () {
      final o = run([sameSite, sameSite]);
      expect(o.added, 1);
      expect(o.duplicates, hasLength(1));
    });
  });

  group('duplicate actions', () {
    test('skip leaves the vault untouched', () {
      final o = run([sameSite], current: [existing]);
      expect(o.entries, [existing]);
      expect(o.skipped, 1);
      expect(o.changes, 0);
    });

    test('keep both adds a second item', () {
      final o = run(
        [sameSite],
        current: [existing],
        action: DuplicateAction.keepBoth,
      );
      expect(o.entries, hasLength(2));
      expect(o.entries.last.id, 'new-0');
      expect(o.entries.last.password, 'new-pw');
    });

    test(
        'merge makes the imported password current and keeps the old '
        'one in history', () {
      final o = run(
        [sameSite],
        current: [existing],
        action: DuplicateAction.merge,
      );
      final merged = o.entries.single;
      expect(o.merged, 1);
      expect(merged.id, 'gh');
      expect(merged.password, 'new-pw');
      expect(merged.history.first.password, 'old-pw');
      expect(merged.notes, 'from chrome');
      expect(merged.title, 'GitHub');
      expect(merged.updatedAt, now);
    });

    test('merge fills empty fields without overwriting set ones', () {
      final o = run(
        [
          const ImportedItem(
            title: 'Other title',
            url: 'https://github.com',
            username: 'octo',
            totp: TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
            favorite: true,
          ),
        ],
        current: [existing],
        action: DuplicateAction.merge,
      );
      final merged = o.entries.single;
      expect(merged.title, 'GitHub');
      expect(merged.password, 'old-pw');
      expect(merged.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(merged.favorite, isTrue);
    });

    test('merging an identical item changes nothing', () {
      final o = run(
        [
          const ImportedItem(
            title: 'GitHub',
            url: 'https://github.com',
            username: 'Octo',
            password: 'old-pw',
          ),
        ],
        current: [existing],
        action: DuplicateAction.merge,
      );
      expect(o.entries.single, same(existing));
      expect(o.merged, 0);
      expect(o.skipped, 1);
    });
  });

  group('authenticator codes', () {
    const code = TotpConfig(secret: 'JBSWY3DPEHPK3PXP');

    test('attach to the login whose title/site and username match', () {
      final o = run(
        const [],
        current: [existing],
        authenticators: const [
          ImportedAuthenticator(
            config: code,
            issuer: 'GitHub',
            account: 'octo',
          ),
        ],
      );
      expect(o.totpAttached, 1);
      expect(o.entries.single.totp, code);
      expect(o.entries.single.updatedAt, now);
    });

    test('match by site when the title differs', () {
      final o = run(
        const [],
        current: [
          makeEntry(title: 'Work code', url: 'gitlab.com', username: 'me')
        ],
        authenticators: const [
          ImportedAuthenticator(config: code, issuer: 'GitLab', account: 'me'),
        ],
      );
      expect(o.totpAttached, 1);
    });

    test('create a new item when no login matches', () {
      final o = run(
        const [],
        current: [existing],
        authenticators: const [
          ImportedAuthenticator(config: code, issuer: 'Slack', account: 'me'),
        ],
      );
      expect(o.totpCreated, 1);
      final created = o.entries.last;
      expect(created.title, 'Slack');
      expect(created.username, 'me');
      expect(created.totp, code);
      expect(created.password, '');
    });

    test('an identical secret already there is not duplicated', () {
      final o = run(
        const [],
        current: [
          makeEntry(
            title: 'GitHub',
            username: 'octo',
            totp: const TotpConfig(secret: 'jbsw y3dp ehpk 3pxp'),
          ),
        ],
        authenticators: const [
          ImportedAuthenticator(
              config: code, issuer: 'GitHub', account: 'octo'),
        ],
      );
      expect(o.totpAlreadyPresent, 1);
      expect(o.entries, hasLength(1));
    });

    test('a login with a different secret is not overwritten', () {
      final o = run(
        const [],
        current: [
          makeEntry(
            title: 'GitHub',
            username: 'octo',
            totp: const TotpConfig(secret: 'GEZDGNBVGY3TQOJQ'),
          ),
        ],
        authenticators: const [
          ImportedAuthenticator(
              config: code, issuer: 'GitHub', account: 'octo'),
        ],
      );
      expect(o.totpCreated, 1);
      expect(o.entries.first.totp!.secret, 'GEZDGNBVGY3TQOJQ');
    });

    test('codes attach to logins added earlier in the same batch', () {
      final o = run(
        const [
          ImportedItem(title: 'Dropbox', url: 'dropbox.com', username: 'bob'),
        ],
        authenticators: const [
          ImportedAuthenticator(
              config: code, issuer: 'Dropbox', account: 'bob'),
        ],
      );
      expect(o.entries.single.totp, code);
      expect(o.totpAttached, 1);
    });
  });
}
