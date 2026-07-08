/// Secure-storage keys used by Vaultly. Namespaced to avoid clashing with
/// sibling apps that share the core packages.
abstract final class VaultKeyKeys {
  static const String salt = 'vaultkey_salt';
  static const String verifier = 'vaultkey_verifier';
  static const String failedAttempts = 'vaultkey_failed_attempts';
  static const String lockoutUntil = 'vaultkey_lockout_until';
  static const String biometricEnabled = 'vaultkey_biometric_enabled';
  static const String biometricKey = 'vaultkey_biometric_key';
  static const String autoLockSeconds = 'vaultkey_auto_lock_seconds';
  static const String backupInterval = 'vaultkey_backup_interval';
  static const String backupFolderUri = 'vaultkey_backup_folder_uri';
  static const String backupFolderName = 'vaultkey_backup_folder_name';
  static const String backupPassphrase = 'vaultkey_backup_passphrase';
  static const String backupLastAt = 'vaultkey_backup_last_at';
  static const String backupLastError = 'vaultkey_backup_last_error';
  static const String onboardingDone = 'vaultkey_onboarding_done';

  static const List<String> all = [
    salt,
    verifier,
    failedAttempts,
    lockoutUntil,
    biometricEnabled,
    biometricKey,
    autoLockSeconds,
    backupInterval,
    backupFolderUri,
    backupFolderName,
    backupPassphrase,
    backupLastAt,
    backupLastError,
    onboardingDone,
  ];
}
