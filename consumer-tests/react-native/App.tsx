import React, { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  computeBucket,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from 'react-native-coproduct';
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
  loadedFromCache: boolean;
  flagValue: boolean;
  observerFired: boolean;
};

const initial: DemoStatus = {
  ready: false,
  hostCallbacks: false,
  loadedFromCache: false,
  flagValue: false,
  observerFired: false,
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
      const loadedFromCache = client.wasLoadedFromCache();
      let observerFired = false;

      const observerPromise = new Promise<boolean>((resolve) => {
        let settled = false;
        subscriptionRef.current = client.observe('test-flag', false, () => {
          if (!settled) {
            settled = true;
            observerFired = true;
            resolve(true);
          }
        });
        setTimeout(() => {
          if (!settled) {
            settled = true;
            resolve(false);
          }
        }, 3000);
      });

      await client.simulateChange('test-flag', true);
      observerFired = await observerPromise;

      const next: DemoStatus = {
        ready: true,
        hostCallbacks:
          mockTransport.requestCount === 1 &&
          mockSecureStore.completedHandshake,
        loadedFromCache,
        flagValue,
        observerFired,
      };

      if (active) setStatus(next);

      console.log(
        [
          'COPRODUCT_RN_CONSUMER_STATUS',
          `ready=${next.ready}`,
          `hostCallbacks=${next.hostCallbacks}`,
          `loadedFromCache=${next.loadedFromCache}`,
          `flagValue=${next.flagValue}`,
          `observerFired=${next.observerFired}`,
        ].join(' ')
      );

      // Iterate the golden bucketing vectors through the real TurboModule and
      // emit a single tagged status line for the shell-script orchestrator
      const vectors: BucketingVector[] = bucketingVectors;
      let bucketingPass = true;
      for (const v of vectors) {
        const actual = computeBucket(v.rule_id, v.targeting_key, v.suffix);
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
      <Text>Loaded from cache: {status.loadedFromCache ? 'yes' : 'no'}</Text>
      <Text>getBool: {String(status.flagValue)}</Text>
      <Text>Observer fired: {status.observerFired ? 'yes' : 'no'}</Text>
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
