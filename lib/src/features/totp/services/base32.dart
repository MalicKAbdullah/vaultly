import 'dart:typed_data';

/// RFC 4648 base32. Decoding is tolerant of the messy secrets users
/// actually paste: lowercase letters, spaces/dashes between groups, and
/// missing `=` padding are all accepted.
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

  /// Encodes [bytes] as unpadded uppercase base32.
  static String encode(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bitsLeft = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xFF);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        out.write(_alphabet[(buffer >> bitsLeft) & 0x1F]);
      }
      buffer &= (1 << bitsLeft) - 1;
    }
    if (bitsLeft > 0) out.write(_alphabet[(buffer << (5 - bitsLeft)) & 0x1F]);
    return out.toString();
  }
}
