import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';

/// What the inviting device's QR code carries: who it is, its pairing
/// public key, a one-time secret, and where to reach it.
@immutable
final class PairingInvite {
  const PairingInvite({
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    required this.secret,
    required this.hosts,
    required this.port,
  });

  factory PairingInvite.parse(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text.trim());
    } on FormatException {
      throw _notInvite;
    }
    if (uri.scheme != scheme || uri.host != 'v1') throw _notInvite;
    final q = uri.queryParameters;
    try {
      final invite = PairingInvite(
        deviceId: q['d']!,
        deviceName: q['n'] ?? 'Vaultly device',
        publicKey: base64Url.decode(base64Url.normalize(q['k']!)),
        secret: base64Url.decode(base64Url.normalize(q['s']!)),
        hosts: q['h']!.split(',').where((h) => h.isNotEmpty).toList(),
        port: int.parse(q['p']!),
      );
      if (invite.publicKey.length != 32 ||
          invite.secret.length != 32 ||
          invite.hosts.isEmpty) {
        throw _notInvite;
      }
      return invite;
    } on SyncProtocolException {
      rethrow;
    } on Object {
      throw _notInvite;
    }
  }

  static const String scheme = 'vaultly-pair';
  static const _notInvite = SyncProtocolException(
    'That is not a Vaultly pairing code.',
  );

  final String deviceId;
  final String deviceName;
  final Uint8List publicKey;

  /// 32 random bytes, used once: only a device that scanned the code can
  /// prove it knows them.
  final Uint8List secret;
  final List<String> hosts;
  final int port;

  String toQr() => Uri(
        scheme: scheme,
        host: 'v1',
        queryParameters: {
          'd': deviceId,
          'n': deviceName,
          'k': base64Url.encode(publicKey),
          's': base64Url.encode(secret),
          'h': hosts.join(','),
          'p': '$port',
        },
      ).toString();
}

/// Keys agreed during pairing.
@immutable
final class PairingResult {
  const PairingResult({
    required this.peerId,
    required this.peerName,
    required this.syncKey,
    required this.sas,
    required this.confirmInviter,
    required this.confirmJoiner,
  });

  final String peerId;
  final String peerName;

  /// The long-term key both devices store for later syncs.
  final Uint8List syncKey;

  /// Six digits both screens show; matching proves no one sits in between.
  final String sas;
  final Uint8List confirmInviter;
  final Uint8List confirmJoiner;
}

/// Pairing: X25519 between the inviter's QR key and the joiner's fresh key,
/// HKDF-SHA256 salted with the QR's one-time secret and bound to both
/// identities, then mutual key confirmation and a 6-digit SAS.
///
/// Messages (plain frames; every claim is MAC'd):
/// 1. joiner → inviter: id, name, public key, HMAC(secret, joiner key ‖ id)
/// 2. inviter → joiner: name, HMAC(confirmInviter, transcript)
/// 3. joiner → inviter: HMAC(confirmJoiner, transcript)
/// 4. both, after the user compares the SAS: confirm/cancel, MAC'd with the
///    sender's confirm key.
abstract final class Pairing {
  static const String _info = 'vaultly-pair-v1';

  /// Inviter side, after a joiner connected to the advertised port.
  static Future<PairingResult> inviterHandshake({
    required FrameChannel channel,
    required SimpleKeyPair keyPair,
    required PairingInvite invite,
  }) async {
    final hello = _json(await channel.receive());
    final joinerId = _string(hello, 'id');
    final joinerName = _string(hello, 'name');
    final joinerPub = _bytes(hello, 'k');
    final proof = _bytes(hello, 'proof');
    final expected = await SyncPrimitives.mac(
      invite.secret,
      [...joinerPub, ...utf8.encode(joinerId)],
    );
    if (!SyncPrimitives.equal(proof, expected)) {
      throw const SyncProtocolException(
        'That device did not scan this code. Show a new code and try again.',
      );
    }
    final result = await _derive(
      mine: keyPair,
      theirPub: joinerPub,
      secret: invite.secret,
      inviterId: invite.deviceId,
      inviterPub: invite.publicKey,
      joinerId: joinerId,
      joinerPub: joinerPub,
      peerId: joinerId,
      peerName: joinerName,
    );
    final transcript = _transcript(invite.publicKey, joinerPub);
    channel.send(utf8.encode(jsonEncode({
      'name': invite.deviceName,
      'mac': base64.encode(
        await SyncPrimitives.mac(result.confirmInviter, transcript),
      ),
    })));
    final reply = _json(await channel.receive());
    final joinerMac = _bytes(reply, 'mac');
    if (!SyncPrimitives.equal(
      joinerMac,
      await SyncPrimitives.mac(result.confirmJoiner, transcript),
    )) {
      throw _mismatch;
    }
    return result;
  }

