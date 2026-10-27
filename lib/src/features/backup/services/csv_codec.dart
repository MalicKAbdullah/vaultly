import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// CSV export in the Chrome/Bitwarden column style
/// (`name,url,username,password,note,totp`) plus the RFC-4180 reader the
/// importers share.
abstract final class CsvCodec {
  /// Exports entries as plain CSV (name,url,username,password,note,totp).
  /// Two-factor secrets travel as otpauth URIs so other managers import
  /// them with their parameters intact. Passkeys are left out: a private
  /// key never leaves Vaultly unencrypted, and CSV has no column for one.
  static String export(List<VaultEntry> entries) {
    final buffer = StringBuffer('name,url,username,password,note,totp\r\n');
    for (final e in entries) {
      if (e.passkey != null) continue;
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

  /// Minimal RFC-4180 CSV parser: quoted fields, escaped quotes, embedded
  /// commas/newlines, and both LF and CRLF line endings. A quote that does
  /// not open a field is kept as a literal character.
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
      } else if (char == '"' && field.isEmpty) {
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
