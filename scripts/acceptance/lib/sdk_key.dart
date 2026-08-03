import 'dart:math';

/// The 32-symbol lowercase Crockford base32 alphabet: digits 0-9 and letters
/// a-z excluding i, l, o, u. Matches the core's key validator.
const String _crockford = '0123456789abcdefghjkmnpqrstvwxyz';

/// Generates a fresh, syntactically valid mobile SDK key. A cryptographically
/// strong source keeps keys collision-free across separate runs, so an old
/// cache entry on the simulator or emulator can never be reused, which would
/// let initialize return Ready from stale cache before the fixture poll.
String generateSdkKey() {
  final rng = Random.secure();
  final body = List.generate(
      32, (_) => _crockford[rng.nextInt(_crockford.length)]).join();
  return 'cpk_mob_$body';
}
