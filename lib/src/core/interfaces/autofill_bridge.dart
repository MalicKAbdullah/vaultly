import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A fill request Vaultly was launched to answer: another app (or a website
/// in a browser) is showing a login form.
@immutable
final class AutofillFillRequest {
  const AutofillFillRequest({this.domain, this.package});

  /// Web domain of the page being filled, when the form is in a browser.
  final String? domain;

  /// Package name of the requesting Android app.
  final String? package;

  @override
  bool operator ==(Object other) =>
      other is AutofillFillRequest &&
      other.domain == domain &&
      other.package == package;

  @override
  int get hashCode => Object.hash(domain, package);
}

/// Platform seam for the Android autofill flow. The real implementation
/// talks to MainActivity over a MethodChannel; tests use a fake.
abstract interface class IAutofillBridge {
  /// The fill request this launch should answer, or null on a normal launch.
  Future<AutofillFillRequest?> pendingRequest();

  /// Hands the picked credentials back to Android, which fills the form
  /// and closes Vaultly. Returns false when there was nothing to answer.
  Future<bool> complete({
    required String username,
    required String password,
    required String label,
  });

  /// Abandons the fill request and closes Vaultly.
  Future<void> cancel();

  /// Whether this device supports autofill at all (Android 8+).
  Future<bool> isSupported();

  /// Whether Vaultly is the device's current autofill provider.
  Future<bool> isEnabled();

  /// Opens the system screen where the user can pick Vaultly as the
  /// autofill provider. Returns false when the screen could not open.
  Future<bool> openSettings();
}

/// Talks to MainActivity. Every call degrades gracefully on platforms
/// without the channel (iOS, tests) instead of throwing.
final class MethodChannelAutofillBridge implements IAutofillBridge {
  const MethodChannelAutofillBridge();

  static const MethodChannel _channel = MethodChannel('vaultly/autofill');

  @override
  Future<AutofillFillRequest?> pendingRequest() async {
    final map = await _invoke<Map<Object?, Object?>>('getPendingRequest');
    if (map == null) return null;
    return AutofillFillRequest(
      domain: map['domain'] as String?,
      package: map['package'] as String?,
    );
  }

  @override
  Future<bool> complete({
    required String username,
    required String password,
    required String label,
  }) async =>
      await _invoke<bool>('complete', {
        'username': username,
        'password': password,
        'label': label,
      }) ??
      false;

  @override
  Future<void> cancel() => _invoke<void>('cancel');

  @override
  Future<bool> isSupported() async =>
      await _invoke<bool>('isSupported') ?? false;

  @override
  Future<bool> isEnabled() async => await _invoke<bool>('isEnabled') ?? false;

  @override
  Future<bool> openSettings() async =>
      await _invoke<bool>('openSettings') ?? false;

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null; // Not on Android (or engine without the channel).
    } on PlatformException {
      return null;
    }
  }
}
