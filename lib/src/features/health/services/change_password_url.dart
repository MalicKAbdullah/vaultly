/// Where a site's change-password page lives, by the well-known convention
/// (https://w3c.github.io/webappsec-change-password-url/). Vaultly makes no
/// request itself: the browser opens the URL, and a site without the page
/// answers however it likes.
abstract final class ChangePasswordUrl {
  /// The page for [entryUrl] (a bare host, a full URL with any scheme and
  /// path), always over https. Null when the entry has no website.
  static Uri? forEntry(String entryUrl) {
    final raw = entryUrl.trim();
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    final host = parsed?.host ?? '';
    if (host.isEmpty) return null;
    return Uri(
      scheme: 'https',
      host: host,
      port: parsed!.hasPort ? parsed.port : null,
      path: '/.well-known/change-password',
    );
  }
}
