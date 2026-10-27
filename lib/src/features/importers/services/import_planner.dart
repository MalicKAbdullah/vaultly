import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// What to do with an imported item that matches an existing one (same
/// site and username).
enum DuplicateAction {
  skip('Skip', 'Keep what is in Vaultly; ignore the imported copy.'),
  merge(
      'Merge',
      'Fill in missing details. A different password becomes '
          'current and the old one moves to history.'),
  keepBoth('Keep both', 'Add the imported copy as a separate item.');

  const DuplicateAction(this.label, this.description);

  final String label;
  final String description;
}

/// An imported item that matched something already in the vault (or earlier
/// in the same file).
final class ImportDuplicate {
  const ImportDuplicate({required this.incoming, required this.existing});

  final ImportedItem incoming;
  final VaultEntry existing;
}

/// The result of applying a batch: the new vault plus what happened.
final class ImportOutcome {
  const ImportOutcome({
    required this.entries,
    required this.added,
    required this.merged,
    required this.skipped,
    required this.duplicates,
    required this.totpAttached,
    required this.totpCreated,
    required this.totpAlreadyPresent,
  });

  final List<VaultEntry> entries;
  final int added;
  final int merged;
  final int skipped;
  final List<ImportDuplicate> duplicates;

  /// Authenticator codes attached to an existing login.
  final int totpAttached;

  /// Authenticator codes that became new items (no matching login).
  final int totpCreated;

  /// Authenticator codes the matching login already had.
  final int totpAlreadyPresent;

  int get changes => added + merged + totpAttached + totpCreated;
}

/// Pure import semantics: duplicate detection, the skip / merge / keep-both
/// choice, and attaching authenticator codes to matching logins.
abstract final class ImportPlanner {
  /// Applies [batch] to [current]. Items are processed in order against a
  /// working copy, so a duplicate inside the file itself is detected the
  /// same way as one already in the vault.
  static ImportOutcome apply({
    required List<VaultEntry> current,
    required ImportBatch batch,
    required DuplicateAction action,
    required DateTime now,
    required String Function() newId,
  }) {
    final working = List<VaultEntry>.of(current);
    // Duplicate key → index in [working] of the first entry with that key.
    final byKey = <String, int>{};
    void index(int i) {
      final e = working[i];
      final key = duplicateKey(e.url, e.title, e.username);
      if (key != null) byKey.putIfAbsent(key, () => i);
    }

    for (var i = 0; i < working.length; i++) {
      index(i);
    }
    final duplicates = <ImportDuplicate>[];
    var added = 0;
    var merged = 0;
    var skipped = 0;

    void add(ImportedItem item) {
      working.add(item.toEntry(id: newId(), now: now));
      index(working.length - 1);
      added++;
    }

    for (final item in batch.items) {
      final key = duplicateKey(item.url, item.title, item.username);
      final idx = key == null ? null : byKey[key];
      if (idx == null) {
        add(item);
        continue;
      }
      duplicates.add(ImportDuplicate(incoming: item, existing: working[idx]));
      switch (action) {
        case DuplicateAction.skip:
          skipped++;
        case DuplicateAction.keepBoth:
          add(item);
        case DuplicateAction.merge:
          final result = mergeInto(working[idx], item, now);
          if (result == working[idx]) {
            skipped++;
          } else {
            working[idx] = result;
            index(idx);
            merged++;
          }
      }
    }

    var attached = 0;
    var created = 0;
    var present = 0;
    for (final auth in batch.authenticators) {
      final candidates = [
        for (var i = 0; i < working.length; i++)
          if (_authenticatorMatches(working[i], auth)) i,
      ];
      if (candidates.any((i) => _sameSecret(working[i], auth))) {
        present++;
        continue;
      }
      final free = candidates.where((i) => working[i].totp == null);
      if (free.isNotEmpty) {
        final i = free.first;
        working[i] =
            working[i].copyWith(totp: () => auth.config, updatedAt: now);
        attached++;
        continue;
      }
      working.add(VaultEntry(
        id: newId(),
        title: auth.issuer.isNotEmpty
            ? auth.issuer
            : (auth.account.isNotEmpty ? auth.account : 'Authenticator code'),
        username: auth.account,
        totp: auth.config,
        createdAt: now,
        updatedAt: now,
        passwordChangedAt: now,
      ));
      created++;
    }

    return ImportOutcome(
      entries: working,
      added: added,
      merged: merged,
      skipped: skipped,
      duplicates: duplicates,
      totpAttached: attached,
      totpCreated: created,
      totpAlreadyPresent: present,
    );
  }

  /// Same site + same username. The site is the URL host without `www.`
  /// (or the lower-cased title when there is no URL). Items without any
  /// site or username are never duplicates.
  static String? duplicateKey(String url, String title, String username) {
    final site =
        siteOf(url).isNotEmpty ? siteOf(url) : title.trim().toLowerCase();
    final user = username.trim().toLowerCase();
    if (site.isEmpty && user.isEmpty) return null;
    return '$site\u0000$user';
  }

  /// Lower-cased host without a leading `www.`; also accepts bare domains.
  static String siteOf(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return '';
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final host = Uri.tryParse(withScheme)?.host.toLowerCase() ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// [existing] with the gaps filled from [incoming]. A different non-empty
  /// password becomes current and the old one moves to history.
  static VaultEntry mergeInto(
    VaultEntry existing,
    ImportedItem incoming,
    DateTime now,
  ) {
    var e = existing;
    if (incoming.password.isNotEmpty && incoming.password != e.password) {
      e = e.withNewPassword(incoming.password, now);
    }
    final notes = incoming.notes.trim();
    final mergedNotes = notes.isEmpty || e.notes.contains(notes)
        ? e.notes
        : [e.notes.trim(), notes].where((p) => p.isNotEmpty).join('\n\n');
    final next = e.copyWith(
      title: e.title.trim().isEmpty ? incoming.title : null,
      username: e.username.isEmpty ? incoming.username : null,
      url: e.url.isEmpty ? incoming.url : null,
      notes: mergedNotes,
      favorite: e.favorite || incoming.favorite,
      totp:
          e.totp == null && incoming.totp != null ? () => incoming.totp : null,
    );
    if (next == existing) return existing;
    return next.copyWith(updatedAt: now);
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The issuer names the login (title or site) and the account names its
  /// username. With no issuer, the account alone must match.
  static bool _authenticatorMatches(VaultEntry e, ImportedAuthenticator a) {
    if (e.category != EntryCategory.login) return false;
    final issuer = _norm(a.issuer);
    final account = a.account.trim().toLowerCase();
    final user = e.username.trim().toLowerCase();
    final accountOk = account.isEmpty || account == user;
    if (issuer.isEmpty) return account.isNotEmpty && accountOk;
    final title = _norm(e.title);
    final site = _norm(siteOf(e.url));
    final issuerOk = (title.isNotEmpty &&
            (title.contains(issuer) || issuer.contains(title))) ||
        (site.isNotEmpty && site.contains(issuer));
    return issuerOk && accountOk;
  }

  static bool _sameSecret(VaultEntry e, ImportedAuthenticator a) =>
      e.totp != null &&
      Base32.normalize(e.totp!.secret) == Base32.normalize(a.config.secret);
}
