// Stand-ins named after declarations that must stay out of the public API.
// internal_names_test.dart imports these beside every public barrel, so a
// barrel that starts exporting one of the real declarations makes the
// reference ambiguous and that test stops compiling

/// Mirrors the paywall snapshot cache class
class SnapshotCache {}

/// Mirrors the shared paywall snapshot cache instance
const Object snapshotCache = Object();

/// Mirrors the paywall snapshot cache key builder
const Object snapshotCacheKey = Object();

/// Mirrors the paywall snapshot cache lifetime
const Object snapshotTtl = Object();
