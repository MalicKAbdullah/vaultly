import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';
import 'package:vaultkey/src/features/sync/services/sync_merge.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';

/// One sync round over an established [SecureChannel]: each side sends its
/// snapshot, both compute the same merge, and each acknowledges receipt
/// before either applies it, so neither device commits a merge the other
/// never saw.
///
/// Each snapshot names its vault format. Both devices must be on the same
/// one: an older Vaultly drops fields it does not know when it rewrites an
/// entry, so syncing with it would erase them. On a mismatch this device
/// stops before acknowledging, so neither side applies anything.
abstract final class SyncExchange {
  static const List<int> _ack = [0x61, 0x63, 0x6b]; // "ack"

  static const peerTooOld = SyncProtocolException(
    'The other phone has an older Vaultly. Update Vaultly on it, then sync '
    'again.',
  );

  static const selfTooOld = SyncProtocolException(
    'The other phone has a newer Vaultly. Update Vaultly on this phone, then '
    'sync again.',
  );

  static Future<SyncMergeResult> run(
    SecureChannel channel,
    SyncSnapshot local,
  ) async {
    final out = utf8.encode(jsonEncode({
      'format': VaultRepository.formatVersion,
      ...local.toJson(),
    }));
    await channel.send(out);
    out.fillRange(0, out.length, 0);

    final incoming = await channel.receive(timeout: const Duration(minutes: 2));
    final SyncSnapshot remote;
    try {
      final json = jsonDecode(utf8.decode(incoming)) as Map<String, dynamic>;
      // Vaultly before format 2 sent no format number.
      final format = json.containsKey('format') ? json['format'] as int : 1;
      if (format < VaultRepository.formatVersion) throw peerTooOld;
      if (format > VaultRepository.formatVersion) throw selfTooOld;
      remote = SyncSnapshot.fromJson(json);
    } on SyncProtocolException {
      rethrow;
    } on Object {
      throw const SyncProtocolException('The other device sent bad data.');
    } finally {
      _wipe(incoming);
    }

    final result = SyncMerge.merge(local: local, remote: remote);
    await channel.send(_ack);
    final ack = await channel.receive();
    if (!SyncPrimitives.equal(ack, _ack)) {
      throw const SyncProtocolException('The other device sent bad data.');
    }
    return result;
  }

  static void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
