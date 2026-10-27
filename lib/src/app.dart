import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/appearance_provider.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/security/inactivity_locker.dart';

class VaultKeyApp extends ConsumerWidget {
  const VaultKeyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final appearance = ref.watch(appearanceProvider);
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp.router(
        title: 'Vaultly',
        theme: AppTheme.build(Brightness.light, accent: AppAccents.vaultly),
        darkTheme: AppTheme.build(Brightness.dark, accent: AppAccents.vaultly),
        themeMode: appearance.mode,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            InactivityLocker(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
