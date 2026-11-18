import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/backup/services/file_transfer.dart';
import 'package:vaultkey/src/features/share/crypto/entry_share.dart';

final fileShareProvider = Provider<FileShare>(
  (ref) => FileShare(
    keyDerivation: ref.watch(keyDerivationProvider),
    cipher: ref.watch(cipherServiceProvider),
  ),
);

/// Opens the share sheet with a file. A seam so widget tests need no
/// platform channel.
final shareFileSenderProvider =
    Provider<Future<void> Function(String content, String fileName)>(
  (_) => (content, fileName) =>
      FileTransfer.shareAsFile(content: content, fileName: fileName),
);

/// A live camera view that reports the text of each QR code it reads.
final qrScannerProvider =
    Provider<Widget Function(ValueChanged<String> onCode)>(
  (_) => (onCode) => ReaderWidget(
        codeFormat: Format.qrCode,
        showGallery: false,
        showToggleCamera: false,
        onScan: (code) {
          final text = code.text;
          if (code.isValid && text != null) onCode(text);
        },
      ),
);
