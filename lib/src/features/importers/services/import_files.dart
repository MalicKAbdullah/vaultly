import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// An export file's raw bytes, held only in memory. Call [wipe] as soon as
/// it has been parsed.
final class PickedExport {
  PickedExport({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  void wipe() => bytes.fillRange(0, bytes.length, 0);
}

/// Reads export files through the system picker without ever writing them.
/// Not unit-tested (platform channels); parsing lives in the importers.
abstract final class ImportFiles {
  /// Lets the user pick an export and returns its bytes, or null when
  /// cancelled.
  static Future<PickedExport?> pickExport() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      final file = result?.files.singleOrNull;
      if (file == null) return null;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) return null;
      return PickedExport(name: file.name, bytes: bytes);
    } finally {
      await _clearPickerCopies();
    }
  }

  /// Lets the user pick an image and runs [read] on its path. The picker's
  /// cached copy is deleted afterwards, whatever [read] does.
  static Future<T?> withPickedImage<T>(
    Future<T> Function(String path) read,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.singleOrNull?.path;
      if (path == null) return null;
      return await read(path);
    } finally {
      await _clearPickerCopies();
    }
  }

  /// file_picker copies the chosen file into the app's cache on Android and
  /// iOS; that copy is plaintext, so it is removed straight away.
  static Future<void> _clearPickerCopies() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await FilePicker.platform.clearTemporaryFiles();
    }
  }
}
