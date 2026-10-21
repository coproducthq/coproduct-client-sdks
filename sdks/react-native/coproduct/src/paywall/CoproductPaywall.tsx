import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Platform, StyleSheet, View } from 'react-native';
import { WebView } from 'react-native-webview';
import { HttpPaywallClient } from './httpPaywallClient';
import { IapPaywallBridge } from './iapPaywallBridge';
import type { PaywallSnapshot } from './models/paywallSnapshot';
import type { NativePaywallBridge } from './nativePaywallBridge';
import type { PaywallClient } from './paywallClient';
import {
  PaywallRuntime,
  type PurchaseErrorCallback,
  type PurchaseResultCallback,
} from './paywallRuntime';
import { assemblePaywallShell } from './paywallShellAssembler';
import { platformScriptJs as bundledPlatformScriptJs } from './platformScript.generated';

export interface PaywallLoadError {
  message: string;
}

export interface CoproductPaywallProps {
  paywallId: string;
  appUserId: string;
  sdkKey: string;
  platformScriptJs: string;
  envSlug?: string;
  onPurchaseResult?: PurchaseResultCallback;
  onPurchaseError?: PurchaseErrorCallback;
  onLoadError?: (error: PaywallLoadError) => void;
  onDismiss?: () => void;
  client?: PaywallClient;
  bridge?: NativePaywallBridge;
}

// Renders and drives one resolved paywall: fetches it, loads its html into a
// WebView, resolves and injects live StoreKit2 prices, and completes a
// purchase or restore when the user taps a cta. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/coproduct_paywall.dart.
/**
 * The purchase bridge a paywall uses, or undefined after reporting why there
 * is none. Building the default bridge loads react-native-iap, an optional
 * peer, so an app without it gets onLoadError and a logged message naming the
 * install command, rather than a rejection inside the boot effect that would
 * leave the paywall blank
 */
export function createBridge(
  override: NativePaywallBridge | undefined,
  onLoadError: ((error: PaywallLoadError) => void) | undefined
): NativePaywallBridge | undefined {
  if (override != null) return override;
  try {
    return new IapPaywallBridge();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    onLoadError?.({ message });
    return undefined;
  }
}

/**
 * Maps React Native's Platform.OS to the platform string PaywallRuntime
 * and the backend's purchase-recording API expect. Every non-Android OS
 * name (ios, macos, windows, ...) maps to IOS -- the only two store
 * integrations this feature has are Apple's and Google's.
 */
export function platformFor(osName: string): string {
  return osName === 'android' ? 'ANDROID' : 'IOS';
}

