import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:vaultkey/src/core/interfaces/key_derivation.dart';
import 'package:vaultkey/src/features/share/services/shared_entry.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';

/// In person: two QR codes, nothing typed.
///
/// The receiver shows [ShareInvite.uri] (a one-time X25519 public key). The
/// sender scans it, makes its own one-time key pair, and shows the entry
/// sealed under the X25519 shared secret ([sealForInvite]). A photo of
/// either code is useless on its own: the private keys never leave the
/// phones, and the receiver's dies with its screen.
abstract final class QrShare {
  static const String inviteScheme = 'vaultly-recv://v1';
  static const String shareScheme = 'vaultly-share://v1';
  static const String _info = 'vaultly-share-v1';

  /// Larger entries (long notes) make a QR code too dense to scan from a
  /// screen; they go as a file.
  static const int maxPlaintextBytes = 1000;

  static const _notInvite = ShareException(
    'That is not a Vaultly receive code. On the other phone, open Vault, '
    'then Receive an entry.',
  );
  static const _notShare = ShareException(
    'That is not the code for this share. Scan the code on the sending '
    'phone.',
  );

  /// The sender's half: [entry] (from [SharedEntry.encode]) sealed for the
  /// receiver whose invite was scanned.
  static Future<String> sealForInvite(String inviteUri, List<int> entry) async {
    if (entry.length > maxPlaintextBytes) {
      throw const ShareException(
        'This entry is too long for a QR code. Share it as a file instead.',
      );
    }
    final receiverPub = _param(inviteUri, inviteScheme, 'k', _notInvite);
    final pair = await SyncPrimitives.x25519.newKeyPair();
    final senderPub = await SyncPrimitives.publicKeyOf(pair);
    final key = await _key(
      pair,
      receiverPub,
      receiverPub: receiverPub,
      senderPub: senderPub,
      onBadKey: _notInvite,
    );
    final box = await SyncPrimitives.aead.encrypt(
      entry,
      secretKey: SecretKey(key),
      nonce: SyncPrimitives.randomBytes(12),
      aad: _aad(receiverPub, senderPub),
    );
    key.fillRange(0, key.length, 0);
    return '$shareScheme?e=${_b64(senderPub)}&c=${_b64(box.concatenation())}';
  }

  /// The AEAD key both phones derive: HKDF over the X25519 secret of
  /// [mine] and [theirs], salted with both public keys so it is bound to
  /// this exact pair.
  static Future<Uint8List> _key(
    SimpleKeyPair mine,
    Uint8List theirs, {
    required List<int> receiverPub,
    required List<int> senderPub,
    required ShareException onBadKey,
  }) async {
    final Uint8List shared;
    try {
      shared = await SyncPrimitives.dh(mine, theirs);
    } on SyncProtocolException {
      throw onBadKey;
    }
    try {
      return await SyncPrimitives.hkdf(
        ikm: shared,
        salt: [...receiverPub, ...senderPub],
        info: utf8.encode(_info),
        length: 32,
      );
    } finally {
      shared.fillRange(0, shared.length, 0);
    }
  }

  static List<int> _aad(List<int> receiverPub, List<int> senderPub) =>
      [...utf8.encode(shareScheme), ...receiverPub, ...senderPub];

  static Uint8List _param(
    String uri,
    String scheme,
    String name,
    ShareException error,
  ) {
    if (!uri.startsWith('$scheme?')) throw error;
    final value = Uri.splitQueryString(uri.substring(scheme.length + 1))[name];
    if (value == null) throw error;
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    } on FormatException {
      throw error;
    }
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

/// The receiver's one-time key pair, alive while its screen is open.
final class ShareInvite {
  ShareInvite._(this._pair, this._publicKey);

  static Future<ShareInvite> create() async {
    final pair = await SyncPrimitives.x25519.newKeyPair();
    return ShareInvite._(pair, await SyncPrimitives.publicKeyOf(pair));
  }

  final SimpleKeyPair _pair;
  final Uint8List _publicKey;

  /// What the receiver's QR code holds.
  String get uri => '${QrShare.inviteScheme}?k=${QrShare._b64(_publicKey)}';

