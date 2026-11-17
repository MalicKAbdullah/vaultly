import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How one block of a printed page is drawn.
enum PrintBlockStyle {
  /// The page title.
  title,

  /// Small grey text under the title.
  caption,

  /// A boxed warning.
  warning,

  /// A section heading.
  heading,

  /// Body text.
  text,

  /// A secret to copy by eye: large monospace.
  secret,

  /// A QR code; [PrintBlock.qr] holds its modules.
  qr,

  /// A labelled empty line to write on by hand.
  writeIn,
}

/// One block of a printed page, laid out top to bottom.
@immutable
final class PrintBlock {
  const PrintBlock(this.style, this.text) : qr = null;

  const PrintBlock.qr(QrModules this.qr)
      : style = PrintBlockStyle.qr,
        text = '';

  final PrintBlockStyle style;
  final String text;
  final QrModules? qr;

  Map<String, Object> toMap() => {
        'style': style.name,
        'text': text,
        if (qr != null) 'qrSize': qr!.size,
        if (qr != null) 'qrModules': qr!.modules,
      };
}

/// A QR code as a square of modules: [modules] holds `size * size` bytes,
/// row by row, 1 for dark.
@immutable
final class QrModules {
  const QrModules({required this.size, required this.modules});

  final int size;
  final Uint8List modules;
}

/// Prints a page through the platform print dialog (printer or "Save as
/// PDF"). Completes when the dialog closes.
abstract interface class IPrintBridge {
  Future<void> printEmergencyKit({
    required String jobName,
    required List<PrintBlock> blocks,
  });
}

/// Android: `android.print.PrintManager` drawing on a `PdfDocument`.
final class MethodChannelPrintBridge implements IPrintBridge {
  const MethodChannelPrintBridge();

  static const MethodChannel _channel = MethodChannel('vaultly/print');

  @override
  Future<void> printEmergencyKit({
    required String jobName,
    required List<PrintBlock> blocks,
  }) =>
      _channel.invokeMethod<void>('printEmergencyKit', {
        'jobName': jobName,
        'blocks': [for (final b in blocks) b.toMap()],
      });
}
