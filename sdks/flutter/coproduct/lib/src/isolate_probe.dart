import 'package:flutter/services.dart' show RootIsolateToken;

/// True on a root isolate. RootIsolateToken.instance is documented as null on a
/// spawned background isolate, which makes it the probe for the entry check. It
/// is deliberately used nowhere else: suppressing a diagnostic on a bad
/// inference would hide a real misconfiguration
bool isRootIsolateNow() => RootIsolateToken.instance != null;
