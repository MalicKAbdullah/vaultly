import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/widgets/identity_check.dart';
import 'package:vaultkey/src/features/sync/providers/sync_providers.dart';
import 'package:vaultkey/src/features/sync/screens/pair_device_screen.dart';
import 'package:vaultkey/src/features/sync/services/sync_ledger.dart';

/// Sync with paired devices over the local network. Sync runs while this
/// screen is open on both devices; the paired-device list allows unpairing.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(syncControllerProvider.notifier).start());
    });
  }

  Future<void> _pair() async {
    if (!await confirmVaultIdentity(
      context,
      ref,
      reason: 'Pair a device with your vault',
    )) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PairDeviceScreen()),
    );
    if (mounted) unawaited(ref.read(syncControllerProvider.notifier).start());
  }

  Future<void> _unpair(PairedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unpair ${device.name}?'),
        content: const Text(
          'This device forgets the shared key. To sync again you will need '
          'to pair both devices again. Unpair on the other device too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncLedgerProvider).removePeer(device.id);
    ref.invalidate(pairedDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final status = ref.watch(syncControllerProvider);
    final peers = ref.watch(pairedDevicesProvider).valueOrNull ?? const [];
    final me = ref.watch(localDeviceProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync devices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          if (status.message != null) ...[
            AppBanner(
              kind: switch (status.phase) {
                SyncPhase.done => BannerKind.success,
                SyncPhase.failed => BannerKind.error,
                _ => BannerKind.info,
              },
              icon: switch (status.phase) {
                SyncPhase.done => Icons.check_circle_rounded,
                SyncPhase.failed => Icons.sync_problem_rounded,
                _ => Icons.sync_rounded,
              },
              title: switch (status.phase) {
                SyncPhase.done => 'Synced',
                SyncPhase.failed => 'Sync did not finish',
                SyncPhase.syncing => 'Syncing',
                SyncPhase.listening => 'Ready to sync',
                SyncPhase.idle => 'No devices yet',
              },
              message: status.message,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (peers.isNotEmpty)
            VaultButton(
              label: 'Sync again',
              icon: Icons.sync_rounded,
              isLoading: status.phase == SyncPhase.syncing,
              onPressed: status.phase == SyncPhase.syncing
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).start(),
            ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Paired devices'),
          if (peers.isEmpty)
            Text(
              'None yet. Pair your other phone or tablet to keep both '
              'vaults the same.',
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
            )
          else
            RowGroup(
              separatorIndent: 66,
              children: [
                for (final p in peers)
                  SettingsTile(
                    icon: Icons.smartphone_rounded,
                    title: p.name,
                    subtitle: p.lastSyncAt == null
                        ? 'Not synced yet'
                        : 'Last synced '
                            '${DateFormat.yMMMd().add_jm().format(p.lastSyncAt!.toLocal())}',
                    showChevron: false,
                    trailing: TextButton(
                      onPressed: () => _unpair(p),
                      child: const Text('Unpair'),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          VaultButton(
            label: 'Pair a device',
            icon: Icons.add_link_rounded,
            variant: VaultButtonVariant.secondary,
            onPressed: _pair,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Sync works directly between your devices on the same Wi-Fi. '
            'There is no server: both devices need Vaultly open and unlocked '
            'on this screen. Everything sent is encrypted with a key only '
            'your paired devices hold.'
            '${me == null ? '' : '\n\nThis device: ${me.name}'}',
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
