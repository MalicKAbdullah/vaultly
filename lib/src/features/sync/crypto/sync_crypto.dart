import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';

/// The primitives sync and pairing share: X25519, HKDF-SHA256, HMAC-SHA256
/// and ChaCha20-Poly1305.
abstract final class SyncPrimitives {
  static final X25519 x25519 = X25519();
  static final Chacha20 aead = Chacha20.poly1305Aead();
  static final Hmac hmac = Hmac.sha256();
  static final Random _random = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  static Future<Uint8List> publicKeyOf(SimpleKeyPair pair) async =>
      Uint8List.fromList((await pair.extractPublicKey()).bytes);

  /// X25519 shared secret. An all-zero result means the peer sent a
  /// low-order point, which is refused.
  static Future<Uint8List> dh(SimpleKeyPair mine, List<int> theirs) async {
    if (theirs.length != 32) {
      throw const SyncProtocolException('The other device sent a bad key.');
    }
    final shared = await x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await shared.extractBytes());
    if (bytes.every((b) => b == 0)) {
      throw const SyncProtocolException('The other device sent a bad key.');
    }
    return bytes;
  }

  static Future<Uint8List> hkdf({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) async {
    final key = await Hkdf(hmac: hmac, outputLength: length).deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Uint8List> mac(List<int> key, List<int> data) async =>
      Uint8List.fromList(
        (await hmac.calculateMac(data, secretKey: SecretKey(key))).bytes,
      );

  static Future<Uint8List> sha256(List<int> data) async =>
      Uint8List.fromList((await Sha256().hash(data)).bytes);

  /// Constant-time equality for MACs.
  static bool equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// An authenticated, encrypted frame stream: ChaCha20-Poly1305 with one
/// key per direction and a 96-bit nonce built from a per-direction counter,
/// so a replayed, reordered, dropped or altered frame fails to decrypt.
final class SecureChannel {
  SecureChannel._(this._frames, this._sendKey, this._receiveKey, this._aad);

  final FrameChannel _frames;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  final List<int> _aad;
  int _sent = 0;
  int _received = 0;

  static List<int> _nonce(int counter) {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, counter);
    return n;
  }

  Future<void> send(List<int> plaintext) async {
    final box = await SyncPrimitives.aead.encrypt(
      plaintext,
      secretKey: _sendKey,
      nonce: _nonce(_sent++),
      aad: _aad,
    );
    _frames.send(box.concatenation(nonce: false));
  }

  Future<Uint8List> receive({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final frame = await _frames.receive(timeout: timeout);
    if (frame.length < 16) throw _tampered;
    final box = SecretBox(
      Uint8List.sublistView(frame, 0, frame.length - 16),
      nonce: _nonce(_received++),
      mac: Mac(Uint8List.sublistView(frame, frame.length - 16)),
    );
    try {
      return Uint8List.fromList(await SyncPrimitives.aead.decrypt(
        box,
        secretKey: _receiveKey,
        aad: _aad,
      ));
    } on SecretBoxAuthenticationError {
      throw _tampered;
    }
  }

  Future<void> close() => _frames.close();

  static const _tampered = SyncProtocolException(
    'The connection could not be verified. Make sure both devices are '
    'paired with each other.',
  );
}

/// The sync handshake, in the spirit of Noise NNpsk0: both sides send an
/// ephemeral X25519 key and a nonce in the clear, then derive
/// direction keys with HKDF over the ephemeral shared secret, salted with
/// the pairing key and bound to the transcript. Only a device holding the
/// pairing key can produce or read the first encrypted frame (a key
/// confirmation), and fresh ephemerals give every session forward secrecy.
abstract final class SyncHandshake {
  static const String _protocol = 'vaultly-sync-v1';

  /// Starts a session with [peerId], whose pairing key is [pairingKey].
  static Future<SecureChannel> initiate({
    required FrameChannel channel,
    required String myId,
    required String peerId,
    required List<int> pairingKey,
  }) async {
    final eph = await SyncPrimitives.x25519.newKeyPair();
    final hello = _hello(myId, await SyncPrimitives.publicKeyOf(eph));
    channel.send(hello);
    final reply = await channel.receive();
    final (replyId, replyEph) = _parseHello(reply);
    if (replyId != peerId) {
      throw const SyncProtocolException(
        'A different device answered. Try again.',
      );
    }
    final secure = await _derive(
      channel: channel,
      eph: eph,
      remoteEph: replyEph,
      pairingKey: pairingKey,
      initiatorHello: hello,
      responderHello: reply,
      initiator: true,
    );
    await _confirm(secure);
    return secure;
  }

  /// Answers a session. [keyFor] returns the pairing key for a device id,
  /// or null for a device that is not paired.
  static Future<(SecureChannel, String)> respond({
    required FrameChannel channel,
    required String myId,
    required Future<List<int>?> Function(String peerId) keyFor,
  }) async {
    final hello = await channel.receive();
    final (peerId, peerEph) = _parseHello(hello);
    final key = await keyFor(peerId);
    if (key == null) {
      throw const SyncProtocolException(
        'A device that is not paired tried to sync.',
      );
    }
    final eph = await SyncPrimitives.x25519.newKeyPair();
    final reply = _hello(myId, await SyncPrimitives.publicKeyOf(eph));
    channel.send(reply);
    final secure = await _derive(
      channel: channel,
      eph: eph,
      remoteEph: peerEph,
      pairingKey: key,
      initiatorHello: hello,
      responderHello: reply,
      initiator: false,
    );
    await _confirm(secure);
    return (secure, peerId);
  }

  static Uint8List _hello(String id, Uint8List eph) => utf8.encode(jsonEncode({
        'v': 1,
        'id': id,
        'e': base64.encode(eph),
        'n': base64.encode(SyncPrimitives.randomBytes(16)),
      }));

  static (String, Uint8List) _parseHello(Uint8List frame) {
    try {
      final json = jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;
      if (json['v'] != 1) {
        throw const SyncProtocolException(
          'The other device runs a different Vaultly version. Update both.',
        );
      }
      return (json['id'] as String, base64.decode(json['e'] as String));
    } on SyncProtocolException {
      rethrow;
    } on Object {
      throw const SyncProtocolException('The other device sent bad data.');
    }
  }

  static Future<SecureChannel> _derive({
    required FrameChannel channel,
    required SimpleKeyPair eph,
    required List<int> remoteEph,
    required List<int> pairingKey,
    required List<int> initiatorHello,
    required List<int> responderHello,
    required bool initiator,
  }) async {
    final shared = await SyncPrimitives.dh(eph, remoteEph);
    final transcript = await SyncPrimitives.sha256([
      ...utf8.encode(_protocol),
      ...initiatorHello,
      ...responderHello,
    ]);
    final keys = await SyncPrimitives.hkdf(
      ikm: shared,
      salt: pairingKey,
      info: transcript,
      length: 64,
    );
    shared.fillRange(0, shared.length, 0);
    final i2r = SecretKey(Uint8List.sublistView(keys, 0, 32));
    final r2i = SecretKey(Uint8List.sublistView(keys, 32, 64));
    return SecureChannel._(
      channel,
      initiator ? i2r : r2i,
      initiator ? r2i : i2r,
      transcript,
    );
  }

  /// Each side's first encrypted frame; decrypting the other's proves it
  /// holds the same pairing key.
  static Future<void> _confirm(SecureChannel secure) async {
    await secure.send(utf8.encode(_protocol));
    final got = await secure.receive();
    if (!SyncPrimitives.equal(got, utf8.encode(_protocol))) {
      throw const SyncProtocolException('The other device sent bad data.');
    }
  }
}
