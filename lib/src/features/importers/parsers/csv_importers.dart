import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/import_text.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// A parsed CSV file: the header row and the data rows, with the UTF-8 byte
/// order mark stripped and fully blank rows dropped.
final class CsvTable {
  const CsvTable({required this.header, required this.rows});

  factory CsvTable.parse(String content) {
    final text = content.startsWith('﻿') ? content.substring(1) : content;
    final all = CsvCodec.parseCsv(text);
    if (all.isEmpty) {
      throw const ImportFormatException('That file is empty.');
    }
    return CsvTable(
      header: all.first.map((h) => h.trim()).toList(),
      rows: [
        for (final row in all.skip(1))
          if (row.any((cell) => cell.trim().isNotEmpty)) row,
      ],
    );
  }

  final List<String> header;
  final List<List<String>> rows;

  /// Lower-cased header names, for format detection and column lookup.
  List<String> get keys => header.map((h) => h.toLowerCase()).toList();

  int? indexOf(String key) {
    final i = keys.indexOf(key);
    return i == -1 ? null : i;
  }
}

/// The vault fields a CSV column can feed.
enum ImportField {
  title('Name'),
  url('Website'),
  username('Username'),
  password('Password'),
  notes('Notes'),
  totp('Two-factor secret');

  const ImportField(this.label);

  final String label;
}

/// Which column (by index) feeds each vault field. Unmapped fields stay
/// empty.
final class CsvColumnMapping {
  const CsvColumnMapping(this.columns);

  final Map<ImportField, int> columns;

  CsvColumnMapping withColumn(ImportField field, int? column) =>
      CsvColumnMapping({
        for (final e in columns.entries)
          if (e.key != field) e.key: e.value,
        if (column != null) field: column,
      });

  /// A mapping can import only when it can name or fill something.
  bool get isUsable =>
      columns.containsKey(ImportField.title) ||
      columns.containsKey(ImportField.username) ||
      columns.containsKey(ImportField.password);
}

/// Imports from any CSV: Chrome, Bitwarden, 1Password and arbitrary files
/// through a user-confirmed [CsvColumnMapping].
abstract final class CsvImporters {
  static const Map<ImportField, List<String>> _aliases = {
    ImportField.title: ['name', 'title', 'account', 'item', 'site name'],
    ImportField.url: [
      'url',
      'website',
      'login_uri',
      'uri',
      'web site',
      'site',
      'address',
      'hostname',
    ],
    ImportField.username: [
      'username',
      'login_username',
      'user',
      'user name',
      'login',
      'email',
      'e-mail',
      'login name',
    ],
    ImportField.password: ['password', 'login_password', 'pass', 'pwd'],
    ImportField.notes: ['note', 'notes', 'comments', 'comment', 'extra'],
    ImportField.totp: [
      'totp',
      'login_totp',
      'otp',
      'otpauth',
      'one-time password'
    ],
  };

  /// Best-guess mapping for [header], matched case-insensitively against
  /// common column names. The user confirms or corrects it.
  static CsvColumnMapping guessMapping(List<String> header) {
    final keys = header.map((h) => h.trim().toLowerCase()).toList();
    final used = <int>{};
    final columns = <ImportField, int>{};
    for (final field in ImportField.values) {
      for (final alias in _aliases[field]!) {
        final idx = keys.indexOf(alias);
        if (idx != -1 && !used.contains(idx)) {
          columns[field] = idx;
          used.add(idx);
          break;
        }
      }
    }
    return CsvColumnMapping(columns);
  }

  /// Imports [table] through [mapping].
  static ImportBatch generic(
    CsvTable table,
    CsvColumnMapping mapping, {
    ImportSource source = ImportSource.genericCsv,
  }) {
    if (!mapping.isUsable) {
      throw const ImportFormatException(
        'Pick at least a name, username or password column.',
      );
    }
    final items = <ImportedItem>[];
    final warnings = <String>[];
    for (final row in table.rows) {
      String cell(ImportField f) => _cell(row, mapping.columns[f]);
      final item = _loginItem(
        title: cell(ImportField.title),
        url: cell(ImportField.url),
        username: cell(ImportField.username),
        password: cell(ImportField.password),
        notes: cell(ImportField.notes),
        totpCell: cell(ImportField.totp),
        warnings: warnings,
      );
      if (item != null) items.add(item);
    }
    return ImportBatch(source: source, items: items, warnings: warnings);
  }

