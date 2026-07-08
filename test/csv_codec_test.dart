import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/backup/services/csv_codec.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';

import 'fakes/fakes.dart';

void main() {
  group('CsvCodec.parseImport', () {
    test('parses Chrome-style export (name,url,username,password,note)', () {
      const csv = 'name,url,username,password,note\n'
          'GitHub,https://github.com,octo,s3cret!,work account\n'
          'Bank,https://bank.example,jo,hunter2,\n';
      final rows = CsvCodec.parseImport(csv);
      expect(rows.length, 2);
      expect(rows.first.name, 'GitHub');
      expect(rows.first.url, 'https://github.com');
      expect(rows.first.username, 'octo');
      expect(rows.first.password, 's3cret!');
      expect(rows.first.note, 'work account');
    });

    test('parses Bitwarden-style headers case-insensitively', () {
      const csv =
          'folder,favorite,type,Name,notes,fields,login_uri,login_username,login_password\n'
          ',,login,Email,my note,,https://mail.example,me@example.com,pa55word\n';
      final rows = CsvCodec.parseImport(csv);
      expect(rows.single.name, 'Email');
      expect(rows.single.url, 'https://mail.example');
      expect(rows.single.username, 'me@example.com');
      expect(rows.single.password, 'pa55word');
      expect(rows.single.note, 'my note');
    });

    test('handles quoted fields with commas, quotes, and newlines', () {
      const csv = 'name,url,username,password,note\n'
          '"Acme, Inc.",https://acme.example,user,"pa,ss""word","line one\nline two"\n';
      final rows = CsvCodec.parseImport(csv);
      expect(rows.single.name, 'Acme, Inc.');
      expect(rows.single.password, 'pa,ss"word');
      expect(rows.single.note, 'line one\nline two');
    });

    test('handles CRLF line endings', () {
      const csv =
          'name,username,password\r\nSite,me,secret123\r\nOther,you,pass456\r\n';
      final rows = CsvCodec.parseImport(csv);
      expect(rows.length, 2);
      expect(rows.last.password, 'pass456');
    });

    test('skips blank lines and rows with no usable data', () {
      const csv = 'name,username,password\n\nSite,me,secret\n,,\n';
      final rows = CsvCodec.parseImport(csv);
      expect(rows.length, 1);
    });

    test('falls back to the url as a name when the name is missing', () {
      const csv = 'name,url,username,password\n,ex.com,me,secret\n';
      expect(CsvCodec.parseImport(csv).single.name, 'ex.com');
    });

    test('throws FormatException when no known headers exist', () {
      expect(
        () => CsvCodec.parseImport('foo,bar\n1,2\n'),
        throwsFormatException,
      );
    });

    test('empty content yields no rows', () {
      expect(CsvCodec.parseImport(''), isEmpty);
    });
  });

  group('CsvCodec totp column', () {
    test('parses a Bitwarden login_totp otpauth URI', () {
      const csv = 'name,login_username,login_password,login_totp\n'
          'GitHub,octo,s3cret,'
          'otpauth://totp/GitHub:octo?secret=JBSWY3DPEHPK3PXP&digits=8\n';
      final row = CsvCodec.parseImport(csv).single;
      expect(row.totpConfig, isNotNull);
      expect(row.totpConfig!.secret, 'JBSWY3DPEHPK3PXP');
      expect(row.totpConfig!.digits, 8);
      expect(row.toEntry(id: 'x', now: DateTime(2026)).totp, row.totpConfig);
    });

    test('accepts a bare base32 secret in the totp column', () {
      const csv = 'name,username,password,totp\n'
          'Site,me,pw,jbsw y3dp ehpk 3pxp\n';
      final row = CsvCodec.parseImport(csv).single;
      expect(row.totpConfig!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('an unusable totp cell never blocks importing the password', () {
      const csv = 'name,username,password,totp\n'
          'Site,me,pw,definitely not a secret!\n';
      final row = CsvCodec.parseImport(csv).single;
      expect(row.totpConfig, isNull);
      expect(row.password, 'pw');
    });

    test('export → import round-trips the two-factor secret', () {
      final entries = [
        makeEntry(
          title: 'GitHub',
          username: 'octo',
          totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP', digits: 8),
        ),
        makeEntry(title: 'No 2FA', username: 'plain'),
      ];
      final rows = CsvCodec.parseImport(CsvCodec.export(entries));
      expect(rows[0].totpConfig, entries[0].totp);
      expect(rows[1].totpConfig, isNull);
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
      final rows = CsvCodec.parseImport(CsvCodec.export(entries));
      expect(rows.length, 2);
      expect(rows[0].name, 'Site A');
      expect(rows[0].password, 'p1,with commas');
      expect(rows[0].note, 'note "quoted"');
      expect(rows[1].username, 'b@example.com');
    });
  });
}
