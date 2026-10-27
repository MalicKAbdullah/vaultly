import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/bitwarden_json_importer.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/parsers/onepux_importer.dart';

/// What reading an export file produced: either a finished batch, or a CSV
/// whose columns the user must map first.
sealed class ImportReadResult {
  const ImportReadResult();
}

final class ImportReady extends ImportReadResult {
  const ImportReady(this.batch);

  final ImportBatch batch;
}

final class ImportNeedsMapping extends ImportReadResult {
  const ImportNeedsMapping(this.table, this.suggested);

  final CsvTable table;
  final CsvColumnMapping suggested;
}

/// Recognises an export by its bytes (zip magic, JSON shape, CSV header)
/// and hands it to the right importer.
abstract final class ImportDetector {
  static ImportReadResult read({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (_isZip(bytes) || fileName.toLowerCase().endsWith('.1pux')) {
      return ImportReady(OnePuxImporter.parse(bytes));
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ImportFormatException(
        'That file is not text. Choose a CSV, JSON or .1pux export.',
      );
    }
    final trimmed = text.trimLeft().replaceFirst('﻿', '');
    if (trimmed.startsWith('{')) {
      return ImportReady(BitwardenJsonImporter.parse(trimmed));
    }
    return readCsv(text);
  }

  /// Picks the CSV importer from the header row.
  static ImportReadResult readCsv(String text) {
    final table = CsvTable.parse(text);
    final keys = table.keys.toSet();
    if (keys.containsAll(['login_uri', 'login_username', 'login_password'])) {
      return ImportReady(CsvImporters.bitwarden(table));
    }
    if (keys.containsAll(['title', 'username', 'password']) &&
        (keys.contains('otpauth') || keys.contains('archived'))) {
      return ImportReady(CsvImporters.onePassword(table));
    }
    if (keys.containsAll(['name', 'url', 'username', 'password'])) {
      return ImportReady(CsvImporters.chrome(table));
    }
    return ImportNeedsMapping(table, CsvImporters.guessMapping(table.header));
  }

  static bool _isZip(Uint8List b) =>
      b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4;
}