  /// Joiner side, after connecting to one of [PairingInvite.hosts].
  static Future<PairingResult> joinerHandshake({
    required FrameChannel channel,
    required PairingInvite invite,
    required String myId,
    required String myName,
  }) async {
    final keyPair = await SyncPrimitives.x25519.newKeyPair();
    final myPub = await SyncPrimitives.publicKeyOf(keyPair);
    channel.send(utf8.encode(jsonEncode({
      'id': myId,
      'name': myName,
      'k': base64.encode(myPub),
      'proof': base64.encode(
        await SyncPrimitives.mac(
            invite.secret, [...myPub, ...utf8.encode(myId)]),
      ),
    })));
    final reply = _json(await channel.receive());
    final result = await _derive(
      mine: keyPair,
      theirPub: invite.publicKey,
      secret: invite.secret,
      inviterId: invite.deviceId,
      inviterPub: invite.publicKey,
      joinerId: myId,
      joinerPub: myPub,
      peerId: invite.deviceId,
      peerName: _string(reply, 'name'),
    );
    final transcript = _transcript(invite.publicKey, myPub);
    if (!SyncPrimitives.equal(
      _bytes(reply, 'mac'),
      await SyncPrimitives.mac(result.confirmInviter, transcript),
    )) {
      throw _mismatch;
    }
    channel.send(utf8.encode(jsonEncode({
      'mac': base64.encode(
        await SyncPrimitives.mac(result.confirmJoiner, transcript),
      ),
    })));
    return result;
  }

  /// Exchanges the users' SAS verdicts. Returns true only when both people
  /// confirmed the codes match.
  static Future<bool> exchangeConfirmation({
    required FrameChannel channel,
    required PairingResult result,
    required bool inviter,
    required bool accepted,
  }) async {
    final mine = inviter ? result.confirmInviter : result.confirmJoiner;
    final theirs = inviter ? result.confirmJoiner : result.confirmInviter;
    final verdict = accepted ? 'match' : 'cancel';
    channel.send(utf8.encode(jsonEncode({
      'verdict': verdict,
      'mac':
          base64.encode(await SyncPrimitives.mac(mine, utf8.encode(verdict))),
    })));
    if (!accepted) return false;
    // The other person may take a while to compare the codes.
    final reply = _json(
      await channel.receive(timeout: const Duration(minutes: 3)),
    );
    final theirVerdict = _string(reply, 'verdict');
    final ok = SyncPrimitives.equal(
      _bytes(reply, 'mac'),
      await SyncPrimitives.mac(theirs, utf8.encode(theirVerdict)),
    );
    if (!ok) throw _mismatch;
    return theirVerdict == 'match';
  }

  static Future<PairingResult> _derive({
    required SimpleKeyPair mine,
    required List<int> theirPub,
    required List<int> secret,
    required String inviterId,
    required List<int> inviterPub,
    required String joinerId,
    required List<int> joinerPub,
    required String peerId,
    required String peerName,
  }) async {
    final shared = await SyncPrimitives.dh(mine, theirPub);
    final okm = await SyncPrimitives.hkdf(
      ikm: shared,
      salt: secret,
      info: [
        ...utf8.encode(_info),
        ...inviterPub,
        ...joinerPub,
        ...utf8.encode(inviterId),
        0,
        ...utf8.encode(joinerId),
      ],
      length: 32 + 32 + 32 + 4,
    );
    shared.fillRange(0, shared.length, 0);
    final sasNumber = ByteData.sublistView(okm, 96, 100).getUint32(0) % 1000000;
    return PairingResult(
      peerId: peerId,
      peerName: peerName,
      syncKey: Uint8List.fromList(okm.sublist(0, 32)),
      confirmInviter: Uint8List.fromList(okm.sublist(32, 64)),
      confirmJoiner: Uint8List.fromList(okm.sublist(64, 96)),
      sas: sasNumber.toString().padLeft(6, '0'),
    );
  }

  static List<int> _transcript(List<int> inviterPub, List<int> joinerPub) =>
      [...utf8.encode(_info), ...inviterPub, ...joinerPub];

  static Map<String, dynamic> _json(Uint8List frame) {
    try {
      return jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;
    } on Object {
      throw const SyncProtocolException('The other device sent bad data.');
    }
  }

  static String _string(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is String) return v;
    throw const SyncProtocolException('The other device sent bad data.');
  }

  static Uint8List _bytes(Map<String, dynamic> json, String key) {
    try {
      return base64.decode(_string(json, key));
    } on FormatException {
      throw const SyncProtocolException('The other device sent bad data.');
    }
  }

  static const _mismatch = SyncProtocolException(
    'The devices could not agree on a key. Show a new code and try again.',
  );
}
