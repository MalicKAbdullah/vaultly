import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';

/// Auto-lock choices offered in Settings.
const List<Duration> autoLockChoices = [
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
];

const Duration defaultAutoLock = Duration(minutes: 2);

/// Inactivity timeout before the vault locks itself.
final autoLockProvider = NotifierProvider<AutoLockNotifier, Duration>(
  AutoLockNotifier.new,
);

final class AutoLockNotifier extends Notifier<Duration> {
  @override
  Duration build() {
    Future.microtask(_load);
    return defaultAutoLock;
  }

  Future<void> _load() async {
    final raw = await ref
        .read(secureStorageProvider)
        .read(key: VaultKeyKeys.autoLockSeconds);
    if (raw != null) {
      state = Duration(seconds: int.parse(raw));
    }
  }

  Future<void> set(Duration duration) async {
    state = duration;
    await ref.read(secureStorageProvider).write(
          key: VaultKeyKeys.autoLockSeconds,
          value: duration.inSeconds.toString(),
        );
  }
}

/// Whether biometric unlock is enabled (and whether the device supports it).
final biometricStateProvider =
    AsyncNotifierProvider<BiometricStateNotifier, BiometricState>(
  BiometricStateNotifier.new,
);

final class BiometricState {
  const BiometricState({required this.supported, required this.enabled});

  final bool supported;
  final bool enabled;
}

final class BiometricStateNotifier extends AsyncNotifier<BiometricState> {
  @override
  Future<BiometricState> build() async {
    final service = ref.read(biometricServiceProvider);
    return BiometricState(
      supported: await service.isSupported(),
      enabled: await service.isEnabled(),
    );
  }

  /// Enables biometric unlock using the current session key. Returns false
  /// when the platform prompt was cancelled.
  Future<bool> enable() async {
    final service = ref.read(biometricServiceProvider);
    final authenticator = ref.read(biometricAuthenticatorProvider);
    final confirmed =
        await authenticator.authenticate('Confirm to enable biometric unlock');
    if (!confirmed) return false;
    await service.enable(ref.read(sessionProvider.notifier).vaultKey);
    ref.invalidateSelf();
    return true;
  }

  Future<void> disable() async {
    await ref.read(biometricServiceProvider).disable();
    ref.invalidateSelf();
  }
}
