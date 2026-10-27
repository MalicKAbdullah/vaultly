import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/parsers/import_detector.dart';
import 'package:vaultkey/src/features/importers/parsers/onepux_importer.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/import/$name').readAsBytesSync();

ImportReadResult readFixture(String name) =>
    ImportDetector.read(fileName: name, bytes: fixture(name));

ImportBatch batchOf(String name) => (readFixture(name) as ImportReady).batch;

ImportedItem named(ImportBatch b, String title) =>
    b.items.singleWhere((i) => i.title == title);

void main() {
  group('Chrome / Google Password Manager CSV', () {
    late ImportBatch batch;
    setUp(() => batch = batchOf('chrome.csv'));

    test('is detected as Chrome', () {
      expect(batch.source, ImportSource.chrome);
    });

    test('reads quoted commas and escaped quotes', () {
      final gh = named(batch, 'github.com');
      expect(gh.url, 'https://github.com/login');
      expect(gh.username, 'octo@example.com');
      expect(gh.password, 'pa,ss"word');
      expect(gh.notes, '');
    });

    test('keeps a multi-line note intact', () {
      expect(named(batch, 'accounts.google.com').notes, 'line one\nline two');
    });

    test('keeps unicode in every field', () {
      final item = named(batch, 'bücher.de');
      expect(item.username, 'jürgen@beispiel.de');
      expect(item.password, 'pässwörd🔑');
      expect(item.notes, 'Ünïcødé note — 中文');
    });

    test('names an untitled row after its website host', () {
      expect(named(batch, 'example.org').password, 'pw-only');
    });

    test('a row missing trailing fields imports with them empty', () {
      final item = named(batch, 'Short row');
      expect(item.url, 'https://short.example');
      expect(item.username, '');
      expect(item.password, '');
    });

    test('skips blank lines', () {
      expect(batch.items, hasLength(5));
    });
  });

  group('Bitwarden JSON', () {
    late ImportBatch batch;
    setUp(() => batch = batchOf('bitwarden.json'));

    test('login keeps URIs, custom fields, folder and TOTP', () {
      final item = named(batch, 'Example');
      expect(batch.source, ImportSource.bitwardenJson);
      expect(item.url, 'https://example.com/login');
      expect(item.username, 'alice@example.com');
      expect(item.password, 'Tr0ub4dor&3');
      expect(item.favorite, isTrue);
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(item.totp!.algorithm, TotpAlgorithm.sha256);
      expect(item.notes, contains('main account'));
      expect(item.notes, contains('PIN: 4321'));
      expect(item.notes, contains('Folder: Personal'));
      expect(item.notes, contains('Other websites: https://m.example.com'));
    });

    test('secure note becomes a note', () {
      final item = named(batch, 'Recovery codes');
      expect(item.category, EntryCategory.note);
      expect(item.notes, 'a1b2 c3d4');
    });

    test('card puts holder and number in the login fields', () {
      final item = named(batch, 'Visa');
      expect(item.category, EntryCategory.card);
      expect(item.username, 'Alice Ä. Example');
      expect(item.password, '4111111111111111');
      expect(item.notes, contains('Expires: 7/2030'));
      expect(item.notes, contains('Security code: 123'));
    });

    test('identity keeps the details in notes', () {
      final item = named(batch, 'Me');
      expect(item.category, EntryCategory.identity);
      expect(item.username, 'alice@example.com');
      expect(item.notes, contains('Name: Ms Alice Example'));
      expect(item.notes, contains('Address: 1 Main St, N1 1AA London, GB'));
      expect(item.notes, contains('Passport: X123'));
    });

    test('null password imports as empty', () {
      expect(named(batch, 'No password').password, '');
    });

    test('unknown item types are reported, not imported', () {
      expect(batch.items.map((i) => i.title), isNot(contains('Future thing')));
      expect(batch.warnings.single, contains('Future thing'));
    });

    test('encrypted exports are refused with a hint', () {
      expect(
        () => readFixture('bitwarden_encrypted.json'),
        throwsA(isA<ImportFormatException>().having(
          (e) => e.message,
          'message',
          contains('encrypted'),
        )),
      );
    });

    test('JSON that is not a Bitwarden export is refused', () {
      expect(
        () => ImportDetector.read(
          fileName: 'x.json',
          bytes: Uint8List.fromList('{"foo": 1}'.codeUnits),
        ),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('Bitwarden CSV', () {
    late ImportBatch batch;
    setUp(() => batch = batchOf('bitwarden.csv'));

    test('is detected despite the byte order mark', () {
      expect(batch.source, ImportSource.bitwardenCsv);
      expect(batch.items, hasLength(4));
    });

    test('login with several URIs, fields and an 8-digit TOTP', () {
      final item = named(batch, 'GitLab');
      expect(item.url, 'https://gitlab.example.com');
      expect(item.password, 's3cr"et');
      expect(item.favorite, isTrue);
      expect(item.totp!.digits, 8);
      expect(item.notes, contains('Self-hosted, on-prem'));
      expect(item.notes, contains('Recovery: 1234'));
      expect(
        item.notes,
        contains('Other websites: https://gitlab.example.com/admin'),
      );
    });

    test('note rows become notes with their multi-line text', () {
      final item = named(batch, 'Wi-Fi codes');
      expect(item.category, EntryCategory.note);
      expect(item.notes, 'Home: hunter2\nOffice: correct horse');
    });

    test('a bad TOTP is reported but the login still imports', () {
      final item = named(batch, 'Broken 2FA');
      expect(item.password, 'pw');
      expect(item.totp, isNull);
      expect(batch.warnings.single, contains('Broken 2FA'));
    });

    test('a bare base32 secret is accepted', () {
      expect(named(batch, 'Bare secret').totp!.secret, 'JBSWY3DPEHPK3PXP');
    });
  });

  group('1Password .1pux', () {
    late ImportBatch batch;
    setUp(() => batch = batchOf('1password.1pux'));

    test('login with username, password, TOTP, extra fields and URLs', () {
      final item = named(batch, 'Mail');
      expect(batch.source, ImportSource.onePassword1pux);
      expect(item.url, 'https://mail.example.com');
      expect(item.username, 'bob@example.com');
      expect(item.password, r'Sup3r$ecret');
      expect(item.favorite, isTrue);
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(item.notes, contains('Primary email'));
      expect(item.notes, contains('recovery email: bob.backup@example.com'));
      expect(
        item.notes,
        contains('Other websites: https://webmail.example.com'),
      );
      expect(item.notes, contains('Tags: personal'));
    });

    test('credit card maps holder and number; expiry goes to notes', () {
      final item = named(batch, 'Mastercard');
      expect(item.category, EntryCategory.card);
      expect(item.username, 'Bob Example');
      expect(item.password, '5555444433331111');
      expect(item.notes, contains('verification number: 987'));
      expect(item.notes, contains('expiry date: 11/2030'));
    });

    test('secure note keeps unicode', () {
      final item = named(batch, 'Notes ✎');
      expect(item.category, EntryCategory.note);
      expect(item.notes, 'Gate code 4711 — ключ');
    });

    test('password item and server item', () {
      expect(named(batch, 'Router admin').password, 'standalone-pw');
      final server = named(batch, 'Server');
      expect(server.username, 'root');
      expect(server.password, 'toor');
      expect(server.category, EntryCategory.login);
    });

    test('trashed items are left out; documents are reported', () {
      final titles = batch.items.map((i) => i.title);
      expect(titles, isNot(contains('Deleted thing')));
      expect(titles, isNot(contains('Passport scan')));
      expect(batch.warnings.single, contains('Passport scan'));
    });

    test('is detected by its zip header even without the extension', () {
      final b = (ImportDetector.read(
        fileName: 'export',
        bytes: fixture('1password.1pux'),
      ) as ImportReady)
          .batch;
      expect(b.source, ImportSource.onePassword1pux);
    });

    test('a .1pux without export.data is refused', () {
      expect(
        () => readFixture('1password_missing_data.1pux'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('a damaged archive is refused', () {
      expect(
        () => OnePuxImporter.parse(Uint8List.fromList([0x50, 0x4B, 3, 4, 1])),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('1Password CSV', () {
    late ImportBatch batch;
    setUp(() => batch = batchOf('1password.csv'));

    test('reads OTPAuth, favourite, tags and multi-line notes', () {
      final item = named(batch, 'Dropbox');
      expect(batch.source, ImportSource.onePasswordCsv);
      expect(item.password, 'dr0p,box');
      expect(item.favorite, isTrue);
      expect(item.totp!.secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(item.notes, 'multi\nline ✓\n\nTags: work,cloud');
    });

    test('archived items still import', () {
      expect(named(batch, 'Old forum').username, 'bobby');
    });
  });

  group('Generic CSV with column mapping', () {
    late CsvTable table;
    late CsvColumnMapping guess;
    setUp(() {
      final r = readFixture('generic.csv') as ImportNeedsMapping;
      table = r.table;
      guess = r.suggested;
    });

    test('unknown headers ask for a mapping, with a best guess', () {
      expect(table.header.first, 'Label');
      expect(guess.columns, {ImportField.username: 2, ImportField.notes: 4});
    });

    test('the user mapping drives the import', () {
      final mapping = const CsvColumnMapping({})
          .withColumn(ImportField.title, 0)
          .withColumn(ImportField.url, 1)
          .withColumn(ImportField.username, 2)
          .withColumn(ImportField.password, 3)
          .withColumn(ImportField.notes, 4);
      final batch = CsvImporters.generic(table, mapping);
      expect(batch.items, hasLength(3));
      final forum = named(batch, 'Forum');
      expect(forum.url, 'forum.example');
      expect(forum.password, 'p@ss, word');
      expect(forum.notes, 'says ""hi""');
      final uni = named(batch, 'Ünïcode Site');
      expect(uni.username, 'user✓');
      expect(uni.password, 'pässwörd');
      final missing = named(batch, 'Missing fields');
      expect(missing.username, '');
    });

    test('unmapping a column drops it', () {
      final mapping = const CsvColumnMapping({ImportField.title: 0})
          .withColumn(ImportField.password, 3)
          .withColumn(ImportField.password, null);
      expect(mapping.columns.keys, [ImportField.title]);
    });

    test('a mapping with no name, username or password is refused', () {
      expect(
        () => CsvImporters.generic(
          table,
          const CsvColumnMapping({ImportField.notes: 4}),
        ),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('guessMapping recognises common headers in any case', () {
      final m = CsvImporters.guessMapping(
        ['Title', 'Website', 'E-mail', 'Pass', 'Comments', 'OTP'],
      );
      expect(m.columns, {
        ImportField.title: 0,
        ImportField.url: 1,
        ImportField.username: 2,
        ImportField.password: 3,
        ImportField.notes: 4,
        ImportField.totp: 5,
      });
    });
  });

  group('ImportDetector edge cases', () {
    test('an empty file is refused', () {
      expect(
        () => ImportDetector.read(fileName: 'a.csv', bytes: Uint8List(0)),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('binary that is not a zip is refused', () {
      expect(
        () => ImportDetector.read(
          fileName: 'a.bin',
          bytes: Uint8List.fromList([0xff, 0xfe, 0x00, 0xd8]),
        ),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('a header-only CSV yields an empty batch', () {
      final r = ImportDetector.readCsv('name,url,username,password\n');
      expect((r as ImportReady).batch.isEmpty, isTrue);
    });
  });
}