  /// Opens the sender's code. Throws [ShareException] when it was sealed
  /// for another invite or altered.
  Future<Uint8List> open(String shareUri) async {
    final senderPub = QrShare._param(
      shareUri,
      QrShare.shareScheme,
      'e',
      QrShare._notShare,
    );
    final sealed =
        QrShare._param(shareUri, QrShare.shareScheme, 'c', QrShare._notShare);
    if (sealed.length < 12 + 16) throw QrShare._notShare;
    final key = await QrShare._key(
      _pair,
      senderPub,
      receiverPub: _publicKey,
      senderPub: senderPub,
      onBadKey: QrShare._notShare,
    );
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: 12,
        macLength: 16,
      );
      return Uint8List.fromList(await SyncPrimitives.aead.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: QrShare._aad(_publicKey, senderPub),
      ));
    } on SecretBoxAuthenticationError {
      throw QrShare._notShare;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}

/// At a distance: a `.vaultlyshare` file plus a one-time code sent another
/// way. The code has the recovery-key shape (28 characters, 140 bits) and
/// is stretched with Argon2id like a backup passphrase, so guessing it
/// offline is not practical.
final class FileShare {
  const FileShare({
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
  })  : _kdf = keyDerivation,
        _cipher = cipher;

  final IKeyDerivation _kdf;
  final CipherService _cipher;

  static const String format = 'vaultly.share';
  static const int formatVersion = 1;
  static const String extension = 'vaultlyshare';

  /// A fresh one-time code in display form.
  static String newCode() => RecoveryKey.generate();

  Future<String> seal(List<int> entry, String code) async {
    final salt = await _cipher.generateSalt();
    final key = await _kdf.deriveKey(
      password: RecoveryKey.normalize(code)!,
      salt: salt,
    );
    try {
      final payload = await _cipher.encrypt(
        plaintext: utf8.decode(entry),
        keyBytes: key,
        salt: salt,
      );
      return jsonEncode({
        'format': format,
        'formatVersion': formatVersion,
        'kdf': 'argon2id',
        'salt': base64Encode(salt),
        'nonce': base64Encode(payload.nonce),
        'ciphertext': base64Encode(payload.ciphertext),
      });
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// Whether [content] looks like a shared-entry file (before asking for
  /// the code).
  static bool recognises(String content) {
    try {
      final doc = jsonDecode(content);
      return doc is Map<String, dynamic> && doc['format'] == format;
    } on FormatException {
      return false;
    }
  }

  Future<Uint8List> open(String content, String code) async {
    const notShare = ShareException('This is not a Vaultly shared entry.');
    final Object? doc;
    try {
      doc = jsonDecode(content);
    } on FormatException {
      throw notShare;
    }
    if (doc is! Map<String, dynamic> ||
        doc['format'] != format ||
        doc['formatVersion'] is! int ||
        doc['salt'] is! String ||
        doc['nonce'] is! String ||
        doc['ciphertext'] is! String) {
      throw notShare;
    }
    if ((doc['formatVersion'] as int) > formatVersion) {
      throw const ShareException(
        'This file comes from a newer Vaultly. Update Vaultly, then try '
        'again.',
      );
    }
    final normalized = RecoveryKey.normalize(code);
    if (normalized == null) {
      throw const ShareException(
        'The code has ${RecoveryKey.length} letters and numbers.',
      );
    }
    final salt = Uint8List.fromList(base64Decode(doc['salt'] as String));
    final key = await _kdf.deriveKey(password: normalized, salt: salt);
    try {
      final plaintext = await _cipher.decrypt(
        payload: EncryptedPayload(
          ciphertext:
              Uint8List.fromList(base64Decode(doc['ciphertext'] as String)),
          nonce: Uint8List.fromList(base64Decode(doc['nonce'] as String)),
          salt: salt,
        ),
        keyBytes: key,
      );
      return utf8.encode(plaintext);
    } on Object {
      // AES-GCM authentication failed: wrong code or an altered file.
      throw const ShareException('That code does not open this file.');
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
