import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';

/// One QR code from Google Authenticator's "Transfer accounts" export.
/// Large exports span several codes that share [batchId].
final class MigrationBatch {
  const MigrationBatch({
    required this.authenticators,
    required this.warnings,
    required this.batchSize,
    required this.batchIndex,
    required this.batchId,
  });

  final List<ImportedAuthenticator> authenticators;
  final List<String> warnings;

  /// How many QR codes the whole export has (1 when not split).
  final int batchSize;

  /// This code's position, from 0.
  final int batchIndex;
  final int batchId;
}

/// Decodes `otpauth-migration://offline?data=<base64 protobuf>` links.
///
/// The payload is Google's `MigrationPayload` message:
/// `repeated OtpParameters otp_parameters = 1; int32 version = 2;
/// int32 batch_size = 3; int32 batch_index = 4; int32 batch_id = 5;` where
/// `OtpParameters` is `bytes secret = 1; string name = 2; string issuer = 3;
/// Algorithm algorithm = 4; DigitCount digits = 5; OtpType type = 6;
/// int64 counter = 7;`. The format has no period field: every code it
/// carries uses 30 seconds.
abstract final class OtpauthMigration {
  static bool looksLikeMigration(String input) =>
      input.trim().toLowerCase().startsWith('otpauth-migration://');

  static MigrationBatch parse(String link) {
    final Uri uri;
    try {
      uri = Uri.parse(link.trim());
    } on FormatException {
      throw const ImportFormatException('That QR code is not readable.');
    }
    if (uri.scheme.toLowerCase() != 'otpauth-migration' ||
        uri.host.toLowerCase() != 'offline') {
      throw const ImportFormatException(
        'That is not a Google Authenticator export code.',
      );
    }
    final data = uri.queryParameters['data'];
    if (data == null || data.isEmpty) {
      throw const ImportFormatException('That export code has no data.');
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(base64.normalize(
        data.replaceAll(' ', '+').replaceAll('-', '+').replaceAll('_', '/'),
      ));
    } on FormatException {
      throw const ImportFormatException('That export code is damaged.');
    }
    try {
      return decodePayload(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static MigrationBatch decodePayload(Uint8List bytes) {
    final authenticators = <ImportedAuthenticator>[];
    final warnings = <String>[];
    var batchSize = 1;
    var batchIndex = 0;
    var batchId = 0;
    try {
      final reader = _ProtoReader(bytes);
      while (!reader.done) {
        final (field, wire) = reader.tag();
        switch ((field, wire)) {
          case (1, 2):
            final otp = _otp(reader.bytes(), warnings);
            if (otp != null) authenticators.add(otp);
          case (3, 0):
            batchSize = reader.varint();
          case (4, 0):
            batchIndex = reader.varint();
          case (5, 0):
            batchId = reader.varint();
          default:
            reader.skip(wire);
        }
      }
    } on RangeError {
      throw const ImportFormatException('That export code is damaged.');
    }
    return MigrationBatch(
      authenticators: authenticators,
      warnings: warnings,
      batchSize: batchSize < 1 ? 1 : batchSize,
      batchIndex: batchIndex,
      batchId: batchId,
    );
  }

  static ImportedAuthenticator? _otp(Uint8List bytes, List<String> warnings) {
    final reader = _ProtoReader(bytes);
    Uint8List? secret;
    var name = '';
    var issuer = '';
    var algorithm = 0;
    var digits = 0;
    var type = 0;
    while (!reader.done) {
      final (field, wire) = reader.tag();
      switch ((field, wire)) {
        case (1, 2):
          secret = reader.bytes();
        case (2, 2):
          name = utf8.decode(reader.bytes(), allowMalformed: true);
        case (3, 2):
          issuer = utf8.decode(reader.bytes(), allowMalformed: true);
        case (4, 0):
          algorithm = reader.varint();
        case (5, 0):
          digits = reader.varint();
        case (6, 0):
          type = reader.varint();
        default:
          reader.skip(wire);
      }
    }

    // The name is "Issuer:account" or just "account".
    var account = name.trim();
    final colon = account.indexOf(':');
    if (colon != -1) {
      final prefix = account.substring(0, colon).trim();
      account = account.substring(colon + 1).trim();
      if (issuer.trim().isEmpty) issuer = prefix;
    }
    issuer = issuer.trim();
    final label = [issuer, account].where((p) => p.isNotEmpty).join(' · ');
    final shown = label.isEmpty ? 'An account' : '"$label"';

    if (type == 1) {
      warnings.add('$shown uses counter-based codes (HOTP), which Vaultly '
          'does not support.');
      return null;
    }
    final algo = switch (algorithm) {
      0 || 1 => TotpAlgorithm.sha1,
      2 => TotpAlgorithm.sha256,
      3 => TotpAlgorithm.sha512,
      _ => null,
    };
    if (algo == null) {
      warnings.add('$shown uses an algorithm Vaultly does not support.');
      return null;
    }
    if (secret == null || secret.isEmpty) {
      warnings.add('$shown has no secret in the export.');
      return null;
    }
    final config = TotpConfig(
      secret: Base32.encode(secret),
      algorithm: algo,
      digits: digits == 2 ? 8 : 6,
    );
    secret.fillRange(0, secret.length, 0);
    return ImportedAuthenticator(
      config: config,
      issuer: issuer,
      account: account,
    );
  }
}

/// Minimal protobuf wire-format reader (varint, 64-bit, length-delimited,
/// 32-bit). Reading past the end throws [RangeError].
final class _ProtoReader {
  _ProtoReader(this._buf);

  final Uint8List _buf;
  int _pos = 0;

  bool get done => _pos >= _buf.length;

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _buf.length) throw RangeError('truncated varint');
      final b = _buf[_pos++];
      if (shift < 63) result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 70) throw RangeError('varint too long');
    }
  }

  Uint8List bytes() {
    final len = varint();
    if (len < 0 || _pos + len > _buf.length) {
      throw RangeError('truncated field');
    }
    final out = Uint8List.sublistView(_buf, _pos, _pos + len);
    _pos += len;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        bytes();
      case 5:
        _advance(4);
      default:
        throw RangeError('unsupported wire type $wire');
    }
  }

  void _advance(int n) {
    if (_pos + n > _buf.length) throw RangeError('truncated field');
    _pos += n;
  }
}
