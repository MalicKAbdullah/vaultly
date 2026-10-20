import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_crypto/core_crypto.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/biometric_key_vault.dart';
import 'package:vaultkey/src/core/shell/home_shell.dart';
import 'package:vaultkey/src/features/auth/screens/onboarding_screen.dart';
import 'package:vaultkey/src/features/auth/screens/setup_screen.dart';
import 'package:vaultkey/src/features/auth/screens/unlock_screen.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/backup/screens/export_screen.dart';
import 'package:vaultkey/src/features/backup/screens/import_screen.dart';
import 'package:vaultkey/src/features/generator/screens/generator_screen.dart';
import 'package:vaultkey/src/features/health/screens/health_screen.dart';
import 'package:vaultkey/src/features/settings/screens/settings_screen.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';
import 'package:vaultkey/src/features/vault/screens/entry_editor_screen.dart';
import 'package:vaultkey/src/features/vault/screens/vault_list_screen.dart';

import '../fakes/fakes.dart';
import '../widgets/helpers.dart';

/// Design-review renders of every main screen, light and dark side by side.
/// Run on request only: `GALLERY=<out dir> flutter test test/gallery`.
/// Pixels differ per platform, so these are previews, not CI goldens. All
/// items are invented; none of the passwords belong to anyone.
final String? _out = Platform.environment['GALLERY'];

final _now = DateTime(2026, 10, 20, 21, 43);

final _entries = [
  makeEntry(
    id: 'github',
    title: 'GitHub',
    username: 'sara.ahmed',
    password: 'Qm7#vR2!kT9pL4xZ',
    url: 'github.com',
    favorite: true,
    totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
    createdAt: DateTime(2025, 2, 3),
    updatedAt: DateTime(2026, 10, 18),
    passwordChangedAt: DateTime(2026, 9, 2),
    notes: 'Recovery codes are in the safe, envelope 3.',
    history: [
      PasswordHistoryEntry(
        password: 'old-Example-Pass1',
        replacedAt: DateTime(2026, 9, 2),
      ),
    ],
  ),
  makeEntry(
    id: 'bank',
    title: 'Meezan Bank',
    username: 'sara.ahmed@example.com',
    password: 'p8&Wd3^nY6qJ1s',
    url: 'meezanbank.example',
    favorite: true,
    category: EntryCategory.card,
    updatedAt: DateTime(2026, 10, 12),
  ),
  makeEntry(
    id: 'gmail',
    title: 'Gmail',
    username: 'sara.ahmed@example.com',
    password: 'summer2019',
    url: 'mail.google.com',
    favorite: true,
    totp: const TotpConfig(secret: 'KRUGS4ZANFZSAYJA'),
    updatedAt: DateTime(2026, 10, 9),
    passwordChangedAt: DateTime(2024, 4, 1),
  ),
  makeEntry(
    id: 'netflix',
    title: 'Netflix',
    username: 'family@example.com',
    password: 'summer2019',
    url: 'netflix.com',
    updatedAt: DateTime(2026, 10, 1),
  ),
  makeEntry(
    id: 'figma',
    title: 'Figma',
    username: 'sara@studio.example',
    password: 'Hx4!rB8@cN2#fV6m',
    url: 'figma.com',
    totp: const TotpConfig(secret: 'MFRGGZDFMZTWQ2LK'),
    updatedAt: DateTime(2026, 9, 21),
  ),
  makeEntry(
    id: 'daraz',
    title: 'Daraz',
    username: 'sara.ahmed',
    password: 'Lz5%tE9&uK3*wQ7d',
    url: 'daraz.pk',
    updatedAt: DateTime(2026, 9, 12),
    passwordChangedAt: DateTime(2024, 11, 5),
  ),
  makeEntry(
    id: 'passport',
    title: 'Passport',
    username: '',
    password: '',
    url: '',
    category: EntryCategory.identity,
    notes: 'Renewal due March 2028.',
    updatedAt: DateTime(2026, 8, 30),
  ),
  makeEntry(
    id: 'wifi',
    title: 'Home Wi-Fi',
    username: 'Ahmed-5G',
    password: 'Gq2@Ny7!Rb4#Kc9s',
    url: '',
    category: EntryCategory.note,
    updatedAt: DateTime(2026, 8, 2),
  ),
];

