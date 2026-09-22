import 'package:coproduct/src/isolate_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the production isolate probe reports true on a root isolate', () {
    expect(isRootIsolateNow(), isTrue);
  });
}
