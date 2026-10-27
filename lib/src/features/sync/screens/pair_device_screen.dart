import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/pairing.dart';
import 'package:vaultkey/src/features/sync/providers/sync_providers.dart';
import 'package:vaultkey/src/features/sync/services/pairing_host.dart';
import 'package:vaultkey/src/features/sync/services/sync_ledger.dart';
import 'package:vaultkey/src/features/sync/services/sync_network.dart';

enum _Role { show, scan }

enum _Step { starting, waiting, compare, confirming, failed }

/// Pairs this device with another: one shows a QR code, the other scans
/// it, then both people check the same six digits before the key is saved.
class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen> {
  _Role _role = _Role.show;
  _Step _step = _Step.starting;
  PairingHost? _host;
  FrameChannel? _channel;
  PairingResult? _result;
  String? _error;
  MobileScannerController? _scanner;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    unawaited(_showCode());
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }

  Future<void> _teardown() async {
    await _host?.close().catchError((Object _) {});
    _host = null;
    await _channel?.close();
    _channel = null;
    _scanner?.dispose();
    _scanner = null;
  }

  void _setRole(_Role role) {
    if (role != _role) _restart(role);
  }

  void _restart(_Role role) {
    unawaited(_teardown().then((_) {
      if (!mounted) return;
      setState(() {
        _role = role;
        _step = _Step.starting;
        _error = null;
        _scanned = false;
        _result = null;
      });
      if (role == _Role.show) {
        unawaited(_showCode());
      } else {
        setState(() {
          _scanner = MobileScannerController(
            formats: const [BarcodeFormat.qrCode],
          );
          _step = _Step.waiting;
        });
      }
    }));
  }

  Future<void> _showCode() async {
    try {
      final device = await ref.read(syncLedgerProvider).device();
      final host = _host = await PairingHost.open(device);
      if (!mounted) return;
      setState(() => _step = _Step.waiting);
      final (channel, result) = await host.accept();
      if (!mounted || _host != host) {
        await channel.close();
        return;
      }
      _channel = channel;
      setState(() {
        _result = result;
        _step = _Step.compare;
      });
    } on Object catch (e) {
      _failWith(e);
    }
  }

  Future<void> _onScan(BarcodeCapture capture) async {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !raw.startsWith(PairingInvite.scheme)) return;
    _scanned = true;
    await _scanner?.stop();
    setState(() => _step = _Step.starting);
    try {
      final invite = PairingInvite.parse(raw);
      final device = await ref.read(syncLedgerProvider).device();
      final channel = _channel = SyncNetwork.channelFor(
        await SyncNetwork.connect(invite.hosts, invite.port),
      );
      final result = await Pairing.joinerHandshake(
        channel: channel,
        invite: invite,
        myId: device.id,
        myName: device.name,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.compare;
      });
    } on Object catch (e) {
      _failWith(e);
    }
  }

  Future<void> _answer({required bool match}) async {
    final channel = _channel;
    final result = _result;
    if (channel == null || result == null) return;
    setState(() => _step = _Step.confirming);
    try {
      final both = await Pairing.exchangeConfirmation(
        channel: channel,
        result: result,
        inviter: _role == _Role.show,
        accepted: match,
      );
      if (!both) {
        _failWith(SyncProtocolException(match
            ? 'The other device said the codes did not match. Nothing was '
                'saved.'
            : 'Pairing cancelled. Nothing was saved.'));
        return;
      }
      await ref.read(syncLedgerProvider).savePeer(PairedDevice(
            id: result.peerId,
            name: result.peerName,
            key: result.syncKey,
            pairedAt: ref.read(clockProvider).now(),
          ));
      ref.invalidate(pairedDevicesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired with ${result.peerName}.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      _failWith(e);
    }
  }

  void _failWith(Object e) {
    if (!mounted) return;
    unawaited(_channel?.close());
    _channel = null;
    setState(() {
      _step = _Step.failed;
      _error = e is SyncProtocolException
          ? e.message
          : 'Pairing did not finish. Check both devices are on the same '
              'Wi-Fi and try again.';
    });
  }

  void _retry() => _restart(_role);

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a device')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          if (_step != _Step.compare && _step != _Step.confirming) ...[
            AppSegmentedControl<_Role>(
              height: 44,
              segments: const [
                AppSegment(
                  value: _Role.show,
                  label: 'Show code',
                  icon: Icons.qr_code_2_rounded,
                ),
                AppSegment(
                  value: _Role.scan,
                  label: 'Scan code',
                  icon: Icons.qr_code_scanner_rounded,
                ),
              ],
              selected: _role,
              onChanged: _setRole,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _role == _Role.show
                  ? 'On your other device, open Vaultly → Settings → Sync '
                      'devices → Pair a device → Scan code, and point it at '
                      'this code. Both devices must be on the same Wi-Fi.'
                  : 'On your other device, choose Show code, then scan it '
                      'here.',
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          switch (_step) {
            _Step.starting => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            _Step.waiting when _role == _Role.show && _host != null =>
              _QrPanel(data: _host!.invite.toQr()),
            _Step.waiting => ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: _onScan,
                  ),
                ),
              ),
            _Step.compare || _Step.confirming => _SasPanel(
                sas: result!.sas,
                peerName: result.peerName,
                busy: _step == _Step.confirming,
                onMatch: () => _answer(match: true),
                onMismatch: () => _answer(match: false),
              ),
            _Step.failed => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppBanner(
                    kind: BannerKind.error,
                    icon: Icons.link_off_rounded,
                    title: 'Not paired',
                    message: _error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  VaultButton(label: 'Try again', onPressed: _retry),
                ],
              ),
          },
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return VaultCard(
      child: Column(
        children: [
          // A white quiet zone keeps the code scannable in dark mode.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: QrImageView(
              data: data,
              size: 240,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Waiting for the other device… This code works once.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SasPanel extends StatelessWidget {
  const _SasPanel({
    required this.sas,
    required this.peerName,
    required this.busy,
    required this.onMatch,
    required this.onMismatch,
  });

  final String sas;
  final String peerName;
  final bool busy;
  final VoidCallback onMatch;
  final VoidCallback onMismatch;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check the code',
          style: AppTextStyles.h2.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '$peerName should show exactly the same six digits. If they '
          'differ, someone may be interfering — choose "They differ".',
          style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            '${sas.substring(0, 3)} ${sas.substring(3)}',
            style: AppTextStyles.codeLarge.copyWith(
              color: c.textPrimary,
              fontSize: 44,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (busy) ...[
          Text(
            'Waiting for the other device…',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        VaultButton(
          label: 'Codes match',
          isLoading: busy,
          onPressed: busy ? null : onMatch,
        ),
        const SizedBox(height: AppSpacing.sm),
        VaultButton(
          label: 'They differ',
          variant: VaultButtonVariant.secondary,
          onPressed: busy ? null : onMismatch,
        ),
      ],
    );
  }
}
