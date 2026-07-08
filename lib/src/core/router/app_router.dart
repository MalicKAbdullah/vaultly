import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/shell/home_shell.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';
import 'package:vaultkey/src/features/autofill/screens/autofill_picker_screen.dart';
import 'package:vaultkey/src/features/auth/screens/onboarding_screen.dart';
import 'package:vaultkey/src/features/auth/screens/setup_screen.dart';
import 'package:vaultkey/src/features/auth/screens/unlock_screen.dart';
import 'package:vaultkey/src/features/backup/screens/export_screen.dart';
import 'package:vaultkey/src/features/backup/screens/import_screen.dart';
import 'package:vaultkey/src/features/generator/screens/generator_screen.dart';
import 'package:vaultkey/src/features/health/screens/health_screen.dart';
import 'package:vaultkey/src/features/settings/screens/change_master_password_screen.dart';
import 'package:vaultkey/src/features/settings/screens/settings_screen.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';
import 'package:vaultkey/src/features/vault/screens/entry_editor_screen.dart';
import 'package:vaultkey/src/features/vault/screens/vault_list_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String setup = '/setup';
  static const String unlock = '/unlock';
  static const String vault = '/vault';
  static const String generator = '/generator';
  static const String health = '/health';
  static const String settings = '/settings';
  static const String newEntry = '/entry/new';
  static const String changeMasterPassword = '/change-master-password';
  static const String export = '/export';
  static const String import = '/import';
  static const String autofillPicker = '/autofill-picker';

  static String entryDetail(String id) => '/entry/$id';

  static String editEntry(String id) => '/entry/$id/edit';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(sessionProvider, (_, __) => refresh.value++)
    // Re-route once the platform reports whether this launch is answering
    // another app's fill request.
    ..listen(autofillRequestProvider, (_, __) => refresh.value++)
    // Re-route once the first-run flag loads or gets written.
    ..listen(onboardingSeenProvider, (_, __) => refresh.value++);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(sessionProvider);
      final location = state.matchedLocation;
      switch (status) {
        case AuthStatus.unknown:
          return AppRoutes.splash;
        case AuthStatus.needsSetup:
          // First run: intro pages once, then master-password setup.
          final seen = ref.read(onboardingSeenProvider).valueOrNull;
          if (seen == null) return AppRoutes.splash; // flag still loading
          final target = seen ? AppRoutes.setup : AppRoutes.onboarding;
          return location == target ? null : target;
        case AuthStatus.locked:
          return location == AppRoutes.unlock ? null : AppRoutes.unlock;
        case AuthStatus.unlocked:
          // Answering another app's fill request takes over the session:
          // the only destination is the entry picker.
          final autofillPending =
              ref.read(autofillRequestProvider).valueOrNull != null;
          if (autofillPending) {
            return location == AppRoutes.autofillPicker
                ? null
                : AppRoutes.autofillPicker;
          }
          final gate = location == AppRoutes.splash ||
              location == AppRoutes.onboarding ||
              location == AppRoutes.setup ||
              location == AppRoutes.unlock ||
              location == AppRoutes.autofillPicker;
          return gate ? AppRoutes.vault : null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (_, __) => const SetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        builder: (_, __) => const UnlockScreen(),
      ),
      GoRoute(
        path: AppRoutes.autofillPicker,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AutofillPickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.newEntry,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const EntryEditorScreen(),
      ),
      GoRoute(
        path: '/entry/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            EntryDetailScreen(entryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/entry/:id/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            EntryEditorScreen(entryId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.changeMasterPassword,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ChangeMasterPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.import,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ImportScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.vault,
                builder: (_, __) => const VaultListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.generator,
                builder: (_, __) => const GeneratorScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.health,
                builder: (_, __) => const HealthScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
