import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

/// Abstraction over key derivation so unit tests can inject a fast,
/// deterministic fake instead of running Argon2id.
abstract interface class IKeyDerivation {
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
  });
}

/// Production implementation backed by core_crypto's Argon2id
/// [KeyDerivationService] (OWASP-recommended parameters, background isolate).
final class Argon2KeyDerivation implements IKeyDerivation {
  const Argon2KeyDerivation(this._service);

  final KeyDerivationService _service;

  @override
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
  }) =>
      _service.deriveKey(masterPassword: password, salt: salt);
}
