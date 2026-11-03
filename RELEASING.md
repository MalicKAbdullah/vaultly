# Releasing

This app ships **signed APKs** to GitHub Releases automatically via the
[`Release`](.github/workflows/release.yml) workflow.

## Cut a release

1. Bump the version in `pubspec.yaml` (e.g. `version: 1.3.0+6`) and commit it
   (via a PR, since `main` is protected).
2. Create and push a matching tag:

   ```sh
   git tag v1.3.0
   git push origin v1.3.0
   ```

3. The workflow builds signed APKs (universal + `arm64-v8a` + `armeabi-v7a` +
   `x86_64`) and publishes a **GitHub Release** for the tag with auto-generated
   notes. Most phones want the `arm64-v8a` APK; grab `universal` if unsure.

You can also run it manually: **Actions → Release → Run workflow** (with an
optional version label).

## Signing

Release builds are signed with the shared Secure Suite keystore, stored as
**encrypted repository secrets** (never in the repo, never printed in logs):

| Secret | Purpose |
| --- | --- |
| `KEYSTORE_BASE64` | The base64-encoded release keystore |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_PASSWORD` | Key password |
| `KEY_ALIAS` | Key alias |

At build time the workflow decodes the keystore, writes `android/key.properties`,
builds, and then deletes both. Locally, `flutter build apk --release` falls back
to debug signing unless you create your own `android/key.properties`.

> ⚠️ Keep the keystore and its password backed up somewhere safe. Losing them
> means you can never ship an update that installs over an existing release build.

## Store builds

F-Droid and IzzyOnDroid ship their own updates, so their builds leave out
Vaultly's GitHub update check:

```sh
flutter build apk --release --dart-define=OFFLYNE_STORE=fdroid
```

With `OFFLYNE_STORE` set, the update check never runs and the *Updates*
section in Settings and the home-screen update banner are not built. Without
it (the GitHub Release APKs above) the update check is present. Store
listing text, icon, feature graphic, screenshots and per-version changelogs
live in `fastlane/metadata/android/en-US/`; add
`changelogs/<versionCode>.txt` for every release (the `+N` in
`pubspec.yaml`'s `version:`).

## Versioning

Tags are `vMAJOR.MINOR.PATCH` and should match the `version:` in `pubspec.yaml`.
