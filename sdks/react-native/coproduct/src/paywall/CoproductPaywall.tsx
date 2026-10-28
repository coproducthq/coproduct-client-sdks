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
import { snapshotCache, snapshotCacheKey } from './snapshotCache';

export interface PaywallLoadError {
  message: string;
}

export interface PaywallPrefetchArgs {
  paywallId: string;
  sdkKey: string;
  envSlug?: string;
  client?: PaywallClient;
}

// Minimal flag-reader surface this module needs from the base client, declared
// structurally so the paywall module keeps its independence from the base SDK.
// The base CoproductClient satisfies it.
export interface FlagReader {
  getString(key: string, defaultValue: string): string;
}

export interface PaywallPrefetchPlacementsArgs {
  client: FlagReader;
  flagKeys: string[];
  sdkKey: string;
  envSlug?: string;
  paywallClient?: PaywallClient;
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
  // The WebView is mounted hidden and revealed only once it has painted its
  // html and had live prices applied. Until then the loading indicator stays
  // on top, so the user never sees the WebView's blank first paint (a white
  // flash on iOS) nor the half-rendered, price-less intermediate frame.
  const [visible, setVisible] = useState(false);
  const runtimeRef = useRef<PaywallRuntime | undefined>(undefined);
  const webViewRef = useRef<WebView | null>(null);
  const loadedSnapshotRef = useRef<PaywallSnapshot | undefined>(undefined);
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined
  );

  const boot = useCallback(async (): Promise<void> => {
    const client = clientOverride ?? new HttpPaywallClient({ sdkKey, envSlug });
    const bridge = createBridge(bridgeOverride, onLoadError);
    if (bridge == null) return;

    const cacheKey = snapshotCacheKey(paywallId, envSlug);
    let snapshot: PaywallSnapshot | undefined;
    try {
      snapshot = await snapshotCache.resolve(cacheKey, () =>
        client.fetchPaywall(paywallId)
      );
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
        // Prices are the last thing to land, so the paywall is now fully
        // formed -- reveal it. onLoadEnd's fallback timer still covers the
        // case where prices never resolve (e.g. the store is unreachable).
        setVisible(true);
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

    // Hang guard only. The paywall is revealed when its content has actually
    // painted (onLoadEnd) or its prices land (setPrices) -- never on a fixed
    // delay, because the WebView is transparent while hidden, so revealing it
    // before it has painted shows through to the host background (a black gap)
    // until paint catches up. This timer exists solely so a WebView that never
    // fires onLoadEnd (load hung, no network) still reveals rather than
    // spinning forever; it is deliberately far longer than any real load.
    if (revealTimerRef.current != null) clearTimeout(revealTimerRef.current);
    revealTimerRef.current = setTimeout(() => setVisible(true), 8000);
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
    return () => {
      if (revealTimerRef.current != null) clearTimeout(revealTimerRef.current);
    };
    // Boots once per mount, matching Flutter's one-shot initState boot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The WebView is mounted as soon as the html exists but stays hidden
  // (opacity 0, transparent background) beneath the loading indicator until
  // `visible` flips. This loads and paints it off-screen, so revealing it is
  // a single cut from spinner to a fully-formed, priced paywall rather than
  // the white-flash -> half-ui -> full-ui sequence a plain mount shows.
  return (
    <View style={styles.flexContainer}>
      {html != null && (
        /* The explicit <object> type argument is load-bearing -- see
           CoproductOnboardingFlow.tsx's identical comment for why. */
        <WebView<object>
          ref={webViewRef}
          originWhitelist={['*']}
          source={{ html }}
          style={[styles.webView, { opacity: visible ? 1 : 0 }]}
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
            // The whole document (including external resources) has loaded, so
            // reveal if the cap in boot has not already. setPrices reveals
            // sooner once prices land.
            setVisible(true);
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
      )}
      {!visible && (
        <View style={[styles.splashContainer, StyleSheet.absoluteFill]}>
          <ActivityIndicator />
        </View>
      )}
    </View>
  );
}

// Loads the platform script bundled as this package's own generated source.
// Mirrors CoproductOnboardingFlow.loadPlatformScript -- stays async-shaped
// for call-site parity with Flutter, even though this implementation does
// zero I/O.
CoproductPaywall.loadPlatformScript = async (): Promise<string> =>
  bundledPlatformScriptJs;

/**
 * Fetches a paywall's snapshot and holds it in a process-level cache so a
 * later CoproductPaywall for the same id and environment renders without a
 * network round-trip. Call this once at app launch (right after the SDK is
 * initialized) for any paywall the user is likely to reach, so the first open
 * is instant instead of showing a spinner while the snapshot downloads.
 *
 * Best-effort: a failed fetch is swallowed, leaving the cache cold so the
 * paywall's own boot() fetches and reports errors normally. Safe to call more
 * than once; a later call simply refreshes the cached snapshot.
 */
CoproductPaywall.prefetch = async (
  args: PaywallPrefetchArgs
): Promise<void> => {
  const client =
    args.client ??
    new HttpPaywallClient({ sdkKey: args.sdkKey, envSlug: args.envSlug });
  await snapshotCache.warm(snapshotCacheKey(args.paywallId, args.envSlug), () =>
    client.fetchPaywall(args.paywallId)
  );
};

// Warms every paywall the given placement flags currently resolve to. A
// placement is an ordinary string flag whose value is a paywallId, resolved
// here through the base client so targeting is respected. Call once at launch
// with the app's paywall flag keys. Best-effort; failures leave the cache cold.
CoproductPaywall.prefetchPlacements = async (
  args: PaywallPrefetchPlacementsArgs
): Promise<void> => {
  const paywallClient =
    args.paywallClient ??
    new HttpPaywallClient({ sdkKey: args.sdkKey, envSlug: args.envSlug });
  const seen = new Set<string>();
  await Promise.all(
    args.flagKeys.map(async (flagKey) => {
      const paywallId = args.client.getString(flagKey, '');
      if (paywallId.length === 0 || seen.has(paywallId)) return;
      seen.add(paywallId);
      await snapshotCache.warm(
        snapshotCacheKey(paywallId, args.envSlug),
        () => paywallClient.fetchPaywall(paywallId)
      );
    })
  );
};

const styles = StyleSheet.create({
  splashContainer: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  flexContainer: { flex: 1 },
  // Transparent so the WebView's own blank first paint is never a white flash:
  // while hidden there is nothing to see through to but the host background,
  // and the paywall html paints its own (dark) background once loaded.
  webView: { flex: 1, backgroundColor: 'transparent' },
});
