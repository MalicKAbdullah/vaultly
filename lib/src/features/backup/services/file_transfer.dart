import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrappers around the platform share sheet and save/open dialogs so
/// screens stay declarative. Not unit-tested (platform channels); all
/// interesting logic lives in the pure codecs.
abstract final class FileTransfer {
  /// Opens the share sheet with [content] attached as [fileName].
  static Future<void> shareAsFile({
    required String content,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, flush: true);
    try {
      await Share.shareXFiles([XFile(file.path)]);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Opens the system "save file" dialog. Returns true when saved.
  static Future<bool> saveAs({
    required String content,
    required String fileName,
  }) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    return path != null;
  }

  /// Lets the user pick a file and returns its text content, or null when
  /// cancelled.
  static Future<PickedFile?> pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    if (file == null) return null;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return PickedFile(name: file.name, content: utf8.decode(bytes));
  }
}

final class PickedFile {
  const PickedFile({required this.name, required this.content});

  final String name;
  final String content;
}
