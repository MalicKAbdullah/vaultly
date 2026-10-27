import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/import_detector.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';

import 'fakes/fakes.dart';

void main() {
  ImportBatch reimport(String csv) =>
      (ImportDetector.readCsv(csv) as ImportReady).batch;

  group('CsvCodec.parseCsv', () {
    test('quoted fields with commas, quotes, and newlines', () {
      final rows = CsvCodec.parseCsv(
        'a,b\n"Acme, Inc.","pa,ss""word"\n"line one\nline two",x\n',
      );
      expect(rows[1], ['Acme, Inc.', 'pa,ss"word']);
      expect(rows[2], ['line one\nline two', 'x']);
    });

    test('CRLF and LF line endings', () {
      expect(CsvCodec.parseCsv('a,b\r\n1,2\r\n3,4\n'), [
        ['a', 'b'],
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('a quote inside an unquoted field stays literal', () {
      expect(CsvCodec.parseCsv('say ""hi"",b')[0], ['say ""hi""', 'b']);
    });

    test('empty content yields no rows', () {
      expect(CsvCodec.parseCsv(''), isEmpty);
    });
  });

  group('CsvCodec export round-trip', () {
    test('export → import keeps the two-factor secret', () {
      final entries = [
        makeEntry(
          title: 'GitHub',
          username: 'octo',
          totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP', digits: 8),
        ),
        makeEntry(title: 'No 2FA', username: 'plain'),
      ];
      final items = reimport(CsvCodec.export(entries)).items;
      expect(items[0].totp, entries[0].totp);
      expect(items[1].totp, isNull);
    });
  });

  group('CsvCodec.export', () {
    test('exports header plus one row per entry with quoting', () {
      final entries = [
        makeEntry(
          title: 'Acme, Inc.',
          username: 'me',
          password: 'pa"ss',
          url: 'https://acme.example',
          notes: 'two\nlines',
        ),
      ];
      final csv = CsvCodec.export(entries);
      expect(
        csv.startsWith('name,url,username,password,note,totp\r\n'),
        isTrue,
      );
      expect(csv.contains('"Acme, Inc."'), isTrue);
      expect(csv.contains('"pa""ss"'), isTrue);
      expect(csv.contains('"two\nlines"'), isTrue);
    });

    test('export → import round-trips values', () {
      final entries = [
        makeEntry(
          title: 'Site A',
          username: 'a@example.com',
          password: 'p1,with commas',
          url: 'https://a.example',
          notes: 'note "quoted"',
        ),
        makeEntry(
          title: 'Site B',
          username: 'b@example.com',
          password: 'plain',
          url: '',
          notes: '',
        ),
      ];
      final items = reimport(CsvCodec.export(entries)).items;
      expect(items.length, 2);
      expect(items[0].title, 'Site A');
      expect(items[0].password, 'p1,with commas');
      expect(items[0].notes, 'note "quoted"');
      expect(items[1].username, 'b@example.com');
    });
  });
}
