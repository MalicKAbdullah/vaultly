import 'dart:convert';

import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/parsers/import_text.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Bitwarden's unencrypted JSON export (`bitwarden_export_*.json`).
abstract final class BitwardenJsonImporter {
  static const int _login = 1;
  static const int _secureNote = 2;
  static const int _card = 3;
  static const int _identity = 4;
  static const int _sshKey = 5;

  static ImportBatch parse(String content) {
    final Object? doc;
    try {
      doc = jsonDecode(content);
    } on FormatException {
      throw const ImportFormatException('That file is not valid JSON.');
    }
    if (doc is! Map<String, dynamic> || doc['items'] is! List) {
      if (doc is Map<String, dynamic> && doc['encrypted'] == true) {
        throw _encrypted;
      }
      throw const ImportFormatException(
        'That JSON file is not a Bitwarden export.',
      );
    }
    if (doc['encrypted'] == true) throw _encrypted;

    final folders = <String, String>{
      for (final f in (doc['folders'] as List? ?? const []).whereType<Map>())
        if (f['id'] is String && f['name'] is String)
          f['id'] as String: f['name'] as String,
    };

    final items = <ImportedItem>[];
    final warnings = <String>[];
    for (final raw
        in (doc['items'] as List).whereType<Map<String, dynamic>>()) {
      final item = _item(raw, folders, warnings);
      if (item != null) items.add(item);
    }
    return ImportBatch(
      source: ImportSource.bitwardenJson,
      items: items,
      warnings: warnings,
    );
  }

  static const _encrypted = ImportFormatException(
    'This Bitwarden export is encrypted. Export again and choose the '
    '".json" format (not "encrypted"), then import that file.',
  );

  static ImportedItem? _item(
    Map<String, dynamic> raw,
    Map<String, String> folders,
    List<String> warnings,
  ) {
    String str(Map<dynamic, dynamic>? m, String k) {
      final v = m?[k];
      return v == null ? '' : v.toString().trim();
    }

    final name = str(raw, 'name');
    final favorite = raw['favorite'] == true;
    final folder = folders[raw['folderId']] ?? '';
    final customFields = ImportText.fieldLines({
      for (final f in (raw['fields'] as List? ?? const []).whereType<Map>())
        str(f, 'name').isEmpty ? 'Field' : str(f, 'name'): str(f, 'value'),
    });
    final extras = [
      str(raw, 'notes'),
      customFields,
      if (folder.isNotEmpty) 'Folder: $folder',
    ];

    switch (raw['type']) {
      case _login:
        final login = raw['login'] as Map<String, dynamic>? ?? const {};
        final uris = [
          for (final u in (login['uris'] as List? ?? const []).whereType<Map>())
            if (str(u, 'uri').isNotEmpty) str(u, 'uri'),
        ];
        final title = ImportText.title(name, uris.firstOrNull ?? '');
        return ImportedItem(
          title: title,
          url: uris.firstOrNull ?? '',
          username: str(login, 'username'),
          password: str(login, 'password'),
          notes: ImportText.joinNotes([
            ...extras,
            if (uris.length > 1) 'Other websites: ${uris.skip(1).join(', ')}',
          ]),
          favorite: favorite,
          totp: CsvImporters.parseTotpCell(
            str(login, 'totp'),
            itemName: title,
            warnings: warnings,
          ),
        );
      case _secureNote:
        return ImportedItem(
          title: ImportText.title(name, ''),
          notes: ImportText.joinNotes(extras),
          category: EntryCategory.note,
          favorite: favorite,
        );
      case _card:
        final card = raw['card'] as Map<String, dynamic>? ?? const {};
        final month = str(card, 'expMonth');
        final year = str(card, 'expYear');
        return ImportedItem(
          title: ImportText.title(name, ''),
          username: str(card, 'cardholderName'),
          password: str(card, 'number'),
          notes: ImportText.joinNotes([
            ImportText.fieldLines({
              'Brand': str(card, 'brand'),
              'Expires': [month, year].where((p) => p.isNotEmpty).join('/'),
              'Security code': str(card, 'code'),
            }),
            ...extras,
          ]),
          category: EntryCategory.card,
          favorite: favorite,
        );
      case _identity:
        final id = raw['identity'] as Map<String, dynamic>? ?? const {};
        final fullName = [
          str(id, 'title'),
          str(id, 'firstName'),
          str(id, 'middleName'),
          str(id, 'lastName'),
        ].where((p) => p.isNotEmpty).join(' ');
        final address = [
          str(id, 'address1'),
          str(id, 'address2'),
          str(id, 'address3'),
          [str(id, 'postalCode'), str(id, 'city')]
              .where((p) => p.isNotEmpty)
              .join(' '),
          str(id, 'state'),
          str(id, 'country'),
        ].where((p) => p.isNotEmpty).join(', ');
        return ImportedItem(
          title: ImportText.title(name, ''),
          username: str(id, 'email').isNotEmpty
              ? str(id, 'email')
              : str(id, 'username'),
          notes: ImportText.joinNotes([
            ImportText.fieldLines({
              'Name': fullName,
              'Company': str(id, 'company'),
              'Phone': str(id, 'phone'),
              'Address': address,
              'Username': str(id, 'username'),
              'National ID': str(id, 'ssn'),
              'Passport': str(id, 'passportNumber'),
              'Licence': str(id, 'licenseNumber'),
            }),
            ...extras,
          ]),
          category: EntryCategory.identity,
          favorite: favorite,
        );
      case _sshKey:
        final key = raw['sshKey'] as Map<String, dynamic>? ?? const {};
        return ImportedItem(
          title: ImportText.title(name, ''),
          password: str(key, 'privateKey'),
          notes: ImportText.joinNotes([
            ImportText.fieldLines({
              'Public key': str(key, 'publicKey'),
              'Fingerprint': str(key, 'keyFingerprint'),
            }),
            ...extras,
          ]),
          category: EntryCategory.note,
          favorite: favorite,
        );
      default:
        warnings.add('"${name.isEmpty ? 'Unnamed item' : name}" has a type '
            'Vaultly does not know, so it was left out.');
        return null;
    }
  }
}
