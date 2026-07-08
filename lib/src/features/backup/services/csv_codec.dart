import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// CSV import/export in the Chrome/Bitwarden column style
/// (`name,url,username,password,note,totp`). Header matching is liberal and
/// case-insensitive so exports from most managers import cleanly.
abstract final class CsvCodec {
  static const List<String> _nameHeaders = ['name', 'title', 'account'];
  static const List<String> _urlHeaders = [
    'url',
    'website',
    'login_uri',
    'uri',
    'web site',
  ];
  static const List<String> _usernameHeaders = [
    'username',
    'login_username',
    'user',
    'email',
    'login name',
  ];
  static const List<String> _passwordHeaders = ['password', 'login_password'];
  static const List<String> _noteHeaders = ['note', 'notes', 'comments'];
  static const List<String> _totpHeaders = ['totp', 'login_totp', 'otp'];

  /// Parses CSV [content] into draft rows. Throws [FormatException] when the
  /// header row has no recognizable columns.
  static List<CsvImportRow> parseImport(String content) {
    final rows = parseCsv(content);
    if (rows.isEmpty) return const [];

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final nameIdx = _indexOf(header, _nameHeaders);
    final urlIdx = _indexOf(header, _urlHeaders);
    final userIdx = _indexOf(header, _usernameHeaders);
    final passIdx = _indexOf(header, _passwordHeaders);
    final noteIdx = _indexOf(header, _noteHeaders);
    final totpIdx = _indexOf(header, _totpHeaders);

    if (nameIdx == null && userIdx == null && passIdx == null) {
      throw const FormatException(
        'No recognizable columns. Expected headers like '
        'name, url, username, password, note.',
      );
    }

    final result = <CsvImportRow>[];
    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      String cell(int? idx) =>
          idx == null || idx >= row.length ? '' : row[idx].trim();

      final name = cell(nameIdx);
      final username = cell(userIdx);
      final password = cell(passIdx);
      final url = cell(urlIdx);
      if (name.isEmpty && username.isEmpty && password.isEmpty) continue;

      result.add(
        CsvImportRow(
          name: name.isEmpty ? (url.isEmpty ? 'Imported entry' : url) : name,
          url: url,
          username: username,
          password: password,
          note: cell(noteIdx),
          totp: cell(totpIdx),
        ),
      );
    }
    return result;
  }

  /// Exports entries as plain CSV (name,url,username,password,note,totp).
  /// Two-factor secrets travel as otpauth URIs so other managers import
  /// them with their parameters intact.
  static String export(List<VaultEntry> entries) {
    final buffer = StringBuffer('name,url,username,password,note,totp\r\n');
    for (final e in entries) {
      final totp = e.totp == null
          ? ''
          : OtpauthParser.toUri(e.totp!, issuer: e.title, account: e.username);
      buffer.write(
        [e.title, e.url, e.username, e.password, e.notes, totp]
            .map(_escape)
            .join(','),
      );
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  static String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static int? _indexOf(List<String> header, List<String> candidates) {
    for (final candidate in candidates) {
      final idx = header.indexOf(candidate);
      if (idx != -1) return idx;
    }
    return null;
  }

  /// Minimal RFC-4180 CSV parser: quoted fields, escaped quotes, embedded
  /// commas/newlines, and both LF and CRLF line endings.
  static List<List<String>> parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    while (i < content.length) {
      final char = content[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
      } else if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        endField();
      } else if (char == '\r') {
        if (i + 1 < content.length && content[i + 1] == '\n') i++;
        endRow();
      } else if (char == '\n') {
        endRow();
      } else {
        field.write(char);
      }
      i++;
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}

/// One parsed CSV line ready to become a [VaultEntry].
final class CsvImportRow {
  const CsvImportRow({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.note,
    this.totp = '',
  });

  final String name;
  final String url;
  final String username;
  final String password;
  final String note;

  /// Raw two-factor cell: an otpauth URI or a bare base32 secret.
  final String totp;

  /// The parsed two-factor settings, or null when the cell is empty or
  /// unusable (a bad totp cell never blocks importing the password).
  TotpConfig? get totpConfig {
    if (totp.trim().isEmpty) return null;
    try {
      return OtpauthParser.parseUserInput(totp);
    } on FormatException {
      return null;
    }
  }

  VaultEntry toEntry({required String id, required DateTime now}) => VaultEntry(
        id: id,
        title: name,
        username: username,
        password: password,
        url: url,
        notes: note,
        totp: totpConfig,
        createdAt: now,
        updatedAt: now,
        passwordChangedAt: now,
      );
}
