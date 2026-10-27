import 'package:flutter/foundation.dart';

/// A WebAuthn passkey (ES256) held in the vault. Binary values are unpadded
/// base64url, as WebAuthn JSON carries them.
///
/// [privateKey] exists only inside the decrypted vault: it is written to
/// the encrypted vault file and encrypted backups, never shown, copied or
/// exported in plain text.
@immutable
final class PasskeyCredential {
  const PasskeyCredential({
    required this.rpId,
    required this.rpName,
    required this.userName,
    required this.userDisplayName,
    required this.credentialId,
    required this.userHandle,
    required this.publicKey,
    required this.privateKey,
    this.lastUsedAt,
  });

  factory PasskeyCredential.fromJson(Map<String, dynamic> json) =>
      PasskeyCredential(
        rpId: json['rpId'] as String,
        rpName: json['rpName'] as String,
        userName: json['userName'] as String,
        userDisplayName: json['userDisplayName'] as String,
        credentialId: json['credentialId'] as String,
        userHandle: json['userHandle'] as String,
        publicKey: json['publicKey'] as String,
        privateKey: json['privateKey'] as String,
        lastUsedAt: json['lastUsedAt'] == null
            ? null
            : DateTime.parse(json['lastUsedAt'] as String),
      );

  /// Relying-party id: the site's domain, e.g. `github.com`.
  final String rpId;

  /// The site's own name for itself.
  final String rpName;

  final String userName;
  final String userDisplayName;

  final String credentialId;

  /// The site's id for the account (WebAuthn `user.id`).
  final String userHandle;

  /// X.509 SubjectPublicKeyInfo DER.
  final String publicKey;

  /// PKCS#8 DER of the P-256 private key.
  final String privateKey;

  /// Last sign-in with this passkey; null until first use.
  final DateTime? lastUsedAt;

  Map<String, dynamic> toJson() => {
        'rpId': rpId,
        'rpName': rpName,
        'userName': userName,
        'userDisplayName': userDisplayName,
        'credentialId': credentialId,
        'userHandle': userHandle,
        'publicKey': publicKey,
        'privateKey': privateKey,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  PasskeyCredential usedAt(DateTime when) => PasskeyCredential(
        rpId: rpId,
        rpName: rpName,
        userName: userName,
        userDisplayName: userDisplayName,
        credentialId: credentialId,
        userHandle: userHandle,
        publicKey: publicKey,
        privateKey: privateKey,
        lastUsedAt: when,
      );

  @override
  bool operator ==(Object other) =>
      other is PasskeyCredential &&
      other.rpId == rpId &&
      other.rpName == rpName &&
      other.userName == userName &&
      other.userDisplayName == userDisplayName &&
      other.credentialId == credentialId &&
      other.userHandle == userHandle &&
      other.publicKey == publicKey &&
      other.privateKey == privateKey &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(rpId, rpName, userName, userDisplayName,
      credentialId, userHandle, publicKey, privateKey, lastUsedAt);
}
