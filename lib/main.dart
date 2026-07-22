import 'package:core_notify/core_notify.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/app.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/notifications/vault_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local notifications (backup alerts + vault-health digest). Tapping just
  // opens the app.
  final notify = LocalNotify();
  await notify.initialize(channels: VaultNotifier.channels, onSelect: (_) {});
  await notify.requestPermission();

  runApp(
    ProviderScope(
      overrides: [notifyProvider.overrideWithValue(notify)],
      child: const VaultKeyApp(),
    ),
  );
}
