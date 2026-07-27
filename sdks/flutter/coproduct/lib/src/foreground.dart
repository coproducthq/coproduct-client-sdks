import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;

import 'host.dart' show ForegroundBinder;

/// Refreshes on return to the foreground via AppLifecycleListener, returning the
/// listener's disposer so shutdown removes it. The scheduler decides whether a
/// refresh actually polls, honoring an active backoff.
// ignore: prefer_function_declarations_over_variables
final ForegroundBinder appLifecycleForegroundBinder = (onForeground) {
  final listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.resumed) onForeground();
    },
  );
  return listener.dispose;
};
