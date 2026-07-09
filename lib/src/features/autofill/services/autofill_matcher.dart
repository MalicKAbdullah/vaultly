import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Ranks vault entries against an autofill request. All the "which entry
/// belongs to github.com?" smarts live here in Dart, where they are
/// unit-tested — the Kotlin side only extracts the domain/package.
abstract final class AutofillMatcher {
  /// Package prefixes/segments that carry no identity ("com" in
  /// com.github.android says nothing about GitHub).
  static const Set<String> _genericSegments = {
    'com',
    'org',
    'net',
    'io',
    'co',
    'de',
    'uk',
    'eu',
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

  /// Packages of well-known browsers. When a fill request comes from one of
  /// these the package identifies the *browser*, not the site being filled —
  /// so package-name matching would only add noise. The web domain the
  /// browser reports is the real signal, so we lean on that alone.
  static const Set<String> _browserPackages = {
    'com.android.chrome',
    'com.chrome.beta',
    'com.chrome.dev',
    'com.chrome.canary',
    'com.android.browser',
    'com.google.android.apps.chrome',
    'org.mozilla.firefox',
    'org.mozilla.firefox_beta',
    'org.mozilla.focus',
    'org.mozilla.fenix',
    'com.microsoft.emmx',
    'com.opera.browser',
    'com.opera.mini.native',
    'com.opera.gx',
    'com.brave.browser',
    'com.duckduckgo.mobile.android',
    'com.sec.android.app.sbrowser',
    'com.vivaldi.browser',
    'com.kiwibrowser.browser',
    'com.microsoft.bing',
    'com.ecosia.android',
  };

  /// Whether [package] is a browser (so only the web domain should match).
  static bool _isBrowser(String package) =>
      _browserPackages.contains(package) || package.contains('browser');

  /// How well [entry] matches [request]. 0 means "no signal at all".
  static int score(VaultEntry entry, AutofillFillRequest request) {
    final domain = _normalizeHost(request.domain ?? '');
    final entryHost = _normalizeHost(entry.url);
    final title = entry.title.toLowerCase();

    var best = 0;
    if (domain.isNotEmpty) {
      if (entryHost.isNotEmpty) {
        if (entryHost == domain) {
          best = _max(best, 100);
        } else if (domain.endsWith('.$entryHost') ||
            entryHost.endsWith('.$domain')) {
          // accounts.google.com vs google.com, either direction.
          best = _max(best, 80);
        }
      }
      final base = _baseLabel(domain);
      if (base.isNotEmpty && title.contains(base)) best = _max(best, 40);
    }

    final package = (request.package ?? '').toLowerCase();
    // Browser requests are matched purely on the web domain above; the
    // browser's own package must never match a vault entry.
    if (package.isNotEmpty && !_isBrowser(package)) {
      for (final segment in package.split('.')) {
        if (segment.length < 3 || _genericSegments.contains(segment)) {
          continue;
        }
        if (entryHost.contains(segment)) best = _max(best, 60);
        if (title.contains(segment)) best = _max(best, 40);
      }
    }
    return best;
  }

  /// Entries that match [request], best first (ties by title). Empty when
  /// nothing matches — callers then fall back to the full list.
  static List<VaultEntry> rank(
    List<VaultEntry> entries,
    AutofillFillRequest request,
  ) {
    final scored = [
      for (final entry in entries)
        if (score(entry, request) > 0)
          (entry: entry, score: score(entry, request)),
    ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.entry.title
            .toLowerCase()
            .compareTo(b.entry.title.toLowerCase());
      });
    return [for (final item in scored) item.entry];
  }

  /// Lowercased host without scheme, path, port, or a leading `www.`.
  static String _normalizeHost(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (!value.contains('://')) value = 'https://$value';
    String host;
    try {
      host = Uri.parse(value).host;
    } catch (_) {
      return '';
    }
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// The identifying label of a host: `accounts.google.com` → `google`.
  static String _baseLabel(String host) {
    final parts = host.split('.');
    if (parts.length < 2) return host;
    return parts[parts.length - 2];
  }

  static int _max(int a, int b) => a > b ? a : b;
}
