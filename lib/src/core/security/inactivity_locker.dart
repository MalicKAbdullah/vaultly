import 'dart:async';

import 'package:core_security/core_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/settings/providers/settings_providers.dart';

/// Locks the session when the app is backgrounded (via core_security's
/// [LifecycleSecurityService]) or after a period of user inactivity.
/// Any pointer event resets the inactivity timer.
class InactivityLocker extends ConsumerStatefulWidget {
  const InactivityLocker({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<InactivityLocker> createState() => _InactivityLockerState();
}

class _InactivityLockerState extends ConsumerState<InactivityLocker> {
  late final LifecycleSecurityService _lifecycle;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _lifecycle = LifecycleSecurityService(onLockRequested: _lock);
    _lifecycle.attach();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _lifecycle.detach();
    super.dispose();
  }

  void _lock() {
    _inactivityTimer?.cancel();
    ref.read(sessionProvider.notifier).lock();
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    if (ref.read(sessionProvider) != AuthStatus.unlocked) return;
    _inactivityTimer = Timer(ref.read(autoLockProvider), _lock);
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