export function CoproductPaywall(props: CoproductPaywallProps) {
  const {
    paywallId,
    appUserId,
    sdkKey,
    platformScriptJs,
    envSlug,
    onPurchaseResult,
    onPurchaseError,
    onLoadError,
    onDismiss,
    client: clientOverride,
    bridge: bridgeOverride,
  } = props;
  const [html, setHtml] = useState<string | undefined>(undefined);
  const runtimeRef = useRef<PaywallRuntime | undefined>(undefined);
  const webViewRef = useRef<WebView | null>(null);
  const loadedSnapshotRef = useRef<PaywallSnapshot | undefined>(undefined);

  const boot = useCallback(async (): Promise<void> => {
    const client = clientOverride ?? new HttpPaywallClient({ sdkKey, envSlug });
    const bridge = createBridge(bridgeOverride, onLoadError);
    if (bridge == null) return;

    let snapshot: PaywallSnapshot | undefined;
    try {
      snapshot = await client.fetchPaywall(paywallId);
    } catch (error) {
      onLoadError?.({ message: String(error) });
      return;
    }
    if (snapshot == null) {
      onLoadError?.({ message: 'Paywall not found for this environment.' });
      return;
    }

    const reportResultToWebView = (
      state: 'success' | 'cancel' | 'fail',
      message?: string
    ) => {
      try {
        webViewRef.current?.injectJavaScript(
          `window.__coproductOnPurchaseResult__(${JSON.stringify(state)}, ${JSON.stringify(message ?? null)}); true;`
        );
      } catch {
        // The WebView may already be torn down by the time this fires
      }
    };

    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId,
      platform: platformFor(Platform.OS),
      setPrices: async (prices) => {
        try {
          webViewRef.current?.injectJavaScript(
            `window.__coproductSetPrices__(${JSON.stringify(prices)}); true;`
          );
        } catch {
          // The WebView may already be torn down by the time prices resolve
        }
      },
      // The default [data-cp-result] sections (success/cancel/fail) own
      // showing the outcome and, for cancel/fail, waiting for the user's own
      // dismiss tap -- success auto-dismisses itself after a brief hold.
      // onDismiss (not onPurchaseResult/onPurchaseError) is therefore the
      // single place a host app should navigate away from the paywall.
      onPurchaseResult: (result, entitlements) => {
        if (result.outcome === 'success') {
          reportResultToWebView('success');
        } else if (result.outcome === 'pending') {
          reportResultToWebView('cancel', 'Waiting for approval.');
        } else {
          reportResultToWebView('cancel');
        }
        onPurchaseResult?.(result, entitlements);
      },
      onPurchaseError: (error) => {
        reportResultToWebView('fail');
        onPurchaseError?.(error);
      },
      onDismiss,
    });
    runtimeRef.current = runtime;
    loadedSnapshotRef.current = snapshot;

    const shellHtml = assemblePaywallShell({
      bodyHtml: snapshot.html,
      platformScriptJs,
    });
    setHtml(shellHtml);
  }, [
    appUserId,
    bridgeOverride,
    clientOverride,
    envSlug,
    onDismiss,
    onLoadError,
    onPurchaseError,
    onPurchaseResult,
    paywallId,
    platformScriptJs,
    sdkKey,
  ]);

  useEffect(() => {
    // Deliberately not awaited: a mount effect cannot be async, and the
    // boot sequence's own state updates (setHtml) are what the render
    // path reacts to.
    // eslint-disable-next-line no-void
    void boot();
    // Boots once per mount, matching Flutter's one-shot initState boot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (html == null) {
    return (
      <View style={styles.splashContainer}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <View style={styles.flexContainer}>
      {/* The explicit <object> type argument is load-bearing -- see
          CoproductOnboardingFlow.tsx's identical comment for why. */}
      <WebView<object>
        ref={webViewRef}
        originWhitelist={['*']}
        source={{ html }}
        onLoadEnd={() => {
          // Price injection runs JS against the page's own global, so it
          // must wait for the inline <script> to have actually executed --
          // firing right after the shell is assembled (before the WebView
          // has painted) races a cold WebView's first paint and can
          // silently miss, especially since a cached StoreKit price can
          // resolve faster than that paint. Mirrors Flutter's
          // onPageFinished placement exactly.
          const snapshot = loadedSnapshotRef.current;
          if (snapshot != null) {
            // eslint-disable-next-line no-void
            void runtimeRef.current?.onSnapshotLoaded(snapshot);
          }
        }}
        onShouldStartLoadWithRequest={(request) => {
          const runtime = runtimeRef.current;
          const isAction = request.url.startsWith('coproduct-action:');
          if (isAction && runtime != null) {
            // eslint-disable-next-line no-void
            void runtime.handleNavigationRequest(request.url);
          }
          return !isAction;
        }}
      />
    </View>
  );
}

// Loads the platform script bundled as this package's own generated source.
// Mirrors CoproductOnboardingFlow.loadPlatformScript -- stays async-shaped
// for call-site parity with Flutter, even though this implementation does
// zero I/O.
CoproductPaywall.loadPlatformScript = async (): Promise<string> =>
  bundledPlatformScriptJs;

const styles = StyleSheet.create({
  splashContainer: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  flexContainer: { flex: 1 },
});
