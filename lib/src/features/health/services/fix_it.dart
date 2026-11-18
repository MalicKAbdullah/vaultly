import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/health/services/change_password_url.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The entry the user set out to repair, in memory only. The save screen
/// uses it so a changed password goes to exactly this entry even when
/// other accounts share the site.
final class FixTarget {
  const FixTarget({
    required this.entryId,
    required this.host,
    required this.expiresAt,
  });

  final String entryId;
  final String host;
  final DateTime expiresAt;

  /// How long after tapping "Change password" a submitted login still counts
  /// as that fix.
  static const Duration lifetime = Duration(minutes: 15);
}

final fixTargetProvider = StateProvider<FixTarget?>((_) => null);

/// "Change password" on a Vault Health row: keeps the entry ready to fill
/// (its current password is the first thing the site asks for), remembers it
/// as the fix target, and opens the site's change-password page. Returns
/// false for an entry with no website.
Future<bool> startFix(WidgetRef ref, VaultEntry entry) async {
  final url = ChangePasswordUrl.forEntry(entry.url);
  if (url == null) return false;
  final totp = entry.totp;
  await ref.read(fillSessionBridgeProvider).arm(
        entryId: entry.id,
        title: entry.title,
        username: entry.username,
        password: entry.password,
        url: entry.url,
        totp: totp == null
            ? null
            : {
                'secret': totp.secret,
                'algorithm': totp.algorithm.label,
                'digits': totp.digits,
                'period': totp.period,
              },
      );
  ref.read(fixTargetProvider.notifier).state = FixTarget(
    entryId: entry.id,
    host: url.host,
    expiresAt: ref.read(clockProvider).now().add(FixTarget.lifetime),
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
  return true;
}
