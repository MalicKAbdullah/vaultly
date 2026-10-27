import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';
import 'package:vaultkey/src/features/sync/services/sync_merge.dart';

/// One sync round over an established [SecureChannel]: each side sends its
/// snapshot, both compute the same merge, and each acknowledges receipt
/// before either applies it, so neither device commits a merge the other
/// never saw.
abstract final class SyncExchange {
  static const List<int> _ack = [0x61, 0x63, 0x6b]; // "ack"

  static Future<SyncMergeResult> run(
    SecureChannel channel,
    SyncSnapshot local,
  ) async {
    final out = utf8.encode(jsonEncode(local.toJson()));
    await channel.send(out);
    out.fillRange(0, out.length, 0);

    final incoming = await channel.receive(timeout: const Duration(minutes: 2));
    final SyncSnapshot remote;
    try {
      remote = SyncSnapshot.fromJson(
        jsonDecode(utf8.decode(incoming)) as Map<String, dynamic>,
      );
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
