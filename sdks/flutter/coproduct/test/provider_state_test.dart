import 'package:coproduct/src/provider_state.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every generated state maps to a public state', () {
    expect(providerStateFromFrb(frb.ProviderState.notReady), ProviderState.notReady);
    expect(providerStateFromFrb(frb.ProviderState.ready), ProviderState.ready);
    expect(providerStateFromFrb(frb.ProviderState.retrying), ProviderState.retrying);
    expect(providerStateFromFrb(frb.ProviderState.stale), ProviderState.stale);
    expect(providerStateFromFrb(frb.ProviderState.fatal), ProviderState.fatal);
  });
}
