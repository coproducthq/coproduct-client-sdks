import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from '@coproduct/react-native-sdk';
// Imported for the side effect of loading the entry points, which must not
// throw in an Expo build
import '@coproduct/react-native-sdk/onboarding';
import { IapPaywallBridge } from '@coproduct/react-native-sdk/paywall';

type DemoStatus = {
  ready: boolean;
  hostCallbacks: boolean;
  flagValue: boolean;
  observerRegistered: boolean;
  purchaseLibrary: boolean;
};

const initial: DemoStatus = {
  ready: false,
  hostCallbacks: false,
  flagValue: false,
  observerRegistered: false,
  purchaseLibrary: false,
};

// The paywall's purchase bridge loads expo-iap here, because this app does
// not install react-native-iap. Constructing it throws when neither loads
function purchaseLibraryLoads(): boolean {
  try {
    new IapPaywallBridge();
    return true;
  } catch (error) {
    console.error('COPRODUCT_EXPO_CONSUMER_ERROR', error);
    return false;
  }
}

export default function App() {
  const subscriptionRef = useRef<Cancellable | null>(null);
  const clientRef = useRef<CoproductClient | null>(null);
  const [status, setStatus] = useState<DemoStatus>(initial);

  useEffect(() => {
    let active = true;

    async function runDemo(): Promise<void> {
      const client = await Coproduct.initialize(
        'cpk_mob_0123456789abcdefghjkmnpqrstvwxyz',
        { transport: mockTransport, secureStore: mockSecureStore }
      );
      clientRef.current = client;

      const flagValue = client.getBool('test-flag', false);
      subscriptionRef.current = client.observeBool(
        'test-flag',
        false,
        () => {}
      );

      const next: DemoStatus = {
        ready: true,
        // The core called back into JS: it sent a request through the
        // transport and kept the install's anonymous id in the secure store
        hostCallbacks:
          mockTransport.requestCount > 0 &&
          mockSecureStore.readCount > 0 &&
          mockSecureStore.writeCount > 0,
        flagValue,
        observerRegistered: subscriptionRef.current !== null,
        purchaseLibrary: purchaseLibraryLoads(),
      };
      if (active) setStatus(next);

      console.log(
        [
          'COPRODUCT_EXPO_CONSUMER_STATUS',
          `ready=${next.ready}`,
          `hostCallbacks=${next.hostCallbacks}`,
          `flagValue=${next.flagValue}`,
          `observerRegistered=${next.observerRegistered}`,
          `purchaseLibrary=${next.purchaseLibrary}`,
        ].join(' ')
      );
    }

    runDemo().catch((error: unknown) => {
      console.error('COPRODUCT_EXPO_CONSUMER_ERROR', error);
    });

    return () => {
      active = false;
      subscriptionRef.current?.cancel();
      subscriptionRef.current = null;
    };
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Coproduct Expo consumer</Text>
      <Text>SDK ready: {status.ready ? 'yes' : 'no'}</Text>
      <Text>Host callbacks: {status.hostCallbacks ? 'yes' : 'no'}</Text>
      <Text>getBool: {String(status.flagValue)}</Text>
      <Text>
        Observer registered: {status.observerRegistered ? 'yes' : 'no'}
      </Text>
      <Text>
        Purchase library: {status.purchaseLibrary ? 'expo-iap' : 'missing'}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  title: { fontSize: 18, fontWeight: '600' },
});
