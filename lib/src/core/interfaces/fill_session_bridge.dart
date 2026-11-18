import 'package:flutter/services.dart';

/// The login Vaultly keeps ready for the next pages of a sign-in. Held in
/// the native fill service's memory; Dart arms it, ends it and reads
/// whether it is live.
abstract interface class IFillSessionBridge {
  /// Arms the session for [entryId]'s site. The values go to native memory
  /// only and are wiped after two minutes, on screen off, or on [clear].
  Future<void> arm({
    required String entryId,
    required String title,
    required String username,
    required String password,
    required String url,
    Map<String, Object>? totp,
  });

  /// Ends the session.
  Future<void> clear();

  /// The entry the live session belongs to, or null.
  Future<String?> liveEntryId();

  /// Whether choosing an account keeps it ready for the next pages.
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

final class MethodChannelFillSessionBridge implements IFillSessionBridge {
  const MethodChannelFillSessionBridge();

  static const MethodChannel _channel = MethodChannel('vaultly/fill_session');

  @override
  Future<void> arm({
    required String entryId,
    required String title,
    required String username,
    required String password,
    required String url,
    Map<String, Object>? totp,
  }) =>
      _invoke<void>('arm', {
        'entryId': entryId,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'totp': totp,
      });

  @override
  Future<void> clear() => _invoke<void>('clear');

  @override
  Future<String?> liveEntryId() => _invoke<String>('status');

  @override
  Future<bool> isEnabled() async => await _invoke<bool>('isEnabled') ?? true;

  @override
  Future<void> setEnabled(bool enabled) =>
      _invoke<void>('setEnabled', {'enabled': enabled});

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null; // Not on Android (or an engine without the channel).
    }
  }
}
