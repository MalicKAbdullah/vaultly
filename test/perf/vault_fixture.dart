import 'dart:math';

import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// A realistic invented vault: about a quarter of the passwords reused, a
/// mix of weak and strong ones, some two-factor codes and notes, 0–5 old
/// passwords per entry, a quarter favourites, ages spread over five years.
/// Seeded, so every run builds the same vault.
List<VaultEntry> realisticVault(int count, {int seed = 7}) {
  final rng = Random(seed);
  const sites = [
    'GitHub', 'Gmail', 'Netflix', 'Figma', 'Daraz', 'Amazon', 'Spotify',
    'Slack', 'Dropbox', 'Notion', 'Steam', 'PayPal', 'Reddit', 'Twitch',
    'Zoom', 'Airbnb', 'Uber', 'LinkedIn', 'Trello', 'Discord', //
  ];
  const weak = ['summer2019', 'password1', 'qwerty123', 'letmein', 'abc12345'];
  const symbols = r'!@#$%^&*?';
  final now = DateTime(2026, 10, 20);

  String strong() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final length = 12 + rng.nextInt(9);
    return [
      for (var i = 0; i < length; i++)
        i % 5 == 4
            ? symbols[rng.nextInt(symbols.length)]
            : chars[rng.nextInt(chars.length)],
    ].join();
  }

  final shared = [for (var i = 0; i < 40; i++) strong()];
  final entries = <VaultEntry>[];
  for (var i = 0; i < count; i++) {
    final site = sites[rng.nextInt(sites.length)];
    final roll = rng.nextDouble();
    final category = roll < 0.8
        ? EntryCategory.login
        : roll < 0.88
            ? EntryCategory.card
            : roll < 0.94
                ? EntryCategory.identity
                : EntryCategory.note;
    final pick = rng.nextDouble();
    final password = category == EntryCategory.note
        ? ''
        : pick < 0.25
            ? shared[rng.nextInt(shared.length)]
            : pick < 0.4
                ? '${weak[rng.nextInt(weak.length)]}${rng.nextInt(100)}'
                : strong();
    final created = now.subtract(Duration(days: rng.nextInt(5 * 365)));
    final updated = created.add(
      Duration(days: rng.nextInt(now.difference(created).inDays + 1)),
    );
    entries.add(
      VaultEntry(
        id: 'entry-$i',
        title: rng.nextBool() ? '$site ${i % 7}' : site.toLowerCase(),
        username: rng.nextDouble() < 0.9 ? 'user$i@example.com' : '',
        password: password,
        url: '${site.toLowerCase()}.example',
        notes: rng.nextDouble() < 0.3
            ? 'Security questions are in the safe. Account opened '
                'for project $i; recovery codes printed and filed.'
            : '',
        category: category,
        favorite: rng.nextDouble() < 0.25,
        totp: rng.nextDouble() < 0.2
            ? const TotpConfig(secret: 'JBSWY3DPEHPK3PXP')
            : null,
        createdAt: created,
        updatedAt: updated,
        passwordChangedAt: updated,
        history: [
          for (var h = rng.nextInt(6); h > 0; h--)
            PasswordHistoryEntry(
              password: strong(),
              replacedAt: updated.subtract(Duration(days: 30 * h)),
            ),
        ],
      ),
    );
  }
  return entries;
}
