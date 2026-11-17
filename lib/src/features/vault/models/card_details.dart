import 'package:flutter/foundation.dart';

/// A payment card stored on a vault entry.
///
/// [number] and [cvc] are secrets: they are masked on screen, copied with
/// the clipboard auto-clear, and never written to logs.
@immutable
final class CardDetails {
  const CardDetails({
    this.holder = '',
    this.number = '',
    this.expMonth = '',
    this.expYear = '',
    this.cvc = '',
  });

  factory CardDetails.fromJson(Map<String, dynamic> json) => CardDetails(
        holder: json['holder'] as String,
        number: json['number'] as String,
        expMonth: json['expMonth'] as String,
        expYear: json['expYear'] as String,
        cvc: json['cvc'] as String,
      );

  /// The name printed on the card.
  final String holder;

  /// Digits only.
  final String number;

  /// Two digits, `01`–`12`, or empty.
  final String expMonth;

  /// Four digits, or empty.
  final String expYear;

  /// The security code on the back (CVC / CVV).
  final String cvc;

  bool get isEmpty =>
      holder.isEmpty &&
      number.isEmpty &&
      expMonth.isEmpty &&
      expYear.isEmpty &&
      cvc.isEmpty;

  /// The last four digits, safe to show without revealing the card.
  String get last4 =>
      number.length <= 4 ? number : number.substring(number.length - 4);

  /// `MM/YY`, or empty when no expiry is stored.
  String get expiry => expMonth.isEmpty || expYear.isEmpty
      ? ''
      : '$expMonth/${expYear.substring(expYear.length - 2)}';

  /// The card network read from the leading digits, or empty when unknown.
  String get brand {
    final n = number;
    if (n.startsWith('4')) return 'Visa';
    if (n.startsWith('34') || n.startsWith('37')) return 'Amex';
    final two = n.length >= 2 ? int.parse(n.substring(0, 2)) : 0;
    final four = n.length >= 4 ? int.parse(n.substring(0, 4)) : 0;
    if ((two >= 51 && two <= 55) || (four >= 2221 && four <= 2720)) {
      return 'Mastercard';
    }
    if (n.startsWith('6011') || n.startsWith('65')) return 'Discover';
    return '';
  }

  /// "Visa •••• 4242": names the card without revealing it.
  String get maskedLabel {
    if (number.isEmpty) return '';
    final b = brand;
    return b.isEmpty ? '•••• $last4' : '$b •••• $last4';
  }

  /// The number in groups of four, for reading it off the screen.
  String get groupedNumber => [
        for (var i = 0; i < number.length; i += 4)
          number.substring(i, i + 4 > number.length ? number.length : i + 4),
      ].join(' ');

  /// Keeps only the digits of a typed or imported card number.
  static String digitsOf(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// The digits of [raw] when it is written like a card number (digits,
  /// spaces, dashes); null for anything else, such as a gift-card code.
  static String? numberOf(String raw) =>
      RegExp(r'^[0-9 \-]*$').hasMatch(raw) ? digitsOf(raw) : null;

  /// Parses a typed expiry (`7/30`, `07/2030`, `0730`, `07-30`) into a
  /// two-digit month and a four-digit year. Empty input gives empty parts;
  /// anything that is not a real month and year returns null.
  static ({String month, String year})? parseExpiry(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return (month: '', year: '');
    final parts =
        RegExp(r'^(\d{1,2})\s*[/\-. ]\s*(\d{2}|\d{4})$').firstMatch(text) ??
            RegExp(r'^(\d{2})(\d{2}|\d{4})$').firstMatch(text);
    if (parts == null) return null;
    return normalizeExpiry(parts.group(1)!, parts.group(2)!);
  }

  /// A month (`7`, `07`) and year (`30`, `2030`) in the stored form, or null
  /// when either is not a valid value.
  static ({String month, String year})? normalizeExpiry(
    String month,
    String year,
  ) {
    final y = year.trim();
    final m = int.tryParse(month.trim());
    if (m == null || m < 1 || m > 12) return null;
    if (!RegExp(r'^(\d{2}|\d{4})$').hasMatch(y)) return null;
    return (
      month: m.toString().padLeft(2, '0'),
      year: y.length == 2 ? '20$y' : y,
    );
  }

  /// `Label: value` pairs for plain-text exports.
  Map<String, String> get labelledFields => {
        'Cardholder': holder,
        'Card number': number,
        'Expires': expiry,
        'Security code': cvc,
      };

  Map<String, dynamic> toJson() => {
        'holder': holder,
        'number': number,
        'expMonth': expMonth,
        'expYear': expYear,
        'cvc': cvc,
      };

  @override
  bool operator ==(Object other) =>
      other is CardDetails &&
      other.holder == holder &&
      other.number == number &&
      other.expMonth == expMonth &&
      other.expYear == expYear &&
      other.cvc == cvc;

  @override
  int get hashCode => Object.hash(holder, number, expMonth, expYear, cvc);

  // Keeps the number and code out of anything that interpolates the object
  // (logs, error messages, test failure output).
  @override
  String toString() =>
      'CardDetails(${maskedLabel.isEmpty ? '-' : maskedLabel})';
}
