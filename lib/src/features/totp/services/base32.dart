import 'dart:typed_data';

/// RFC 4648 base32 decoding, tolerant of the messy secrets users actually
/// paste: lowercase letters, spaces/dashes between groups, and missing
/// `=` padding are all accepted.
abstract final class Base32 {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Normalizes a pasted secret: uppercased, spaces/dashes/padding removed.
  static String normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '').replaceAll('=', '');

  /// Whether [input] (after [normalize]) is non-empty valid base32.
  static bool isValid(String input) {
    final cleaned = normalize(input);
    if (cleaned.isEmpty) return false;
    return cleaned.split('').every(_alphabet.contains);
  }

  /// Decodes [input] to bytes. Throws [FormatException] on characters
  /// outside the base32 alphabet or an empty secret.
  static Uint8List decode(String input) {
    final cleaned = normalize(input);
    if (cleaned.isEmpty) {
      throw const FormatException('The secret is empty.');
    }

    var buffer = 0;
    var bitsLeft = 0;
    final bytes = <int>[];
    for (final char in cleaned.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) {
        throw FormatException('"$char" is not a valid secret character.');
      }
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
  }
}
