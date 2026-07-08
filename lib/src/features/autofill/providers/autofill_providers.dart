import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The fill request this launch should answer (null on a normal launch).
/// The router sends unlocked sessions to the picker while this is set.
final autofillRequestProvider =
    AsyncNotifierProvider<AutofillRequestNotifier, AutofillFillRequest?>(
  AutofillRequestNotifier.new,
);

final class AutofillRequestNotifier
    extends AsyncNotifier<AutofillFillRequest?> {
  @override
  Future<AutofillFillRequest?> build() =>
      ref.read(autofillBridgeProvider).pendingRequest();

  /// Fills the form with [entry]'s credentials; Android closes Vaultly.
  Future<void> complete(VaultEntry entry) async {
    await ref.read(autofillBridgeProvider).complete(
          username: entry.username,
          password: entry.password,
          label: entry.title,
        );
    state = const AsyncData(null);
  }

  /// Abandons the fill request; Android closes Vaultly.
  Future<void> cancel() async {
    await ref.read(autofillBridgeProvider).cancel();
    state = const AsyncData(null);
  }
}

/// Whether autofill is available on this device and whether Vaultly is the
/// active provider (drives the Settings card).
typedef AutofillStatus = ({bool supported, bool enabled});

final autofillStatusProvider = FutureProvider<AutofillStatus>((ref) async {
  final bridge = ref.watch(autofillBridgeProvider);
  final supported = await bridge.isSupported();
  return (
    supported: supported,
    enabled: supported && await bridge.isEnabled(),
  );
});
