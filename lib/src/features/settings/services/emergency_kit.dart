import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vaultkey/src/core/interfaces/print_bridge.dart';

/// The printed emergency kit: the recovery key for a forgotten master
/// password on this phone, and how to restore a backup on a new phone.
abstract final class EmergencyKit {
  static const String jobName = 'Vaultly emergency kit';

  /// The page, top to bottom. [backupPassphrase] is printed only when the
  /// user chose to include it; otherwise the page leaves a line to write it.
  static List<PrintBlock> blocks({
    required DateTime date,
    required String recoveryKey,
    required String? backupFolder,
    required String? backupPassphrase,
  }) =>
      [
        const PrintBlock(PrintBlockStyle.title, 'Vaultly emergency kit'),
        PrintBlock(
          PrintBlockStyle.caption,
          'Made on ${DateFormat('d MMMM yyyy').format(date)}',
        ),
        const PrintBlock(
          PrintBlockStyle.warning,
          'Anyone with this page can open your vault. Keep it somewhere only '
          'you can reach.',
        ),
        const PrintBlock(
          PrintBlockStyle.heading,
          'If you forget your master password',
        ),
        const PrintBlock(
          PrintBlockStyle.text,
          'You still have this phone.\n'
          '1. Open Vaultly and tap "Forgot password?" on the lock screen.\n'
          '2. Type this recovery key, or scan the code.\n'
          '3. Choose a new master password.',
        ),
        PrintBlock(PrintBlockStyle.secret, recoveryKey),
        PrintBlock.qr(qrModules(recoveryKey)),
        const PrintBlock(
          PrintBlockStyle.caption,
          'This key works only on this phone, and only until you make a new '
          'kit or recovery key.',
        ),
        const PrintBlock(PrintBlockStyle.heading, 'If you lose this phone'),
        PrintBlock(
          PrintBlockStyle.text,
          'Restore a backup file on your new phone.\n'
          '${backupFolder == null ? 'Back up from Settings in Vaultly: '
              'Export, or Auto-backup to a folder.' : 'Your backups are saved '
              'in the folder "$backupFolder".'}\n'
          '1. Install Vaultly and choose a new master password.\n'
          '2. Go to Settings, then Import, and choose the .vkbackup file.\n'
          '3. Enter the backup passphrase.',
        ),
        if (backupPassphrase == null)
          const PrintBlock(PrintBlockStyle.writeIn, 'Backup passphrase')
        else ...[
          const PrintBlock(PrintBlockStyle.caption, 'Backup passphrase'),
          PrintBlock(PrintBlockStyle.secret, backupPassphrase),
        ],
        const PrintBlock(
          PrintBlockStyle.writeIn,
          'Master password (optional, write by hand)',
        ),
      ];

  /// [data] as QR modules, error correction M.
  static QrModules qrModules(String data) {
    final image = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final size = image.moduleCount;
    final modules = Uint8List(size * size);
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if (image.isDark(row, col)) modules[row * size + col] = 1;
      }
    }
    return QrModules(size: size, modules: modules);
  }
}
