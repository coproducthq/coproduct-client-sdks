import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from 'react-native-coproduct';

type DemoStatus = {
  ready: boolean;
  hostCallbacks: boolean;
  flagValue: boolean;
  observerRegistered: boolean;
};

const initialStatus: DemoStatus = {
  ready: false,
  hostCallbacks: false,
  flagValue: false,
  observerRegistered: false,
};

function logStatus(status: DemoStatus): void {
  console.log(
    [
      'COPRODUCT_RN_DEMO_STATUS',
      `ready=${status.ready}`,
      `hostCallbacks=${status.hostCallbacks}`,
      `flagValue=${status.flagValue}`,
      `observerRegistered=${status.observerRegistered}`,
    ].join(' ')
  );
}

export default function App() {
  const clientRef = useRef<CoproductClient | null>(null);
  const subscriptionRef = useRef<Cancellable | null>(null);
  const [status, setStatus] = useState<DemoStatus>(initialStatus);

  useEffect(() => {
    let active = true;

    async function runDemo(): Promise<void> {
      const client = await Coproduct.initialize('cpk_mob_test_scaffold');
      clientRef.current = client;

      const flagValue = client.getBool('test-flag', false);

      subscriptionRef.current = client.observe('test-flag', false, () => {});

      const nextStatus: DemoStatus = {
        ready: true,
        hostCallbacks:
          mockTransport.requestCount === 1 &&
          mockSecureStore.completedHandshake,
        flagValue,
        observerRegistered: subscriptionRef.current !== null,
      };

      if (active) {
        setStatus(nextStatus);
      }

      logStatus(nextStatus);
    }

    runDemo().catch((error: unknown) => {
      console.error('COPRODUCT_RN_DEMO_ERROR', error);
    });

    return () => {
      active = false;
      subscriptionRef.current?.cancel();
      subscriptionRef.current = null;
    };
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Coproduct RN scaffold</Text>
      <Text>SDK ready: {status.ready ? 'yes' : 'no'}</Text>
      <Text>Host callbacks: {status.hostCallbacks ? 'yes' : 'no'}</Text>
      <Text>getBool: {String(status.flagValue)}</Text>
      <Text>
        Observer registered: {status.observerRegistered ? 'yes' : 'no'}
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
  title: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
});
