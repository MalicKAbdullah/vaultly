import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// What to do with a login the user just submitted elsewhere.
sealed class CaptureDecision {
  const CaptureDecision();
}

/// The vault already holds exactly this login.
final class AlreadySaved extends CaptureDecision {
  const AlreadySaved(this.entry);
  final VaultEntry entry;
}

/// The vault holds this account with another password.
final class UpdatePassword extends CaptureDecision {
  const UpdatePassword(this.entry);
  final VaultEntry entry;
}

/// A login the vault does not have yet.
final class SaveNew extends CaptureDecision {
  const SaveNew({required this.title, required this.url});
  final String title;
  final String url;
}

/// Decides between saving, updating and doing nothing. Which entries belong
/// to the page is the matcher's call; this adds the account (username) and
/// the password comparison.
abstract final class LoginCapture {
  /// [fixEntryId] names the entry the user set out to repair (the "Change
  /// password" button), so the new password goes to exactly that entry even
  /// when other accounts share the site.
  static CaptureDecision decide(
    List<VaultEntry> entries,
    CapturedLogin login, {
    String? fixEntryId,
  }) {
    if (fixEntryId != null) {
      for (final e in entries) {
        if (e.id == fixEntryId) return _compare(e, login.password);
      }
    }
    final request =
        AutofillFillRequest(domain: login.host, package: login.package);
    final candidates = [
      for (final e in AutofillMatcher.rank(entries, request))
        if (e.category == EntryCategory.login &&
            e.passkey == null &&
            AutofillMatcher.score(e, request) >= _minScore(login))
          e,
    ];
    final username = login.username.trim().toLowerCase();
    for (final e in candidates) {
      if (e.username.trim().toLowerCase() == username) {
        return _compare(e, login.password);
      }
    }
    // A page that never showed us the account (a password-only step) can
    // only belong to the one entry there is.
    if (username.isEmpty && candidates.length == 1) {
      return _compare(candidates.single, login.password);
    }
    return SaveNew(title: _title(login), url: login.host ?? '');
  }

  /// A web page needs the same site (or a parent or child domain); an app is
  /// matched by the identity in its package.
  static int _minScore(CapturedLogin login) => login.host != null ? 80 : 60;

  static CaptureDecision _compare(VaultEntry entry, String password) =>
      entry.password == password ? AlreadySaved(entry) : UpdatePassword(entry);

  static String _title(CapturedLogin login) {
    final host = login.host;
    if (host != null) return host;
    final package = login.package ?? '';
    const generic = {
      'com',
      'org',
      'net',
      'io',
      'co',
      'app',
      'apps',
      'android',
      'mobile',
      'client',
      'beta',
      'free',
      'main',
      'www',
    };
    final parts =
        package.split('.').where((p) => p.length >= 3 && !generic.contains(p));
    final name = parts.isEmpty ? package : parts.last;
    return name.isEmpty ? 'Login' : name[0].toUpperCase() + name.substring(1);
  }
}
