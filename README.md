# Vaultly

An offline, encrypted password manager for Android and iOS. Your passwords live only on your device — Vaultly has no accounts, no servers, and never connects to the internet.

## Features

- **Master password** — one password protects everything, set up on first run with a live strength meter.
- **First-run intro** — three quick, skippable pages explain the app before the master password is created (shown once).
- **Two-factor codes (TOTP)** — store an account's 2FA secret next to its password and read the live 6-digit code right in the app.
- **Android Autofill** — Vaultly can be the phone's autofill provider: login forms in other apps and browsers offer "Unlock Vaultly to fill".
- **Biometric unlock** — optional fingerprint / face unlock once the vault exists.
- **Escalating cooldown** — repeated wrong passwords trigger a growing lockout timer.
- **Auto-lock** — the vault locks when the app goes to the background and after a configurable period of inactivity (any touch resets the timer).
- **Entries** — title, username, password, URL, notes; categories (login, card, note, identity, other) and favorites; full password history per entry.
- **Search, filter, sort** — instant search, category/favorite filters, sort by recent or A–Z.
- **Reveal & copy** — passwords are hidden by default; copied secrets are wiped from the clipboard after 30 seconds.
- **Password generator** — a dedicated tab and an inline panel in the entry editor: length, character classes, strength estimate.
- **Vault Health** — a dashboard that scores your vault and lists weak, reused, and old (unchanged for 1+ year) passwords.
- **Encrypted backups** — export/import a passphrase-protected `.vkbackup` file; restore by merging into or replacing the current vault.
- **CSV** — import from a browser/manager CSV export; plain CSV export is available behind an explicit warning.
- **Scheduled auto-backup** — off / daily / weekly / monthly to a folder you pick, with "Back up now" and last-backup status.
- **Change master password** — re-encrypts the whole vault with a freshly derived key.
- **Erase all data** — type-to-confirm wipe of every entry, key, and setting.
- **Screenshot protection** — `FLAG_SECURE` on Android blocks screenshots and hides the app in the recents switcher.

## Architecture

```
lib/
  main.dart                  # ProviderScope + app bootstrap
  src/
    app.dart                 # MaterialApp.router, theme, InactivityLocker
    core/
      di.dart                # composition root (Riverpod providers)
      router/                # go_router with auth-state redirects
      security/              # InactivityLocker (background + idle lock)
      services/              # ClipboardGuard (30 s auto-clear)
      interfaces/            # IVaultFileStore, IKeyDerivation, IBackupFolder, IAutofillBridge
      shell/                 # bottom-nav home shell
    features/
      auth/                  # onboarding intro, setup, unlock, master auth, biometrics
      vault/                 # entry model, encrypted repository, CRUD screens
      totp/                  # TOTP generator, otpauth parser, live code card
      autofill/              # entry matcher + picker for Android Autofill
      generator/             # password generator + strength estimator
      health/                # vault health analyzer + dashboard
      backup/                # .vkbackup codec, CSV codec, merge, auto-backup
      settings/              # settings, change master password, auto-backup UI
```

