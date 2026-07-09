<div align="center">

# 🔐 Vaultly

### A password manager you actually own.

Master-password + biometric unlock, one-tap autofill, and 2FA codes — all offline, all yours.

![License](https://img.shields.io/badge/License-MIT-059669?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-059669?style=flat-square)
![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-027DFD?style=flat-square&logo=flutter)
![Privacy](https://img.shields.io/badge/Data-Offline%20%26%20Encrypted-34D399?style=flat-square)
![Trackers](https://img.shields.io/badge/Trackers-0-34D399?style=flat-square)

</div>

> ### 🔒 Private by design
> Vaultly works **completely offline**. Your passwords are **encrypted on your device and never leave it** — no account, no cloud, no servers, no tracking. You hold the only key.

Most password managers ask you to trust their servers with your entire digital life. Vaultly doesn't have servers. Everything stays on your phone, encrypted, and you decide if and where your backups go — including your own cloud folder.

## ✨ Features

**Unlock & fill**
- One **master password**, with optional **fingerprint / face** unlock
- **Android Autofill** — sign in to other apps *and to websites in your browser* with a tap
- Built-in **two-factor (TOTP) codes** — your 2FA lives next to your password

**Everything organised**
- Logins, cards, notes and identities, with favorites and per-entry **password history**
- Instant search, filters, and sorting
- A strong **password generator** with a live strength meter

**Stay secure over time**
- **Vault Health** dashboard flags weak, reused, and old passwords
- Copied passwords auto-clear from the clipboard after 30 seconds
- Screenshot protection and auto-lock

**Never lose access**
- **Encrypted backup & restore** you can export anywhere
- **Scheduled auto-backup** to any folder — including a Google Drive folder, so you can restore on a new phone

## 🔓 Autofill: what works where

Vaultly registers as an Android **Autofill Service** (Android 8 / API 26+). When a
login form appears, Vaultly offers *"Unlock Vaultly to fill"*; you unlock once and
pick the matching entry, and the credentials are written straight into the form.

**Browser web forms are supported alongside native app forms.** When the login
form lives inside a browser (Chrome and other Autofill-integrated browsers), the
browser reports the page's **web domain** to the Autofill Framework. Vaultly:

- extracts that web domain from the `AssistStructure` (`ViewNode.getWebDomain()`),
  walking the whole node tree, and passes it to the entry picker;
- reads the HTML of each `<input>` (`ViewNode.getHtmlInfo()`) — the `type` and
  `autocomplete` attributes plus `name`/`id` — so password and username fields are
  detected even when a website sets no Android autofill hints;
- ranks vault entries by **host / domain match** (e.g. `accounts.google.com` matches
  a `google.com` entry), and deliberately ignores the *browser's own* package name
  (`com.android.chrome`, `org.mozilla.firefox`, …) so the browser never becomes the
  match signal — the site's domain does.

| Source | Autofill support |
| :-- | :-- |
| **Android — native app login forms** | ✅ Supported (Autofill Framework, API 26+) |
| **Android — web login forms in a browser** | ✅ Supported (matched by the page's web domain) |
| **iOS — apps & Safari** | ❌ Not supported (see below) |

> **iOS note (future work).** iOS autofill is *not* implemented. It would require an
> `ASCredentialProviderExtension` (a separate app extension using the
> AuthenticationServices framework) rather than the Android Autofill Service, so it is
> tracked as future work. Everything else in Vaultly runs on iOS.
>
> **Scope.** *Save* requests (offering to capture a brand-new login) are intentionally
> out of scope — Vaultly only fills existing entries; you add new ones yourself.

## 🔒 Privacy & Security

- **Offline-only.** No network code, nothing to leak.
- **Unlocked by you.** Your data key is derived from your master password with **Argon2id** (brute-force-resistant), held only in memory while unlocked and wiped on lock.
- **Encrypted at rest.** The vault is stored as a single file encrypted with **AES-256-GCM**.
- **Your backups, your key.** Backups are encrypted with a separate passphrase — a backup file alone is useless to anyone else.
- **No accounts, no telemetry, no ads.**

## 📸 Screenshots

| Vault | Entry & 2FA | Generator | Vault Health |
| :---: | :---: | :---: | :---: |
| _coming soon_ | _coming soon_ | _coming soon_ | _coming soon_ |

## 🚀 Getting Started

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) and Android Studio / Xcode.

```sh
# 1. Clone
git clone https://github.com/MalicKAbdullah/vaultly.git
cd vaultly

# 2. Install dependencies (also fetches secure-suite-core)
flutter pub get

# 3. Run on a connected device or emulator
flutter run
```

**Build a release APK:**

```sh
flutter build apk --release
```

Run the checks the way CI does:

```sh
flutter analyze
flutter test
```

## 🧱 Built With

- **Flutter** & **Dart** — one codebase, Android & iOS
- **Riverpod** (state) · **go_router** (navigation) · **local_auth** (biometrics) · native **Autofill Service**
- [**secure-suite-core**](https://github.com/MalicKAbdullah/secure-suite-core) — shared encryption, storage & design system

## 📄 License

[MIT](LICENSE) © 2026 Abdullah Malik — part of the [Secure Suite](https://github.com/MalicKAbdullah/secure-suite-core).
