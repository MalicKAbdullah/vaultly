/// Text helpers shared by every importer.
abstract final class ImportText {
  /// The item's title, else the website host, else a placeholder.
  static String title(String title, String url) {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final host = Uri.tryParse(url.trim())?.host ?? '';
    if (host.isNotEmpty) return host;
    return url.trim().isNotEmpty ? url.trim() : 'Imported item';
  }

  /// Joins the non-blank [parts] into one notes field.
  static String joinNotes(Iterable<String> parts) =>
      parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join('\n\n');

  /// `Label: value` lines for the non-blank values, in order.
  static String fieldLines(Map<String, String> fields) => [
        for (final e in fields.entries)
          if (e.value.trim().isNotEmpty) '${e.key}: ${e.value.trim()}',
      ].join('\n');
}