- **State**: Riverpod. `di.dart` is the single composition root; every platform-touching dependency (secure storage, file store, key derivation, clock, clipboard, biometrics, backup folder, autofill bridge) sits behind a small interface so tests swap in in-memory fakes — no platform channels in tests.
- **Navigation**: go_router with a redirect driven by the session state (`needsSetup` → intro pages once, then setup; `locked` → unlock; `unlocked` → vault, or the autofill picker when answering another app's fill request). A `StatefulShellRoute` hosts the four tabs (Vault, Generator, Health, Settings).
- **Autofill split**: the Kotlin side (`VaultlyAutofillService`, `MainActivity`) only parses the form and moves parcels; all entry matching/ranking is `AutofillMatcher` in Dart, fully unit-tested.
- **Shared packages**: `core_crypto` (AES-GCM cipher + Argon2id KDF), `core_storage` (secure storage wrapper), `core_security` (lifecycle lock service), `core_theme`, `core_ui` (from `../../packages`).

## Security model

- **Key derivation**: the vault key is derived from the master password with **Argon2id** and a per-install random salt. The master password itself is never stored anywhere.
- **Verification**: correctness is checked by decrypting a known sentinel encrypted with the derived key — AES-GCM authentication makes a wrong key fail loudly, so there is no password hash to attack.
- **Vault at rest**: the entire entry list is one JSON document encrypted with **AES-256-GCM** and written atomically to a single file in app-private storage. Any tampering fails GCM authentication. Decrypted data exists only in memory while the vault is unlocked.
- **Session**: the decrypted vault key lives only inside the session notifier and is dropped on lock (background, inactivity timeout, or manual lock).
- **Biometrics**: enabling biometric unlock keeps the derived vault key in the OS keystore-backed secure storage, gated behind the platform biometric prompt (`local_auth`). Disabling it (or changing the master password) deletes that copy.
- **Brute force**: failed unlock attempts are counted; past a threshold each further failure starts an escalating lockout that persists across restarts.
- **Backups**: `.vkbackup` files are a small JSON envelope (format id, version, Argon2id salt, AES-GCM nonce + ciphertext). The content is encrypted with a **separate backup passphrase**, so a leaked backup is useless without it. Entry counts and dates are readable without the passphrase for preview.
- **Clipboard**: copied secrets are cleared after 30 seconds (only if the clipboard still holds what Vaultly put there).
- **Android**: `FLAG_SECURE` is set in `MainActivity`, blocking screenshots and recents previews.
- **Network**: the app declares no internet permission and makes no network calls.

## Two-factor codes (TOTP)

Many sites offer "authenticator app" two-factor login. Vaultly can be that authenticator, so the password and its rolling code live in one place:

1. On the site, choose to set up an authenticator app. It shows a QR code and, behind a "can't scan?" link, a **setup key** or an `otpauth://` link.
2. In Vaultly, edit the site's entry and paste either one into **Two-factor authentication (TOTP)**. Both the bare secret (spaces/lowercase fine) and the full link are accepted; non-standard settings (8 digits, 60 s period, SHA-256) come along automatically from the link.
3. Save. The entry now shows a live code with a countdown ring on its detail screen — tap the code to copy it (it clears from the clipboard after 30 seconds). Entries with a code show a small **2FA** badge in the vault list.

TOTP secrets are part of the entry, so they are included in encrypted `.vkbackup` exports/imports and in CSV exports (as an `otpauth://` link in the `totp` column) automatically. Codes are computed on-device from the stored secret (RFC 6238); no network involved.

## Android Autofill

Vaultly can fill logins into other apps and mobile browsers, no copy-paste needed:

1. Open **Settings → Autofill** in Vaultly and tap **Turn on in system settings** (or go to Android Settings → Passwords & accounts → Autofill service) and pick **Vaultly**.
2. Tap a login form in any app or website. The suggestion **"Unlock Vaultly to fill"** appears above the keyboard.
3. Tap it, unlock with your master password or biometrics, and pick the entry. Vaultly pre-selects entries whose website or name matches the app/site asking; search covers the whole vault. The form is filled in one tap and Vaultly closes itself.

Notes:

- Requires Android 8.0 or newer. The Settings card only appears on devices that support autofill.
- Vaultly never fills anything silently — every fill goes through the unlock screen first.
- Saving new logins from autofill (save prompts) is not part of this version; add entries inside Vaultly.

## Backup & restore

### Manual export

Settings → Export offers:

- **Encrypted backup (`.vkbackup`)** — recommended. Choose a passphrase (min 8 chars); share the file or save it anywhere.
- **Plain CSV** — every password in readable text, for migrating away. Shown behind an explicit warning.

### Restore / import

Settings → Import accepts:

- **`.vkbackup`** — enter the backup's passphrase, then choose **Merge** (newer entry wins per id, nothing is deleted) or **Replace** (the backup becomes the vault).
- **CSV** — standard `name,url,username,password,note` columns (Chrome/most managers' export format). A `totp` / `login_totp` column (otpauth link or bare secret) is picked up too, so Bitwarden-style exports bring their 2FA secrets along.

### Scheduled auto-backup

Settings → Auto-backup: pick **daily / weekly / monthly**, set a backup passphrase, and choose a destination folder. Whenever you unlock the vault and a backup is due, Vaultly quietly writes `Vaultly-backup-YYYY-MM-DD.vkbackup` to that folder. "Back up now" forces one immediately, and the status line shows when the last backup happened (or why it failed).

**Syncing to Google Drive**: on Android the folder is chosen with the system (SAF) folder picker. If you have the Google Drive app installed, pick a folder *inside Drive* in that picker — every scheduled backup is then written straight into Drive and synced by the Drive app. The same works with other storage providers that appear in the picker. Vaultly itself still never touches the network; the provider app does the syncing.

## Running & testing

```sh
flutter pub get

# run on a connected device / emulator
flutter run

# static analysis
dart analyze

# tests (pure Dart + widget tests, no device needed)
flutter test

# debug APK
flutter build apk --debug

# regenerate launcher icons after changing assets/icon/
dart run flutter_launcher_icons
```

Notes:

- Android biometric unlock requires `FlutterFragmentActivity` (already configured in `MainActivity.kt`).
- The internal package name stays `vaultkey` (Dart package, `applicationId dev.abdullah.vaultkey`, `.vkbackup` extension and backup format id) so existing installs and old exports keep working — only the user-facing brand is **Vaultly**.
