import 'package:core_theme/core_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The System/Light/Dark choice. `main` loads it before `runApp` and
/// overrides this provider, so the first frame (the lock screen included)
/// already has the chosen theme.
final appearanceProvider = Provider<AppearanceController>(
  (_) => throw StateError('appearanceProvider is overridden in main()'),
);
