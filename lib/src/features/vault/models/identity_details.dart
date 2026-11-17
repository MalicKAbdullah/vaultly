import 'package:flutter/foundation.dart';

/// A person's contact details and postal address, stored on a vault entry.
@immutable
final class IdentityDetails {
  const IdentityDetails({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = '',
  });

  factory IdentityDetails.fromJson(Map<String, dynamic> json) =>
      IdentityDetails(
        fullName: json['fullName'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
        address1: json['address1'] as String,
        address2: json['address2'] as String,
        city: json['city'] as String,
        region: json['region'] as String,
        postalCode: json['postalCode'] as String,
        country: json['country'] as String,
      );

  final String fullName;
  final String email;
  final String phone;

  /// Street and number.
  final String address1;

  /// Flat, floor, building.
  final String address2;
  final String city;

  /// State, province or county.
  final String region;
  final String postalCode;
  final String country;

  bool get isEmpty =>
      fullName.isEmpty && email.isEmpty && phone.isEmpty && !hasAddress;

  bool get hasAddress =>
      address1.isNotEmpty ||
      address2.isNotEmpty ||
      city.isNotEmpty ||
      region.isNotEmpty ||
      postalCode.isNotEmpty ||
      country.isNotEmpty;

  /// The postal address as written on an envelope, one line each.
  String get formattedAddress => [
        address1,
        address2,
        [city, region, postalCode].where((p) => p.isNotEmpty).join(' '),
        country,
      ].where((line) => line.isNotEmpty).join('\n');

  /// `Label: value` pairs for plain-text exports.
  Map<String, String> get labelledFields => {
        'Name': fullName,
        'Email': email,
        'Phone': phone,
        'Address': formattedAddress.replaceAll('\n', ', '),
      };

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'address1': address1,
        'address2': address2,
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
      };

  @override
  bool operator ==(Object other) =>
      other is IdentityDetails &&
      other.fullName == fullName &&
      other.email == email &&
      other.phone == phone &&
      other.address1 == address1 &&
      other.address2 == address2 &&
      other.city == city &&
      other.region == region &&
      other.postalCode == postalCode &&
      other.country == country;

  @override
  int get hashCode => Object.hash(fullName, email, phone, address1, address2,
      city, region, postalCode, country);
}
