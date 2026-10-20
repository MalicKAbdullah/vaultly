import 'dart:async';
import 'dart:developer' as developer;

import 'package:core_notify/core_notify.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/app.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/notifications/vault_notifier.dart';

void main() {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // Local notifications (backup alerts + vault-health digest). Set up after
  // the first frame is scheduled; LocalNotify queues calls until it is ready.
  final notify = LocalNotify(
    smallIcon: 'ic_stat_notify',
    accentColor: AppAccents.vaultly.light,
  );

  runApp(
    ProviderScope(
      overrides: [notifyProvider.overrideWithValue(notify)],
      child: const VaultKeyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback(
    (_) => developer.log(
      'first frame ${startup.elapsedMilliseconds} ms',
      name: 'vaultly.startup',
    ),
  );
  // Tapping a notification just opens the app.
  unawaited(
    notify
        .initialize(channels: VaultNotifier.channels, onSelect: (_) {})
        .then((_) => notify.requestPermission()),
  );
}
