import React, { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from 'react-native-coproduct';
import { bucketForVectors } from 'react-native-coproduct/internal';
import bucketingVectors from '../../tests/bucketing_vectors.json';

type BucketingVector = {
  rule_id: string;
  targeting_key: string;
  suffix: string;
  expected_bucket: number;
};

type DemoStatus = {
  ready: boolean;
  hostCallbacks: boolean;
  flagValue: boolean;
  observerRegistered: boolean;
};

const initial: DemoStatus = {
  ready: false,
  hostCallbacks: false,
  flagValue: false,
  observerRegistered: false,
};

export default function App(): React.JSX.Element {
  const clientRef = useRef<CoproductClient | null>(null);
  const subscriptionRef = useRef<Cancellable | null>(null);
  const [status, setStatus] = useState<DemoStatus>(initial);

  useEffect(() => {
    let active = true;

    async function runDemo(): Promise<void> {
      const client = await Coproduct.initialize('cpk_mob_test_consumer');
      clientRef.current = client;

      const flagValue = client.getBool('test-flag', false);

      subscriptionRef.current = client.observe('test-flag', false, () => {});

      const next: DemoStatus = {
        ready: true,
        hostCallbacks:
          mockTransport.requestCount === 1 &&
          mockSecureStore.completedHandshake,
        flagValue,
        observerRegistered: subscriptionRef.current !== null,
      };

      if (active) setStatus(next);

      console.log(
        [
          'COPRODUCT_RN_CONSUMER_STATUS',
          `ready=${next.ready}`,
          `hostCallbacks=${next.hostCallbacks}`,
          `flagValue=${next.flagValue}`,
          `observerRegistered=${next.observerRegistered}`,
        ].join(' ')
      );

      // Iterate the golden bucketing vectors through the real TurboModule and
      // emit a single tagged status line for the shell-script orchestrator
      const vectors: BucketingVector[] = bucketingVectors;
      let bucketingPass = true;
      for (const v of vectors) {
        const actual = bucketForVectors(v.rule_id, v.targeting_key, v.suffix);
        if (actual !== v.expected_bucket) {
          bucketingPass = false;
        }
      }
      console.log(
        `COPRODUCT_RN_VECTOR_STATUS pass=${bucketingPass} count=${vectors.length}`
      );
    }

    runDemo().catch((error: unknown) => {
      console.error('COPRODUCT_RN_CONSUMER_ERROR', error);
    });

    return () => {
      active = false;
      subscriptionRef.current?.cancel();
      subscriptionRef.current = null;
    };
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Coproduct RN consumer</Text>
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
  title: { fontSize: 18, fontWeight: '600', marginBottom: 8 },
});