  /// Chrome / Google Password Manager: `name,url,username,password,note`.
  static ImportBatch chrome(CsvTable table) =>
      generic(table, guessMapping(table.header), source: ImportSource.chrome);

  /// Bitwarden CSV: `folder,favorite,type,name,notes,fields,reprompt,
  /// login_uri,login_username,login_password,login_totp`.
  static ImportBatch bitwarden(CsvTable table) {
    int? col(String k) => table.indexOf(k);
    final items = <ImportedItem>[];
    final warnings = <String>[];
    for (final row in table.rows) {
      String cell(String k) => _cell(row, col(k));
      final type = cell('type').toLowerCase();
      final notes = ImportText.joinNotes([cell('notes'), cell('fields')]);
      final favorite = cell('favorite') == '1';
      if (type == 'note') {
        items.add(ImportedItem(
          title: ImportText.title(cell('name'), ''),
          notes: notes,
          category: EntryCategory.note,
          favorite: favorite,
        ));
        continue;
      }
      // Several URIs arrive comma-joined in one cell; the first is primary.
      final uris = cell('login_uri')
          .split(',')
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();
      final item = _loginItem(
        title: cell('name'),
        url: uris.isEmpty ? '' : uris.first,
        username: cell('login_username'),
        password: cell('login_password'),
        notes: ImportText.joinNotes([
          notes,
          if (uris.length > 1) 'Other websites: ${uris.skip(1).join(', ')}',
        ]),
        totpCell: cell('login_totp'),
        favorite: favorite,
        warnings: warnings,
      );
      if (item != null) items.add(item);
    }
    return ImportBatch(
      source: ImportSource.bitwardenCsv,
      items: items,
      warnings: warnings,
    );
  }

  /// 1Password CSV: `Title,Url,Username,Password,OTPAuth,Favorite,Archived,
  /// Tags,Notes`.
  static ImportBatch onePassword(CsvTable table) {
    int? col(String k) => table.indexOf(k);
    final items = <ImportedItem>[];
    final warnings = <String>[];
    for (final row in table.rows) {
      String cell(String k) => _cell(row, col(k));
      final tags = cell('tags');
      final item = _loginItem(
        title: cell('title'),
        url: cell('url').isNotEmpty ? cell('url') : cell('website'),
        username: cell('username'),
        password: cell('password'),
        notes: ImportText.joinNotes([
          cell('notes'),
          if (tags.isNotEmpty) 'Tags: $tags',
        ]),
        totpCell: cell('otpauth'),
        favorite: cell('favorite').toLowerCase() == 'true',
        warnings: warnings,
      );
      if (item != null) items.add(item);
    }
    return ImportBatch(
      source: ImportSource.onePasswordCsv,
      items: items,
      warnings: warnings,
    );
  }

  /// A login item from raw cells, or null for a row with nothing to keep.
  static ImportedItem? _loginItem({
    required String title,
    required String url,
    required String username,
    required String password,
    required String notes,
    required String totpCell,
    required List<String> warnings,
    bool favorite = false,
  }) {
    if (title.isEmpty &&
        username.isEmpty &&
        password.isEmpty &&
        url.isEmpty &&
        notes.isEmpty) {
      return null;
    }
    final name = ImportText.title(title, url);
    return ImportedItem(
      title: name,
      url: url,
      username: username,
      password: password,
      notes: notes,
      favorite: favorite,
      totp: parseTotpCell(totpCell, itemName: name, warnings: warnings),
    );
  }

  /// Parses an otpauth URI or bare base32 secret. A bad value never blocks
  /// the login itself; it is reported in [warnings] instead.
  static TotpConfig? parseTotpCell(
    String raw, {
    required String itemName,
    required List<String> warnings,
  }) {
    if (raw.trim().isEmpty) return null;
    try {
      return OtpauthParser.parseUserInput(raw);
    } on FormatException {
      warnings.add('"$itemName": the two-factor secret was not recognised, '
          'so it was left out.');
      return null;
    }
  }

  static String _cell(List<String> row, int? idx) =>
      idx == null || idx >= row.length ? '' : row[idx].trim();
}
