# Opening Vaultly fast

How Vaultly gets from a tap on the icon to the vault list with its items, and
the rules that keep that path short. The suite-wide notes (secure-storage
costs, crypto timings, the biometric prompt options) live in
secure-suite-core's `docs/PERFORMANCE.md`.

## The path

1. **Launch reads, all started at once.** `SessionNotifier.build` starts,
   in this order: the verifier read (setup or unlock?), the prompt's reads
   (lockout cooldown, biometric-enabled flag), the hardware probe, and the
   vault file read. flutter_secure_storage on Android serves calls one at a
   time in call order, so the verifier goes first; the hardware probe is a
   different plugin and runs alongside. The onboarding flag is read only
   once the session knows setup is needed (`setupOnboardingSeenProvider`),
   so it never queues ahead of the unlock reads.
2. **Prompt.** `UnlockScreen` takes the already-running futures
   (`SessionNotifier.unlockPrerequisites`) and raises the biometric prompt
   as soon as they resolve. Nothing secret is read before the prompt
   succeeds: the vault key enters Dart memory only from the released
   biometric key (or the password's Argon2id derivation).
3. **While the prompt is up.** The encrypted vault file is already in
   memory as an `EncryptedPayload` (ciphertext plus its non-secret header).
   The session keeps it read ahead whenever it is locked: at launch, on
   every lock, after an erase and after a recovery reset (which re-encrypts
   the file). A read waits for any save still in flight, so a lock in the
   middle of an edit never reads the older file.
4. **Key released → vault open.** One worker-isolate task decrypts,
   `jsonDecode`s and builds every `VaultEntry`. Only then does the session
   report `unlocked`, so `VaultNotifier.build` returns the entries
   synchronously and the vault list's first frame has them. A decrypt
   failure still unlocks and becomes `VaultNotifier`'s error state (shown
   as "Your vault could not be opened"); mutations refuse to run on it, so
   nothing saves over the file. Password unlock, setup and recovery reset
   take the same path. The worker gets a copy of the key and zeroes it
   when the task ends; the session's key is zeroed on lock.
5. **First vault frame.** Groups are `SliverRowGroup`s: core_ui's
   `RowGroup` card drawn with `DecoratedSliver` around a lazy
   `SliverList`, so only the rows on screen are built. Counts for the
   filter chips and the overview come from `vaultTallyProvider` (one pass,
   recomputed only when the vault changes). The health report is analysed
   on a worker isolate (`vaultHealthProvider`); until the first report the
   overview's health figures are skeletons laid out at their final size,
   and later re-analyses keep showing the previous report. The monthly
   notification digest awaits that same report.

Saves (encode + encrypt) also run on the worker; the file write follows.

## Timeline logs

Debug and profile builds log milestones as `vaultly.startup`
(`StartupTimeline`), in milliseconds since `main`:

- `first frame`
- `launch reads ready` — verifier, cooldown, biometric flag, hardware probe
- `prompt shown`, `key released`
- `vault decrypted in N ms` — the worker task, every unlock
- `first vault frame`

Watch them with `flutter run --profile` on a device.

## Measured

`flutter test test/perf/fast_open_benchmark_test.dart`, Apple M1 Pro,
`flutter test` (JIT, debug-mode framework), median of 7 runs after a
warm-up. The vault is `realisticVault(1000)`: about a quarter of the
passwords reused, a mix of weak and strong, a fifth with TOTP, 30 % with
notes, 0–5 history entries each, a quarter favourites. "UI isolate
blocked" is the longest gap of a 1 ms heartbeat timer on the calling
isolate, so about 1 ms is its floor.

| Work, 1,000 items | Total | UI isolate blocked |
| --- | --- | --- |
| Decrypt + parse, on the UI isolate | 41.5 ms | 41.3 ms |
| Decrypt + parse, worker isolate (now) | 41.6 ms | 1.3 ms |
| Health, naive, UI isolate | 2.1 ms | 2.1 ms |
| Health, memoised per password, UI isolate | 1.1 ms | 1.1 ms |
| Health, memoised, worker isolate (now) | 1.3 ms | 1.2 ms |

| First vault-list frame (`pumpWidget`), 1,000 items | Time | Rows built |
| --- | --- | --- |
| Eager `RowGroup` in a `SliverToBoxAdapter` | 1,722 ms | 1,000 |
| Lazy `SliverRowGroup` (now) | 39.6 ms | 13 |
| Whole `VaultListScreen` (now) | 22.3 ms | — |

The overview also estimated every password's strength on each build of the
vault tab (2.3 ms per build at 1,000 items); it now reads the strong count
from the health report.

The test harness lays text out with the Ahem font in a debug-mode JIT
framework, so absolute frame times are higher than on a release build;
the ratio is what carries over. The decrypt figure is JIT on an M1 Pro;
expect roughly ×4 on a mid-range Android phone in release mode, all of it
now off the UI isolate.

## Rendering parity

`SliverRowGroup` paints the fill behind its rows and the hairline edge in
front of them, as `RowGroup`'s `Material` does, and clips only the first
and last rows to the rounded corners. The gallery renders
(`GALLERY=<dir> flutter test test/gallery`) of the vault tab match the
`RowGroup` renders except for anti-aliasing at the group corners, at most
6/255 per channel.
