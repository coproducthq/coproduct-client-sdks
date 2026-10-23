import React, { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from '@coproduct/react-native-sdk';
import { bucketForVectors } from '@coproduct/react-native-sdk/internal';
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
      const client = await Coproduct.initialize('cpk_mob_0123456789abcdefghjkmnpqrstvwxyz');
      clientRef.current = client;

      const flagValue = client.getBool('test-flag', false);

      subscriptionRef.current = client.observeBool('test-flag', false, () => {});

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
      // The fixture also holds seed-form vectors, which the core's own
      // conformance test covers and the RN binding does not expose. An entry
      // in neither form fails the run rather than being skipped
      const entries = bucketingVectors as Array<Record<string, unknown>>;
      const isTriple = (v: Record<string, unknown>): boolean =>
        typeof v.rule_id === 'string' &&
        typeof v.targeting_key === 'string' &&
        typeof v.suffix === 'string' &&
        typeof v.expected_bucket === 'number';
      const isSeed = (v: Record<string, unknown>): boolean =>
        typeof v.seed === 'string' && typeof v.expected_bucket === 'number';
      const vectors = entries.filter(isTriple) as BucketingVector[];
      let bucketingPass =
        vectors.length > 0 && entries.every((v) => isTriple(v) || isSeed(v));
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
