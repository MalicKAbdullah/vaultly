import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/widgets/identity_check.dart';
import 'package:vaultkey/src/features/settings/services/emergency_kit.dart';

/// When the last emergency kit was printed, or null when none was.
final emergencyKitDateProvider = FutureProvider.autoDispose<DateTime?>(
  (ref) async {
    final raw = await ref
        .read(secureStorageProvider)
        .read(key: VaultKeyKeys.emergencyKitAt);
    return raw == null ? null : DateTime.parse(raw);
  },
);

/// Whether a backup passphrase is stored, so the kit can offer to print it.
final _hasBackupPassphraseProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      await ref.read(autoBackupServiceProvider).readPassphrase() != null,
);

/// Settings → Emergency kit: explains the page, then prints it.
///
/// The kit carries a new recovery key. It is made before the print dialog
/// opens but put in force only once the page was printed or saved, so
/// backing out of the dialog leaves the current recovery key working.
class EmergencyKitScreen extends ConsumerStatefulWidget {
  const EmergencyKitScreen({super.key});

  @override
  ConsumerState<EmergencyKitScreen> createState() => _EmergencyKitScreenState();
}

enum _Outcome { printed, cancelled }

class _EmergencyKitScreenState extends ConsumerState<EmergencyKitScreen> {
  bool _includePassphrase = false;
  bool _busy = false;
  _Outcome? _outcome;

  Future<void> _print() async {
    if (!await confirmVaultIdentity(
      context,
      ref,
      reason: 'Make an emergency kit',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _outcome = null;
    });
    // Everything the flow needs is read now: the print dialog sends Vaultly
    // to the background, which locks it and closes this screen, and the
    // flow still has to finish after that.
    final auth = ref.read(masterAuthServiceProvider);
    final storage = ref.read(secureStorageProvider);
    final backup = ref.read(autoBackupServiceProvider);
    final bridge = ref.read(printBridgeProvider);
    final now = ref.read(clockProvider).now();
    final pending =
        await ref.read(sessionProvider.notifier).prepareRecoveryKey();
    final folder = (await backup.loadConfig()).folderName;
    final passphrase =
        _includePassphrase ? await backup.readPassphrase() : null;

    final sent = await bridge.printEmergencyKit(
      jobName: EmergencyKit.jobName,
      blocks: EmergencyKit.blocks(
        date: now,
        recoveryKey: pending.recoveryKey,
        backupFolder: folder,
        backupPassphrase: passphrase,
      ),
    );
    if (sent) {
      await auth.commitRecoveryKey(pending);
      await storage.write(
        key: VaultKeyKeys.emergencyKitAt,
        value: now.toIso8601String(),
      );
    }
    if (!mounted) return;
    ref
      ..invalidate(hasRecoveryKeyProvider)
      ..invalidate(emergencyKitDateProvider);
    setState(() {
      _busy = false;
      _outcome = sent ? _Outcome.printed : _Outcome.cancelled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final hasKey = ref.watch(hasRecoveryKeyProvider).valueOrNull;
    final hasPassphrase =
        ref.watch(_hasBackupPassphraseProvider).valueOrNull ?? false;
    final body = AppTextStyles.body.copyWith(color: c.textSecondary);

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.smd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: c.accent),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.body.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency kit')),
      bottomNavigationBar: BottomActionBar(
        primary: VaultButton(
          label: _outcome == _Outcome.printed ? 'Done' : 'Print emergency kit',
          icon: _outcome == _Outcome.printed ? null : Icons.print_outlined,
          isLoading: _busy,
          onPressed: _busy
              ? null
              : _outcome == _Outcome.printed
                  ? () => Navigator.of(context).pop()
                  : _print,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          if (_outcome == _Outcome.printed) ...[
            const AppBanner(
              kind: BannerKind.success,
              title: 'Kit printed',
              message: 'The recovery key on it is now the one that works. '
                  'Check the page is readable, then keep it safe.',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_outcome == _Outcome.cancelled) ...[
            const AppBanner(
              kind: BannerKind.info,
              title: 'Nothing was printed',
              message: 'Your recovery key has not changed.',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            'A page to print, or save as a PDF, and keep somewhere safe.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.lg),
          point(
            Icons.key_rounded,
            'A new recovery key, to set a new master password on this phone.',
          ),
          point(
            Icons.restore_rounded,
            'How to restore a backup on a new phone.',
          ),
          point(
            Icons.edit_outlined,
            'A line to write your master password, if you want to.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasKey == true)
            const AppBanner(
              kind: BannerKind.warning,
              title: 'This replaces your recovery key',
              message: 'Once the kit is printed, your current recovery key '
                  'stops working.',
            ),
          if (hasPassphrase) ...[
            const SizedBox(height: AppSpacing.lg),
            RowGroup(
              children: [
                SettingsTile(
                  icon: Icons.password_rounded,
                  title: 'Include backup passphrase',
                  subtitle: 'Lets this page alone restore a backup',
                  showChevron: false,
                  trailing: Switch(
                    value: _includePassphrase,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _includePassphrase = v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: c.negative),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Anyone with this page can open your vault. Keep it '
                  'somewhere only you can reach.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
