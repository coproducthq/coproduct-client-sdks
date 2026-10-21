import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import {
  Coproduct,
  type Cancellable,
  type CoproductClient,
  mockSecureStore,
  mockTransport,
} from '@coproduct/react-native-sdk';
import {
  CoproductPaywall,
  type Entitlement,
  type PaywallClient,
  type PaywallLoadError,
  type PaywallPurchaseError,
  type PaywallSnapshot,
  type PurchaseResult,
} from '@coproduct/react-native-sdk/paywall';

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

// Google reserves this product id to always resolve as a successful
// one-time purchase through the real Play Store app, on any installed
// app, with no Play Console configuration -- used here so this demo can
// drive a real Play Billing purchase dialog without a published app or a
// backend paywall. It only covers a one-time purchase (kind: 'consumable'),
// not a subscription -- Google has no equivalent reserved subscription id.
const ANDROID_TEST_PRODUCT_ID = 'android.test.purchased';

// No real backend involved: fetchPaywall returns a fixed snapshot built
// in-memory, and recordPurchase/getEntitlements just log, so this demo
// exercises the real IapPaywallBridge and the real Play Billing dialog
// without needing a deployed Coproduct paywall.
class FakePaywallDemoClient implements PaywallClient {
  async fetchPaywall(paywallId: string): Promise<PaywallSnapshot | undefined> {
    return {
      paywallId,
      version: 1,
      templateType: 'hero_single_offer',
      content: {
        offeringKey: 'default',
        ctas: [{ packageKey: 'test', label: 'Buy test product' }],
        html: '<section><h1>Coproduct RN paywall demo</h1><a href="coproduct-action:purchase?packageKey=test">Buy test product</a></section>',
      },
      packages: {
        test: { androidProductId: ANDROID_TEST_PRODUCT_ID, kind: 'consumable' },
      },
      html: '<section></section>',
    };
  }

  async recordPurchase(args: {
    appUserId: string;
    platform: string;
    storeProductId: string;
    storeTransactionId: string;
    purchaseDate: Date;
    expiresDate?: Date;
  }): Promise<Entitlement[]> {
    console.log('COPRODUCT_RN_PAYWALL_DEMO_RECORD_PURCHASE', JSON.stringify(args));
    return [];
  }

  async getEntitlements(): Promise<Entitlement[]> {
    return [];
  }

  async identify(): Promise<void> {}
}

function logPaywallResult(result: PurchaseResult): void {
  console.log(
    'COPRODUCT_RN_PAYWALL_DEMO_STATUS',
    `outcome=${result.outcome}`,
    `productId=${result.productId ?? 'none'}`
  );
}

export default function App() {
  const clientRef = useRef<CoproductClient | null>(null);
  const subscriptionRef = useRef<Cancellable | null>(null);
  const [status, setStatus] = useState<DemoStatus>(initialStatus);
  const [showPaywall, setShowPaywall] = useState(false);
  const paywallClientRef = useRef(new FakePaywallDemoClient());

  useEffect(() => {
    let active = true;

    async function runDemo(): Promise<void> {
      const client = await Coproduct.initialize('cpk_mob_test_scaffold', {
        transport: mockTransport,
        secureStore: mockSecureStore,
      });
      clientRef.current = client;

      const flagValue = client.getBool('test-flag', false);

      subscriptionRef.current = client.observeBool(
        'test-flag',
        false,
        () => {}
      );

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

  if (showPaywall) {
    return (
      <CoproductPaywall
        paywallId="demo"
        appUserId="demo-user"
        sdkKey="cpk_mob_test_scaffold"
        platformScriptJs=""
        client={paywallClientRef.current}
        onPurchaseResult={logPaywallResult}
        onPurchaseError={(error: PaywallPurchaseError) =>
          console.error('COPRODUCT_RN_PAYWALL_DEMO_ERROR', error)
        }
        onLoadError={(error: PaywallLoadError) =>
          console.error('COPRODUCT_RN_PAYWALL_DEMO_LOAD_ERROR', error)
        }
        onDismiss={() => setShowPaywall(false)}
      />
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Coproduct RN scaffold</Text>
      <Text>SDK ready: {status.ready ? 'yes' : 'no'}</Text>
      <Text>Host callbacks: {status.hostCallbacks ? 'yes' : 'no'}</Text>
      <Text>getBool: {String(status.flagValue)}</Text>
      <Text>
        Observer registered: {status.observerRegistered ? 'yes' : 'no'}
      </Text>
      <Text onPress={() => setShowPaywall(true)} style={styles.link}>
        Show paywall demo
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
  link: {
    color: '#1a73e8',
    marginTop: 12,
  },
});
