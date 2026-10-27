import 'dart:async';

import 'package:core_notify/core_notify.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/app.dart';
import 'package:vaultkey/src/core/appearance_provider.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/startup_timeline.dart';
import 'package:vaultkey/src/features/notifications/vault_notifier.dart';

Future<void> main() async {
  StartupTimeline.start();
  WidgetsFlutterBinding.ensureInitialized();

  // Local notifications (backup alerts + vault-health digest). Set up after
  // the first frame is scheduled; LocalNotify queues calls until it is ready.
  final notify = LocalNotify(
    smallIcon: 'ic_stat_notify',
    accentColor: AppAccents.vaultly.light,
  );

  final appearance = await AppearanceController.load();

  runApp(
    ProviderScope(
      overrides: [
        notifyProvider.overrideWithValue(notify),
        appearanceProvider.overrideWithValue(appearance),
      ],
      child: const VaultKeyApp(),
    ),
  );

  StartupTimeline.markOnceAfterFrame('first frame');
  // Tapping a notification just opens the app.
  unawaited(
    notify
        .initialize(channels: VaultNotifier.channels, onSelect: (_) {})
        .then((_) => notify.requestPermission()),
  );
}
