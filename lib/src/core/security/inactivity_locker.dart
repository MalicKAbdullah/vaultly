import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/settings/providers/settings_providers.dart';

/// Locks the session when the app is backgrounded (paused or detached) or
/// after a period of user inactivity.
/// Any pointer event resets the inactivity timer.
class InactivityLocker extends ConsumerStatefulWidget {
  const InactivityLocker({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<InactivityLocker> createState() => _InactivityLockerState();
}

class _InactivityLockerState extends ConsumerState<InactivityLocker> {
  late final AppLifecycleListener _lifecycle;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: _lock,
      onDetach: _lock,
      // A save request can reach an app that is already running.
      onResume: () => ref.invalidate(pendingSaveProvider),
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _lock() {
    _inactivityTimer?.cancel();
    ref.read(sessionProvider.notifier).lock();
  }

  /// The user sat idle in the app. Unlike leaving the app (which must not
  /// end a "Sign in" that just opened a browser), idling ends the session.
  void _lockForInactivity() {
    unawaited(ref.read(fillSessionBridgeProvider).clear());
    _lock();
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    if (ref.read(sessionProvider) != AuthStatus.unlocked) return;
    _inactivityTimer = Timer(ref.read(autoLockProvider), _lockForInactivity);
  }

  @override
  Widget build(BuildContext context) {
    // (Re)arm the timer whenever the session unlocks or the timeout changes.
    ref.listen(sessionProvider, (_, __) => _resetTimer());
    ref.listen(autoLockProvider, (_, __) => _resetTimer());

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