Future<void> _loadFonts() async {
  Future<void> family(String name, String prefix, List<String> weights) async {
    final loader = FontLoader(name);
    for (final w in weights) {
      loader.addFont(rootBundle.load('$prefix-$w.ttf'));
    }
    await loader.load();
  }

  const fonts = 'packages/core_theme/fonts';
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await family(AppTextStyles.fontFamily, '$fonts/MonaSans', weights);
  await family(AppTextStyles.displayFamily, '$fonts/MonaSansDisplay', weights);
  await family(
    AppTextStyles.monoFamily,
    '$fonts/MonaSansMono',
    ['Regular', 'Medium', 'SemiBold'],
  );
  final root = Platform.environment['FLUTTER_ROOT'] ??
      '/Users/abdullah/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '$root/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

Future<List<Override>> _overrides({
  List<VaultEntry>? entries,
  FakeSecureStorage? storage,
  InMemoryFileStore? fileStore,
  FakeBiometricAuthenticator? biometrics,
}) async =>
    [
      vaultEntriesProvider
          .overrideWith(() => FakeVaultNotifier(entries ?? _entries)),
      secureStorageProvider.overrideWithValue(storage ?? FakeSecureStorage()),
      fileStoreProvider.overrideWithValue(fileStore ?? InMemoryFileStore()),
      keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
      clockProvider.overrideWithValue(FixedClock(_now)),
      systemClipboardProvider.overrideWithValue(FakeClipboard()),
      backupFolderProvider.overrideWithValue(FakeBackupFolder()),
      autofillBridgeProvider.overrideWithValue(
        FakeAutofillBridge(enabled: true),
      ),
      biometricAuthenticatorProvider.overrideWithValue(
        biometrics ?? FakeBiometricAuthenticator(),
      ),
      updateCheckProvider.overrideWith((_) async => null),
    ];

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget Function() screen, {
  List<Override> overrides = const [],
  int? tab,
  double height = 844,
}) async {
  const width = 390.0;
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size((width * 2 + 8) * 2, height * 2);
  addTearDown(tester.view.reset);
  final key = GlobalKey();

  Widget pane(Brightness b) => SizedBox(
        width: width,
        height: height,
        child: ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(b, accent: AppAccents.vaultly),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, height),
                padding: const EdgeInsets.only(top: 24),
                viewPadding: const EdgeInsets.only(top: 24),
                disableAnimations: true,
              ),
              child: tab == null
                  ? screen()
                  : Scaffold(
                      body: screen(),
                      bottomNavigationBar: HomeNavigationBar(
                        selectedIndex: tab,
                        onSelected: (_) {},
                      ),
                    ),
            ),
          ),
        ),
      );

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: const Color(0xFF808080),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pane(Brightness.light),
              const SizedBox(width: 8),
              pane(Brightness.dark),
            ],
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out!).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  // Dispose the screens (and their timers) before the test ends.
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(_loadFonts);

  final skip = _out == null ? 'Set GALLERY=<dir> to render previews' : null;

  testWidgets('home', skip: skip != null, (tester) async {
    await _render(
      tester,
      'home',
      VaultListScreen.new,
      overrides: await _overrides(),
      tab: 0,
      height: 1640,
    );
  });

  testWidgets('home-phone', skip: skip != null, (tester) async {
    await _render(
      tester,
      'home-phone',
      VaultListScreen.new,
      overrides: await _overrides(),
      tab: 0,
    );
  });

  testWidgets('home-empty', skip: skip != null, (tester) async {
    await _render(
      tester,
      'home-empty',
      VaultListScreen.new,
      overrides: await _overrides(entries: const []),
      tab: 0,
    );
  });

  testWidgets('home-search', skip: skip != null, (tester) async {
    final overrides = await _overrides();
    await _render(
      tester,
      'home-search',
      () => Consumer(
        builder: (context, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ref.read(vaultQueryProvider).search.isEmpty) {
              ref.read(vaultQueryProvider.notifier).setSearch('sara.ahmed');
            }
          });
          return const VaultListScreen();
        },
      ),
      overrides: overrides,
      tab: 0,
    );
  });

  testWidgets('detail', skip: skip != null, (tester) async {
    await _render(
      tester,
      'detail',
      () => const EntryDetailScreen(entryId: 'github'),
      overrides: await _overrides(),
      height: 1240,
    );
  });

  testWidgets('editor', skip: skip != null, (tester) async {
    await _render(
      tester,
      'editor',
      () => const EntryEditorScreen(entryId: 'github'),
      overrides: await _overrides(),
      height: 1100,
    );
  });

  testWidgets('generator', skip: skip != null, (tester) async {
    await _render(
      tester,
      'generator',
      GeneratorScreen.new,
      overrides: await _overrides(),
      tab: 1,
      height: 980,
    );
  });

  testWidgets('security', skip: skip != null, (tester) async {
    await _render(
      tester,
      'security',
      HealthScreen.new,
      overrides: await _overrides(),
      tab: 2,
      height: 1640,
    );
  });

  testWidgets('settings', skip: skip != null, (tester) async {
    await _render(
      tester,
      'settings',
      SettingsScreen.new,
      overrides: await _overrides(),
      tab: 3,
      height: 1900,
    );
  });

  testWidgets('export', skip: skip != null, (tester) async {
    await _render(
      tester,
      'export',
      ExportScreen.new,
      overrides: await _overrides(),
    );
  });

  testWidgets('import', skip: skip != null, (tester) async {
    await _render(
      tester,
      'import',
      ImportScreen.new,
      overrides: await _overrides(),
    );
  });

  testWidgets('onboarding', skip: skip != null, (tester) async {
    await _render(
      tester,
      'onboarding',
      OnboardingScreen.new,
      overrides: await _overrides(),
    );
  });

  testWidgets('setup', skip: skip != null, (tester) async {
    await _render(
      tester,
      'setup',
      SetupScreen.new,
      overrides: await _overrides(),
    );
  });

  testWidgets('lock', skip: skip != null, (tester) async {
    const password = 'gallery only';
    final storage = FakeSecureStorage();
    final fileStore = InMemoryFileStore();
    final biometrics = FakeBiometricAuthenticator(result: false);
    await tester.runAsync(() async {
      final auth = MasterAuthService(
        storage: storage,
        keyDerivation: FakeKeyDerivation(),
        cipher: const CipherService(),
        fileStore: fileStore,
        clock: FixedClock(_now),
      );
      await auth.setup(password);
      final unlocked = await auth.unlock(password) as UnlockSuccess;
      await BiometricUnlockService(
        storage: storage,
        authenticator: biometrics,
        vault: SecureStorageKeyVault(
          storage: storage,
          authenticator: FakeBiometricAuthenticator(),
        ),
      ).enable(unlocked.key);
    });
    await _render(
      tester,
      'lock',
      UnlockScreen.new,
      overrides: await _overrides(
        storage: storage,
        fileStore: fileStore,
        biometrics: biometrics,
      ),
    );
  });
}
