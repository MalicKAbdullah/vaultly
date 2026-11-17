import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/parsers/import_text.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// 1Password's `.1pux` export: a zip whose `export.data` is a JSON tree of
/// accounts → vaults → items.
abstract final class OnePuxImporter {
  static const String _login = '001';
  static const String _creditCard = '002';
  static const String _secureNote = '003';
  static const String _identity = '004';
  static const String _password = '005';
  static const String _document = '006';

  /// Reads the archive [bytes]. The decompressed `export.data` buffer is
  /// zeroed before returning.
  static ImportBatch parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const ImportFormatException(
        'That file is not a readable 1Password export (.1pux).',
      );
    }
    final file = archive.findFile('export.data');
    if (file == null) {
      throw const ImportFormatException(
        'That .1pux file has no export data in it.',
      );
    }
    final data = file.readBytes() ?? Uint8List(0);
    try {
      return parseExportData(utf8.decode(data, allowMalformed: true));
    } finally {
      data.fillRange(0, data.length, 0);
      archive.clearSync();
    }
  }

  /// Parses the JSON inside `export.data`.
  static ImportBatch parseExportData(String json) {
    final Object? doc;
    try {
      doc = jsonDecode(json);
    } on FormatException {
      throw const ImportFormatException(
        'The 1Password export data is damaged.',
      );
    }
    if (doc is! Map<String, dynamic> || doc['accounts'] is! List) {
      throw const ImportFormatException(
        'The 1Password export data is damaged.',
      );
    }

    final items = <ImportedItem>[];
    final warnings = <String>[];
    for (final account in (doc['accounts'] as List).whereType<Map>()) {
      for (final vault
          in (account['vaults'] as List? ?? const []).whereType<Map>()) {
        for (final raw in (vault['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()) {
          final item = _item(raw, warnings);
          if (item != null) items.add(item);
        }
      }
    }
    return ImportBatch(
      source: ImportSource.onePassword1pux,
      items: items,
      warnings: warnings,
    );
  }

  static ImportedItem? _item(Map<String, dynamic> raw, List<String> warnings) {
    // Items in the trash were deleted by the user; leave them behind.
    if (raw['trashed'] == true || raw['state'] == 'deleted') return null;

    final overview = raw['overview'] as Map<String, dynamic>? ?? const {};
    final details = raw['details'] as Map<String, dynamic>? ?? const {};
    final category = raw['categoryUuid']?.toString() ?? '';
    final urls = <String>{
      if (_s(overview['url']).isNotEmpty) _s(overview['url']),
      for (final u in (overview['urls'] as List? ?? const []).whereType<Map>())
        if (_s(u['url']).isNotEmpty) _s(u['url']),
    }.toList();
    final url = urls.firstOrNull ?? '';
    final title = ImportText.title(_s(overview['title']), url);

    if (category == _document) {
      warnings.add('"$title" is a document; files are not imported.');
      return null;
    }

    var username = '';
    var password = '';
    for (final f
        in (details['loginFields'] as List? ?? const []).whereType<Map>()) {
      switch (f['designation']) {
        case 'username':
          username = _s(f['value']);
        case 'password':
          password = _s(f['value']);
      }
    }
    if (password.isEmpty) password = _s(details['password']);

    TotpConfig? totp;
    final lines = <String, String>{};
    final card = <String, String>{};
    final person = <String, String>{};
    for (final section
        in (details['sections'] as List? ?? const []).whereType<Map>()) {
      for (final field
          in (section['fields'] as List? ?? const []).whereType<Map>()) {
        final id = _s(field['id']).toLowerCase();
        final label = _s(field['title']).isNotEmpty
            ? _s(field['title'])
            : _s(field['id']);
        final value = field['value'];
        if (value is! Map || value.isEmpty) continue;
        final kind = value.keys.first.toString();
        final text = _fieldText(kind, value[kind]);
        if (text.isEmpty) continue;

        if (kind == 'totp' && totp == null) {
          totp = CsvImporters.parseTotpCell(text,
              itemName: title, warnings: warnings);
          continue;
        }
        if (category == _creditCard) {
          final slot = switch (id) {
            'ccnum' => 'number',
            'cardholder' => 'holder',
            'cvv' => 'cvc',
            'expiry' when kind == 'monthYear' => 'expiry',
            _ => null,
          };
          if (slot != null && !card.containsKey(slot)) {
            card[slot] = text;
            continue;
          }
        }
        if (category == _identity) {
          final slot = switch ((id, kind)) {
            ('firstname' || 'initial' || 'lastname', _) => id,
            (_, 'email') => 'email',
            (_, 'phone') => 'phone',
            (_, 'address') => 'address',
            _ => null,
          };
          if (slot != null && !person.containsKey(slot)) {
            person[slot] = text;
            if (slot == 'address') _address(value[kind], person);
            continue;
          }
        }
        if (kind == 'concealed' && password.isEmpty && id == 'password') {
          password = text;
          continue;
        }
        if (id == 'username' && username.isEmpty) {
          username = text;
          continue;
        }
        lines[_uniqueLabel(lines, label.isEmpty ? 'Field' : label)] = text;
      }
    }

    // An expiry Vaultly cannot read is kept as text, not lost.
    final expiry = CardDetails.parseExpiry(card['expiry'] ?? '');
    if (expiry == null) lines['Expires'] = card['expiry']!;
    final number = CardDetails.numberOf(card['number'] ?? '');
    if (number == null) lines['Card number'] = card['number']!;
    final tags = (overview['tags'] as List? ?? const []).join(', ');
    return ImportedItem(
      title: title,
      url: url,
      username: username,
      password: password,
      notes: ImportText.joinNotes([
        _s(details['notesPlain']),
        ImportText.fieldLines(lines),
        if (urls.length > 1) 'Other websites: ${urls.skip(1).join(', ')}',
        if (tags.isNotEmpty) 'Tags: $tags',
      ]),
      category: switch (category) {
        _login || _password => EntryCategory.login,
        _creditCard => EntryCategory.card,
        _identity => EntryCategory.identity,
        _secureNote => EntryCategory.note,
        // Bank accounts, licences, servers and the rest keep any login
        // they carry; everything else lands in the notes.
        _ => username.isNotEmpty || password.isNotEmpty
            ? EntryCategory.login
            : EntryCategory.note,
      },
      favorite: (raw['favIndex'] as num? ?? 0) > 0,
      totp: totp,
      card: category == _creditCard
          ? CardDetails(
              holder: card['holder'] ?? '',
              number: number ?? '',
              expMonth: expiry == null ? '' : expiry.month,
              expYear: expiry == null ? '' : expiry.year,
              cvc: card['cvc'] ?? '',
            )
          : null,
      identity: category == _identity
          ? IdentityDetails(
              fullName: [
                for (final part in const ['firstname', 'initial', 'lastname'])
                  if (person[part] != null) person[part]!,
              ].join(' '),
              email: person['email'] ?? '',
              phone: person['phone'] ?? '',
              address1: person['street'] ?? '',
              city: person['city'] ?? '',
              region: person['state'] ?? '',
              postalCode: person['zip'] ?? '',
              country: person['country'] ?? '',
            )
          : null,
    );
  }

  static String _s(Object? v) => v == null ? '' : v.toString().trim();

  /// Copies the parts of a structured `address` value into [into].
  static void _address(Object? v, Map<String, String> into) {
    if (v is! Map) return;
    for (final part in const ['street', 'city', 'state', 'zip', 'country']) {
      final text = _s(v[part]);
      if (text.isNotEmpty) into[part] = text;
    }
  }

  /// Renders one typed section value (`{"string": ...}`, `{"address":
  /// {...}}`, `{"monthYear": 202512}`, ...) as display text.
  static String _fieldText(String kind, Object? v) {
    switch (kind) {
      case 'address':
        if (v is! Map) return '';
        return [v['street'], v['city'], v['state'], v['zip'], v['country']]
            .map(_s)
            .where((p) => p.isNotEmpty)
            .join(', ');
      case 'email':
        return v is Map ? _s(v['email_address']) : _s(v);
      case 'monthYear':
        final n = v is num ? v.toInt() : int.tryParse(_s(v));
        if (n == null || n <= 0) return '';
        return '${(n % 100).toString().padLeft(2, '0')}/${n ~/ 100}';
      case 'date':
        final n = v is num ? v.toInt() : int.tryParse(_s(v));
        if (n == null || n <= 0) return '';
        final d = DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      case 'sshKey':
        return v is Map ? _s(v['privateKey']) : _s(v);
      default:
        return v is Map || v is List ? '' : _s(v);
    }
  }

  static String _uniqueLabel(Map<String, String> lines, String label) {
    if (!lines.containsKey(label)) return label;
    var n = 2;
    while (lines.containsKey('$label ($n)')) {
      n++;
    }
    return '$label ($n)';
  }
}
