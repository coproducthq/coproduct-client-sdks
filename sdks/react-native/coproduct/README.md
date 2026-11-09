<img src="https://raw.githubusercontent.com/coproducthq/coproduct-client-sdks/main/docs/images/coproduct-logo.png" alt="coproduct.app" width="301">

# React Native Integration

## **For Humans to Get Started**

### **Get started in 2 minutes (do not skip)**

1. **Sign up** at [coproduct.app](https://coproduct.app).
2. **Configure MCP** in Claude Code:
   ```bash
   claude mcp add --transport http coproduct https://mcp.coproduct.app/mcp
   ```
3. **Prompt** your agent opened in your app code directory: `Integrate @coproduct/react-native-sdk`
   - Generates your project key and wires the SDK into your app.
4. **Prompt** your agent: `Create a new onboarding with 5 steps`
5. **Prompt** your agent: `Rebuild and open the app`

**Manual setup (no agent):** for an Expo app, jump to [Expo](#expo). For a bare React Native app, start at [Installation](#installation).

### **Agentic integration mindset**

Coproduct is built from the ground up for agentic coding.  
Traditional developer platforms expect humans to manually click through web dashboards: opening a browser, generating API keys in settings, creating feature flags in an admin UI, copying and pasting secrets into code, and toggling release percentages by hand.  
Coproduct is designed for developers using AI coding agents, including Claude Code, Codex, Cursor, and any MCP-compatible assistant connected to the Coproduct MCP server:

* Zero dashboard context switching: Your AI agent creates feature flags, sets targeting rules, generates environment SDK keys, authors multi-step onboarding flows, and configures paywalls directly from conversational prompts in your editor.  
* Synchronized remote and local development: While your agent executes remote platform actions via Coproduct MCP tools, it simultaneously writes, wires, and verifies the corresponding React Native client code in your project.  
* Ship without leaving your workspace: You define intent in plain English, your agent invokes the required MCP tools and modifies your codebase, and changes are ready to test immediately.

This guide is organized around this agentic mindset: hand the prompts to your agent, let it configure remote state and write the client integration, and use the code references to review and verify.

### **Connecting Coproduct to your AI coding tool**

Connect Coproduct as an MCP server and your agent can manage flags, targeting rules, and environments directly from chat.  
In Claude Code, run this from your terminal:

```bash
claude mcp add --transport http coproduct https://mcp.coproduct.app/mcp
```

Or add it manually in your MCP settings:

```json
{
  "mcpServers": {
    "coproduct": {
      "url": "https://mcp.coproduct.app/mcp"
    }
  }
}
```

In Claude Desktop, you can also add Coproduct from the [Claude connectors directory](https://claude.com/docs/connectors/directory).

For other MCP-compatible tools (Cursor, Codex, etc.), add https://mcp.coproduct.app/mcp as an HTTP MCP server in your tool’s configuration.  
When you first use a Coproduct tool, your agent will prompt you to sign in and grant access. Approve the request in the browser — you’ll be redirected back automatically.

### **Getting your SDK key & environments**

Each environment in Coproduct has its own mobile SDK key. A key starts with `cpk_mob_` followed by 32 lowercase letters and digits. SDK keys are generated exclusively through your AI coding tool via the Coproduct MCP integration — there is no manual button to generate keys in the dashboard.

#### **1. Prompt your agent to generate the key**

Ask your agent to issue a key for the environment you are integrating:

```prompt
Generate a mobile SDK key for the development environment.
```

Your agent calls create_sdk_key and provides your environment key (cpk_mob_...).  
IMPORTANT  
The SDK key is revealed only once upon generation. Save it immediately in a private location, such as a local env file that git ignores (`.env.local` in Expo) or your team’s secrets manager, and never commit it. Coproduct never shows the full key again.

#### **2. If you forgot or lost the key**

Raw keys cannot be retrieved after generation. If you lose or forget your key, prompt your agent to rotate or reset it:

```prompt
Rotate my mobile SDK key for the development environment.
```

Tools invoked: rotate_sdk_key  
Your agent initiates a rotation and returns a one-time confirmation link. Opening the link confirms the action, invalidates the old key across all active sessions, and reveals the new replacement key.

#### **Separate keys per environment**

Use the key corresponding to the environment you want flags evaluated against:

* Development or Staging — use while building features, debugging locally, and running test suites.  
* Production — use in release builds published to TestFlight, the App Store, or Google Play.

Never hardcode or commit keys into source control. Keep the key in an env file that git ignores and read it at build time. In Expo, put it in `.env.local` as `EXPO_PUBLIC_COPRODUCT_SDK_KEY`: Expo's default `.gitignore` covers `.env*.local` but not `.env`. In a bare React Native app, put it in a `.env` file that you add to your `.gitignore`, and read it through [react-native-config](https://github.com/lugg/react-native-config). A plain `process.env.COPRODUCT_SDK_KEY` is undefined at runtime in both. A mobile key ships inside your app, so this keeps it out of source control rather than secret.

## **Requirements**

| React Native | 0.84+ |
| :---- | :---- |
| Architecture | New Architecture (TurboModules / Bridgeless) |
| iOS | 15.0+ |
| Android | API 24+ |

Expo SDK 56 and later meet the React Native requirement and always use the New Architecture, so they need no extra setup for it.

## **Installation**

### **Prompting your agent**

Ask your agent to install the packages and sync iOS dependencies:

```prompt
Install @coproduct/react-native-sdk and its required native packages from npm,
using the command in the SDK's manual reference. If the app will show
paywalls, also install the paywall packages listed there.

Then run pod install for iOS. In an Expo app, install with npx expo install
and run npx expo prebuild instead, as the SDK's Expo section describes.
```

### **Manual reference**

Install the SDK with the native packages it requires. React Native links native code only for packages listed in your app's own `package.json`, so each one is installed explicitly:

```bash
npm install @coproduct/react-native-sdk @react-native-async-storage/async-storage @react-native-community/netinfo react-native-device-info react-native-fs react-native-keychain react-native-permissions react-native-webview
```

If your app shows paywalls, also install the purchase packages. An app that uses only flags or onboarding can leave them out, which also keeps Google Play's billing permission out of your Android app:

```bash
npm install react-native-iap react-native-nitro-modules
```

In a bare React Native app, install the iOS pods next. Expo apps skip this step, because `npx expo prebuild` installs them (see [Expo](#expo)):

```bash
cd ios && pod install
```

The SDK requires React Native 0.84 or later. In an app on an earlier release, npm stops the install with a peer dependency conflict, and Yarn and pnpm warn. Earlier releases fail to build under Xcode 26 once the paywall's purchase packages are installed.

### **Expo**

The SDK ships native code, so it runs in an Expo [development build](https://docs.expo.dev/develop/development-builds/introduction/), not in Expo Go. Expo Go can't load native modules that aren't bundled with it.

1. Install the SDK and its native packages with `npx expo install`, which picks the versions of packages such as `@react-native-community/netinfo` and `react-native-webview` that match your Expo SDK:

   ```bash
   npx expo install @coproduct/react-native-sdk @react-native-async-storage/async-storage @react-native-community/netinfo react-native-device-info react-native-fs react-native-keychain react-native-permissions react-native-webview
   ```

   `npx expo install` also adds a `react-native-permissions` entry to the `plugins` list in `app.json`.

2. Put your key in `.env.local` at the project root. Expo's default `.gitignore` covers `.env*.local`, so the key stays out of git:

   ```bash
   EXPO_PUBLIC_COPRODUCT_SDK_KEY=cpk_mob_your_key_here
   ```

   EAS Build doesn't upload `.env.local`, because git ignores it. For EAS builds, set the variable in EAS instead. A build reads the EAS environment its profile names in `eas.json`. Without one, a profile with `developmentClient: true` reads `development`, a store build reads `production`, and any other build reads `preview`. Set the key in each environment you build:

   ```bash
   eas env:set --name EXPO_PUBLIC_COPRODUCT_SDK_KEY --value cpk_mob_your_key_here --environment development --visibility plaintext
   eas env:set --name EXPO_PUBLIC_COPRODUCT_SDK_KEY --value cpk_mob_your_key_here --environment preview --visibility plaintext
   eas env:set --name EXPO_PUBLIC_COPRODUCT_SDK_KEY --value cpk_mob_your_key_here --environment production --visibility plaintext
   ```

3. Generate the native projects, then build and run the app:

   ```bash
   npx expo prebuild
   npx expo run:ios
   npx expo run:android
   ```

   `npx expo prebuild` writes the `ios` and `android` folders and installs the iOS pods. Each run command builds the app, starts the development server, and keeps running. Run one platform at a time: stop it with Ctrl+C before you run the other, or run the other from a second terminal. The second command reuses the running development server, so logs from both apps appear in the first terminal.

## **Basic integration**

Initialize the SDK once at app startup — typically in your root component or app bootstrap script.

### **Prompting your agent**

```prompt
Initialize the Coproduct client at app startup, reading the SDK key from the
app's build configuration: EXPO_PUBLIC_COPRODUCT_SDK_KEY in Expo, or
Config.COPRODUCT_SDK_KEY from react-native-config in a bare React Native app.

Use the useCoproduct hook from the SDK's code reference so the rest of the app
can read flags.
```

### **Code reference**

Add a `useCoproduct` hook in its own file, for example `src/lib/coproduct.ts`. Keep it outside `src/app`: in the default Expo template, every file under `src/app` becomes a route.

```typescript
import { useEffect, useState } from 'react';
import Coproduct, {
  LifecycleEvent,
  ProviderState,
  type Cancellable,
  type CoproductClient,
} from '@coproduct/react-native-sdk';

// Write the variable name out in full. Expo replaces only this exact
// expression at build time
const sdkKey = process.env.EXPO_PUBLIC_COPRODUCT_SDK_KEY;

let shared: CoproductClient | null = null;
let starting: Promise<CoproductClient | null> | null = null;
// Keep the handler's handle. Dropping it removes the handler
let fatalWatch: Cancellable | null = null;
let warned = false;

function warnStopped() {
  if (warned) return;
  warned = true;
  console.warn(
    'Coproduct stopped fetching flags, so reads return your fallbacks. Check the SDK key.'
  );
}

function startCoproduct(): Promise<CoproductClient | null> {
  if (!starting) {
    const initializing = sdkKey
      ? Coproduct.initialize(sdkKey)
      : Promise.reject(new Error('The Coproduct SDK key is not set'));
    starting = initializing.then(
      (client) => {
        fatalWatch ??= client.addHandler(LifecycleEvent.Fatal, warnStopped);
        if (client.state === ProviderState.Fatal) warnStopped();
        shared = client;
        return client;
      },
      (error) => {
        console.error('Coproduct failed to initialize', error);
        return null;
      }
    );
  }
  return starting;
}

export function useCoproduct(): CoproductClient | null {
  const [client, setClient] = useState(shared);
  useEffect(() => {
    if (!client) startCoproduct().then(setClient);
  }, [client]);
  return client;
}
```

Call `useCoproduct()` wherever you need flags. The first call initializes the SDK, and later calls get the same client. If `initialize` fails, the hook logs the error once and returns `null`. If the SDK stops fetching flags, for example because the key was rejected, it logs a warning.

Then read flags in a component, for example `src/components/checkout-banner.tsx`:

```tsx
import { Text } from 'react-native';
import { useCoproduct } from '@/lib/coproduct';

export function CheckoutBanner() {
  const client = useCoproduct();
  const newCheckout = client?.getBool('new-checkout', false) ?? false;
  return <Text>{newCheckout ? 'New checkout' : 'Classic checkout'}</Text>;
}
```

Render `<CheckoutBanner />` on a screen, such as `src/app/index.tsx`, and import it with `import { CheckoutBanner } from '@/components/checkout-banner';`. The default Expo template maps `@/` to `src/`. In other apps, use a relative import.

This reads the flag once per render. To re-render when the flag changes, use `useFlag(useCoproduct(), 'new-checkout', false)` from [Reacting to flag changes](#reacting-to-flag-changes) instead.

In a bare React Native app, install [react-native-config](https://github.com/lugg/react-native-config) and follow its setup, then read the key from it instead of `process.env`:

```typescript
import Config from 'react-native-config';

const sdkKey = Config.COPRODUCT_SDK_KEY;
```

The SDK saves the last flag values it fetched on the device. This saved copy is the cached snapshot. `initialize` loads it right away, so the client is ready to use as soon as `initialize` resolves. Reads evaluate against the cached snapshot while the SDK fetches updates in the background.

## **Onboarding flows**

Coproduct allows authoring and publishing interactive, multi-step onboarding flows directly on the platform. The flow content is fetched dynamically at runtime — zero onboarding screen code or layouts need to be bundled into your binary.

### **Creating an onboarding flow**

Here is a realistic prompt asking your agent to integrate a 4-screen onboarding flow and wire up each screen’s native interactions:

```prompt
Create an OnboardingScreen component in React Native using
CoproductOnboardingFlow from @coproduct/react-native-sdk.

Connect it to the string flag welcome-onboarding, load the platform script with
CoproductOnboardingFlow.loadPlatformScript(), and handle each screen of our
4-step flow:

Screen 1 - Welcome & Value Proposition (welcome): Shows hero branding and
feature overview. User taps Get Started to advance…

Screen 2 - Persona Questionnaire (user-goals): Asks the user their primary
objective (e.g. Freelancer, Small Team, Enterprise). Answers are recorded
automatically…

Screen 3 - Notifications Opt-In (notifications-optin): Prompts the user to
enable alerts. Wire up onRequestPermission(notifications) to request native OS
notification permissions…

Screen 4 - Tailored Plan (plan-reveal): An author-configured wait for API screen
with an onLoad hook. Wire up onNativeOperation(fetchRecommendedPlan, params) to
compute a personalized tier from the Screen 2 answers, and call onFinish() when
onEvent receives flow_completed.
```

### **Code reference**

```tsx
import React, { useEffect, useState } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import type { CoproductClient as BaseCoproductClient } from '@coproduct/react-native-sdk';
import {  
  CoproductOnboardingFlow,  
  HttpOnboardingClient,  
  type CoproductClient as OnboardingAdapterClient,  
} from '@coproduct/react-native-sdk/onboarding';  
interface OnboardingScreenProps {  
  baseClient: BaseCoproductClient;  
  envSlug: string;  
  onFinish: () => void;  
}  
export function OnboardingScreen({ baseClient, envSlug, onFinish }: OnboardingScreenProps) {  
  const [platformScript, setPlatformScript] = useState<string | null>(null);  
  useEffect(() => {  
    CoproductOnboardingFlow.loadPlatformScript().then(setPlatformScript);  
  }, []);  
  if (!platformScript) {  
    return (  
      <View style={styles.center}>  
        <ActivityIndicator size="large" />  
      </View>  
    );  
  }  
  // Create the onboarding adapter connecting the base SDK with flow fetching  
  const onboardingClient: OnboardingAdapterClient = {  
    resolveStringFlag: (flagKey) => baseClient.getString(flagKey, '') || undefined,  
    fetchOnboardingFlow: (flowId) =>  
      new HttpOnboardingClient({ envSlug }).fetchOnboardingFlow(flowId),  
    sdkContextAttributes: { platform: 'ios' },  
    sdkContextSegmentKeys: new Set(),  
    refresh: async () => {},  
  };  
  return (  
    <View style={styles.container}>  
      <CoproductOnboardingFlow  
        flagKey="welcome-onboarding" // String flag that resolves to the target flowId  
        client={onboardingClient}  
        platformScriptJs={platformScript}  
        onEvent={async (event, screenId, answers) => {  
          // Tracks progression through screens:  
          // 'welcome' -> 'user-goals' -> 'notifications-optin' -> 'plan-reveal'  
          console.log(`[Onboarding] ${event} on screen '${screenId}'`, answers);  
          if (event === 'flow_completed' || event === 'flow_dismissed') {  
            onFinish();  
          }  
        }}  
        onRequestPermission={async (permission) => {  
          // Screen 3: called when the user taps the opt-in. The SDK shows the
          // OS permission dialog itself, so use this to sync your app's state
          if (permission === 'notifications') {  
            console.log('Notification permission requested from onboarding');  
          }  
        }}  
        onNativeOperation={async (operation, params): Promise<Record<string, string>> => {  
          // Screen 4: Handles 'onLoad' operations ("wait for API" before showing screen)  
          if (operation === 'fetchRecommendedPlan') {  
            console.log('Calculating personalized plan with answers:', params);  
            // Example response injected back into the flow's answers  
            return {  
              tier: 'pro_annual',  
              discountCode: 'WELCOME20',  
              headline: 'Recommended for Growing Teams',  
            };  
          }  
          return { status: 'error', message: `Unhandled operation: ${operation}` };  
        }}  
      />  
    </View>  
  );  
}  
const styles = StyleSheet.create({
  container: { flex: 1 },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
});
```

* Runtime content loading — the flow graph is retrieved from the edge CDN via HttpOnboardingClient based on the flow ID pointed to by flagKey.  
* Automatic progress persistence — answers and the current screen are preserved in on-device storage; resuming an interrupted flow happens seamlessly.  
* Debug drawer — in __DEV__ builds, a built-in overlay allows refreshing content or resetting progress to test the experience end-to-end.

### **Native interactions & lifecycle callbacks**

The WebView renders platform-authored UI, but all device capabilities and native events are handed back to your React Native app through typed callbacks:

#### **1. Asking for permissions (onRequestPermission)**

Authored screens can prompt the user for native OS permissions (e.g. a push notification opt-in screen, camera upload screen, or location permissions):

* Built-in capability: When a user taps a CTA configured to request a permission, the runtime translates it to an OS request. Under the hood, Coproduct maps standard permissions (notifications, camera, photos, location, microphone) directly to native platform permission dialogs.  
* Custom handling: Supply onRequestPermission: (permission: string) => Promise<void>, which is called when a screen asks for a permission, to keep your app’s own permission state or third-party wrappers (like react-native-permissions) in step.  
* Conditional branching: Subsequent screens or transitions can branch on the result of the SDK’s built-in permission request, granted or denied.

#### **2. Waiting for API calls (onNativeOperation & onLoad)**

Onboarding screens frequently need data that doesn’t exist until the user answers prior questions — such as computing a custom diet plan, querying a credit limit, or reserving a username.

* The onLoad hook: In the Coproduct dashboard, any screen can be configured with an onLoad operation name (e.g. operation: "fetchRecommendedPlan", timeoutMs: 5000).  
* Instant suspension: The moment the user navigates to that screen, the flow pauses and presents a native loading spinner while calling your app’s onNativeOperation(operation, params).  
* Answers returned to the flow: Your handler returns a key-value dictionary (e.g. { tier: "pro_annual", discount: "20%" }). The SDK resolves the request, and the values are injected into the flow’s state under answers.  
* Dynamic screen rendering: The loaded screen and all subsequent screens can display the returned values dynamically using data bindings (such as <span data-cp-answer="tier"></span>), or route users down different paths based on the returned values.

#### **3. Event callbacks & analytics (onEvent)**

Every screen transition and user interaction emits a lifecycle event through onEvent(event, screenId, answers):

* Events emitted:  
  * screen_viewed — fires whenever a screen is rendered.  
  * action_tapped — fires when buttons, choice cards, or inputs are tapped.  
  * flow_completed — fires when the user successfully reaches the end of the onboarding flow.  
  * flow_dismissed — fires when the user taps a close or skip button.  
* Cumulative answers dictionary: Every event carries all answers collected up to that moment (form inputs, choice selections, and native API responses).  
* Analytics integration: Plug onEvent directly into your analytics pipeline (PostHog, Segment, Mixpanel, Firebase) to track conversion funnels without manual instrumentation across individual screens.

#### **4. URL and paywall transitions**

* onOpenUrl(url): Triggered when users tap external links (such as Privacy Policy or Terms of Service URLs), allowing you to open them in an in-app browser or native modal.  
* onShowPaywall(paywallId): Triggered when an onboarding flow finishes with a purchase CTA, letting you immediately transition the user into <CoproductPaywall paywallId={paywallId} ... />.

### **Viewing and inspecting in the dashboard**

Every onboarding flow can be reviewed and previewed in the [Coproduct dashboard](https://dash.coproduct.app) under Onboarding:

* Visual flow inspection — explore the screen graph, screen transitions, default navigation branches, and onLoad asynchronous hooks.  
* Interactive preview — click through the experience as a user would, previewing copy, form inputs, and animations before releasing.  
* Deployment status — see exactly which draft or published version is pinned to each environment (Development, Production).

### **Multiple onboarding flows & variant testing**

Because an onboarding flag (e.g. welcome-onboarding) is a standard Coproduct string flag, its variations return flow IDs (flowId). This enables you to deploy multiple onboarding flows and test them across different variations and user segments without changing any mobile code:

* A/B test onboarding journeys: Point variation A to flow-express (e.g. 2 quick screens) and variation B to flow-guided (e.g. 4 interactive screens). Split traffic 50/50 with a percentage rollout rule to see which yields higher completion and sign-up conversion.  
* Segment-specific onboarding: Serve tailored onboarding experiences depending on user attributes — such as showing a B2B flow for users with corporate email domains, or a simplified flow for mobile users coming from specific marketing campaigns.  
* Zero app updates: Swap variations, point to a brand-new flow, or change targeting rules remotely. The app simply queries the flag and immediately loads whichever flow ID it resolves to.

#### **Prompting your agent for variant testing**

```prompt
Configure our string flag welcome-onboarding with two variations: short-flow
(value: flow-quick-v1) and deep-flow (value: flow-interactive-v2).

Split rollout 50/50 across both variations in production.
```

Tools invoked: create_flag → add_targeting_rule (50% rollout split) → publish_environment

## **Paywalls**

Coproduct paywalls render web-driven, design-system-consistent paywall layouts while delegating transactions and pricing to native in-app purchases (StoreKit 2 on iOS, Google Play Billing on Android).

### **Designing a paywall**

With Coproduct, developers and growth teams never need to hand-code native billing screens, pricing tables, or complex layout variants in React Native. Instead, you instruct your AI coding agent (Claude Code, Cursor, Codex) to design, style, and publish the paywall directly.  
The agent defines entitlements, configures offerings across subscription tiers, selects an optimal layout template, and writes custom HTML, CSS, and copy tailored to your brand.

#### **Prompting your agent to design a paywall**

```prompt
Design a high-converting annual subscription paywall for pro access in project
my-app.

Use a feature comparison layout comparing Free and Pro tiers, highlight a 7-day
free trial on the annual plan with a 40 percent savings badge, set up an
alternative monthly option, and include restore purchases and terms links.
```

Tools invoked: create_entitlement → create_product → create_offering → create_paywall_template → update_paywall_content → deploy_paywall

#### **Paywall templates and data attributes**

Your agent can scaffold paywalls using conversion-tested templates or generate completely custom layouts:

* Hero single offer (hero_single_offer): Focuses user attention on a single high-value tier, ideal for direct trial-to-paid conversions.  
* Feature comparison (feature_comparison): Side-by-side comparison matrix highlighting differences between Free and Pro tiers.  
* Plan grid (plan_grid): Multi-card layout presenting monthly, annual, and lifetime tiers side by side.

Interactive paywall behaviors (purchases, restores, dismissals) and live price placements are wired using standard Coproduct data attributes. When the paywall renders in React Native, the SDK automatically connects native StoreKit 2 and Google Play Billing to these elements:

* data-cp-action="purchase": Triggers native in-app purchase for the target package.  
* data-package-key="annual": Links the button or card to a specific package defined in the offering.  
* data-cp-price-for="annual": Injects live localized pricing and trial terms directly from StoreKit 2 / Google Play.  
* data-cp-action="restore": Triggers transaction restore with Apple or Google Play.  
* data-cp-action="dismiss": Dismisses the paywall modal.

### **Store authorization & App Store Connect setup**

To enable server-driven paywalls with automated product syncing and receipt validation, authorize Coproduct with your store developer accounts:

* In the [Coproduct dashboard](https://dash.coproduct.app), navigate to Settings → Integrations → App Store Connect.  
* In App Store Connect (Users and Access → Integrations → App Store Connect API), create an API Key with App Manager permissions.  
* Link your Issuer ID, Key ID, and downloaded private key (.p8), or ask your agent:

```prompt
Connect our App Store Connect credentials using our Issuer ID, Key ID, and
private key for project my-app.
```

Tools invoked: connect_app_store_credentials → select_app_store_app  
Once authorized, Coproduct can create and sync subscription products, validate transactions, and record entitlement grants directly with Apple and Google Play.

### **Changing pricing from prompts & dashboard (syncs to App Store Connect)**

With Coproduct paywalls, subscription pricing and package configurations are completely decoupled from your app binary, and price updates can be pushed to App Store Connect directly from an AI prompt or the dashboard:

#### **Changing prices from an agent prompt**

You can instruct your AI coding tool to change product prices in chat:

```prompt
Update the price of our iOS subscription product com.myapp.pro.annual to 49.99
USD in project my-app.
```

Tools invoked: update_product

When App Store Connect is connected, Coproduct pushes the new reference price directly to Apple via the App Store Connect API. Because price changes to existing approved subscriptions do not require a new app review, the updated price tier reflects in App Store Connect near-instantly.

#### **Changing prices and offerings in the dashboard**

You can also adjust prices, add promotional discounts, or swap packages visually in the [Coproduct dashboard](https://dash.coproduct.app) under Paywalls → Products & Offerings:

* Zero App Store resubmissions: Change monthly or annual subscription prices, introduce lifetime tiers, or adjust free-trial durations without submitting an app update.  
* Dynamic StoreKit 2 price injection: When <CoproductPaywall /> renders on-device, it automatically queries native StoreKit 2 and Google Play Billing for the user’s localized currency prices and trial terms, then injects them into the paywall UI. Users worldwide always see prices formatted in their local currency.  
* Price elasticity & A/B testing: Test different price points (e.g. $4.99/mo vs. $6.99/mo) or swap offering layouts between user segments using Coproduct targeting rules.

### **Prompting your agent for React Native integration**

```prompt
Create a PaywallModal component using CoproductPaywall from
@coproduct/react-native-sdk/paywall. Make sure react-native-iap and
react-native-nitro-modules are installed first.

Pass the paywall ID premium-annual, current user ID, and SDK key.

Handle onPurchaseResult to unlock pro access when result.outcome is success, and
handle onDismiss.
```

### **Code reference**

```tsx
import React, { useEffect, useState } from 'react';
import { View, ActivityIndicator, StyleSheet, Modal } from 'react-native';
import { CoproductPaywall } from '@coproduct/react-native-sdk/paywall';
interface PaywallModalProps {  
  visible: boolean;  
  paywallId: string;  
  appUserId: string;  
  sdkKey: string;  
  onSuccess: () => void;  
  onClose: () => void;  
}  
export function PaywallModal({  
  visible,  
  paywallId,  
  appUserId,  
  sdkKey,  
  onSuccess,  
  onClose,  
}: PaywallModalProps) {  
  const [platformScript, setPlatformScript] = useState<string | null>(null);  
  useEffect(() => {  
    CoproductPaywall.loadPlatformScript().then(setPlatformScript);  
  }, []);  
  if (!visible || !platformScript) return null;  
  return (  
    <Modal visible={visible} animationType="slide" onRequestClose={onClose}>  
      <View style={styles.container}>  
        <CoproductPaywall  
          paywallId={paywallId}  
          appUserId={appUserId}  
          sdkKey={sdkKey}  
          platformScriptJs={platformScript}  
          onPurchaseResult={(result, entitlements) => {  
            if (result.outcome === 'success') {  
              console.log('Purchase succeeded! Granted entitlements:', entitlements);  
              onSuccess();  
              onClose();  
            } else if (result.outcome === 'pending') {  
              console.log('Purchase pending (e.g. Ask to Buy parent approval)');  
            }  
          }}  
          onPurchaseError={(error) => {  
            console.error('Purchase failed:', error.reason, error.serverCode);  
          }}  
          onDismiss={onClose}  
          onLoadError={(error) => {  
            console.error('Failed to load paywall:', error.message);  
            onClose();  
          }}  
        />  
      </View>  
    </Modal>  
  );  
}  
const styles = StyleSheet.create({
  container: { flex: 1 },
});
```

* Live StoreKit 2 & Google Play pricing — local currency formats, subscription period terms, and trial labels are resolved natively and injected into the paywall automatically.  
* Built-in purchase bridge — uses IapPaywallBridge (backed by react-native-iap) out of the box, with automatic transaction recording and backend entitlement synchronization. It needs react-native-iap and react-native-nitro-modules installed, and a paywall in an app without them fails with the command that installs them.


## **Feature flags**

### **What you can ask your agent to do**

#### **Gate an onboarding flow**

```prompt
Create a boolean flag called onboarding-v2 in my development environment, off by
default.

Turn it on for 10% of users.
```

Tools invoked: create_flag → add_targeting_rule (10% rollout coverage) → publish_environment

#### **Set up a paywall or subscription feature**

```prompt
Create a flag called pro-features that is on for any user with a plan attribute
of pro or enterprise, off for everyone else.
```

Tools invoked: create_flag → add_targeting_rule (attribute condition: plan in [pro, enterprise]) → set_variation_defaults → publish_environment

#### **Roll out a new feature gradually**

```prompt
Roll out new-checkout to 20% of users in production.

Increase it to 50% once I say so.
```

Tools invoked: create_flag → add_targeting_rule (coverage: 20%) → publish_environment  
Then on follow-up: update_targeting_rule (coverage: 50%) → publish_environment

#### **Target a specific group**

```prompt
Create a segment called beta-testers for users where is_beta is true.

Enable new-ui for that segment only.
```

Tools invoked: create_segment → create_flag → add_targeting_rule (segment condition) → publish_environment

#### **Toggle a flag**

```prompt
Turn onboarding-v2 on in production.
```

Or:

```prompt
Turn onboarding-v2 off in production.
```

Tools invoked: toggle_flag → *(auto-publishes the environment)*

#### **Emergency kill switch**

```prompt
Kill new-checkout everywhere immediately – something is broken.
```

Tools invoked: kill_flag → *(auto-publishes every environment)*

To undo:

```prompt
Revive new-checkout.
```

Tools invoked: revive_flag

#### **Audit recent changes**

```prompt
What changed in production in the last 24 hours?
```

Tools invoked: read_audit_log

### **Reading a flag**

Flag reads are instant and synchronous. There is no network latency or await needed.

### **Prompting your agent**

```prompt
Read the boolean flag new-checkout synchronously using client.getBool with a
fallback of false.
```

### **Code reference**

```typescript
const newCheckoutEnabled = client.getBool('new-checkout', false);
```

The second argument is the fallback value returned if the flag is missing, still loading from cold cache, or evaluated to a different type.
The client also provides typed getters for other value types:

```typescript
const heroTitle = client.getString('hero-title', 'Welcome');
const maxUploadMb = client.getInt('max-upload-mb', 10);
const discountPercent = client.getNumber('discount-percent', 0.0);
const promoJson = client.getJson('promo-config', '{}');
```

### **Reacting to flag changes**

When targeting rules change or a flag is toggled remotely, the typed observers (client.observeBool, observeString, observeInt, observeNumber, and observeJson) deliver the new value to subscribed listeners.

### **Prompting your agent**

```prompt
Create a useFlag(client, key, defaultValue) custom React hook that observes flag
updates via client.observeBool and returns the live value, cancelling the
subscription on unmount.
```

### **Code reference**

```typescript
import { useEffect, useState } from 'react';
import type { CoproductClient } from '@coproduct/react-native-sdk';
export function useFlag(
  client: CoproductClient | null,
  key: string,
  defaultValue: boolean
): boolean {
  const [value, setValue] = useState(() =>
    client ? client.getBool(key, defaultValue) : defaultValue
  );
  useEffect(() => {
    if (!client) return;
    const sub = client.observeBool(key, defaultValue, setValue);
    return () => sub.cancel();
  }, [client, key, defaultValue]);
  return value;
}
```

Using the hook in a screen, with `useFlag` saved in `src/lib/use-flag.ts`:

```tsx
import { Text } from 'react-native';
import { useCoproduct } from '@/lib/coproduct';
import { useFlag } from '@/lib/use-flag';

export function CheckoutScreen() {
  const newCheckout = useFlag(useCoproduct(), 'new-checkout', false);
  return <Text>{newCheckout ? 'New checkout' : 'Classic checkout'}</Text>;
}
```

### **Targeting your users**

Pass user identity and contextual attributes to Coproduct so targeting rules, percentage rollouts, and user segments evaluate accurately.

### **Prompting your agent**

```prompt
When a user signs in, identify them with client.identify('user-123') and set
their attributes (plan: 'pro', country: 'US').

On logout, call client.signOut().
```

### **Code reference**

```typescript
// On user sign-in
client.identify('user-123', {
  plan: 'pro',
  country: 'US',
});
// Update specific attributes as state changes
client.updateAttributes({
  cartItemCount: 3,
  isSubscriber: true,
});
// On sign-out
client.signOut();
```

To replace targeting key and attributes in one atomic call:

```typescript
client.setContext('user-123', {
  plan: 'pro',
  country: 'US',
});
```

### **Campaign attribution (UTM)**

Target users by the campaign link that opened your app. Pass the link to `captureAttribution`, and the SDK saves its UTM parameters on the device and sets these attributes for your rules:

| URL parameter | First-touch attribute | Last-touch attribute |
|---|---|---|
| `utm_source` | `utm_source` | `utm_source_last` |
| `utm_medium` | `utm_medium` | `utm_medium_last` |
| `utm_campaign` | `utm_campaign` | `utm_campaign_last` |
| `utm_term` | `utm_term` | `utm_term_last` |
| `utm_content` | `utm_content` | `utm_content_last` |

- **First-touch** is the first value captured for that parameter. It never changes after that.
- **Last-touch** is the most recent value captured for that parameter.

**The SDK does not listen for links**, so call `captureAttribution` from your deep-link handling. It needs a client, so call it once `initialize` has resolved. Your app needs deep linking set up as described in React Native's [Linking](https://reactnative.dev/docs/linking) guide.

### **Prompting your agent**

```prompt
After Coproduct initializes, pass the initial URL and every incoming URL from
React Native's Linking API to client.captureAttribution(url), so UTM targeting
rules can match.
```

### **Code reference**

```typescript
import { Linking } from 'react-native';

// The link that started the app
const initialUrl = await Linking.getInitialURL();
if (initialUrl) await client.captureAttribution(initialUrl);

// Links that arrive while the app is running
const subscription = Linking.addEventListener('url', ({ url }) => {
  client.captureAttribution(url);
});
```

- **Each parameter is tracked on its own.** A link with only `utm_source` leaves the other saved values alone, so one device's values can come from different links.
- **Links without UTM parameters change nothing.** Other query parameters and empty values are ignored, and capturing the same link twice is harmless.
- **Values are kept as they appear in the link**, after URL decoding. Each attribute is a string, and is unset until a link supplies it, so a rule that needs a value does not match.
- **Rules update as soon as a link is captured**, and saved values apply again at every `initialize`.
- **Values belong to the device, not the signed-in user.** `identify`, `setContext`, and `signOut` never change them, and every account on the device shares them.
- **An attribute you set with the same name takes precedence** while it is set.
- **Values stay on the device.** They are never sent to Coproduct.
- **First-touch is not tied to the install.** It is the first link captured, which can be long after the app was installed.
- **A link that goes through a store is not captured.** A link that sends someone to the App Store or Google Play does not reach your app on first launch, and the React Native SDK does not read the Play install referrer.
- **Reinstalling can reset the values.** On iOS, uninstalling removes them, and the next link captured becomes the new first-touch. On Android the same applies unless Android Auto Backup restores your app's data.

### **Segmentation by GPS location (geo-fencing)**

Target a flag or segment by a **geo-fence**: a center latitude/longitude and a radius. The flag turns on when the device is physically inside that circle. Matching runs on-device, so the raw coordinates never leave the phone.

**Author the fence in the dashboard.** Create or edit a segment, add a **Location (GPS)** condition with the **within radius of** operator, and enter the center and radius. Point your flag's targeting rule at that segment. The SDK's only job is to supply the device's position as the `device_location` attribute.

**Location is opt-in.** The SDK never touches location at `initialize`: nothing is read and no permission prompt appears until you call `enableLocation()`.

```typescript
import Coproduct from '@coproduct/react-native-sdk';

// Request permission and start supplying device_location.
// Returns whether permission was granted.
const granted = await Coproduct.enableLocation();

// Optional: refresh on a foreground interval, in milliseconds.
// Default 2 minutes, 30s floor, 0 = a single fix with no repeating loop.
await Coproduct.setLocationUpdateInterval(120_000);

// Force a one-off refresh, for example on a "near me" screen.
await Coproduct.refreshLocation();
```

**When the permission popup appears:** the first time you call `enableLocation()` (or `setLocationUpdateInterval()`), never at startup, and only once. The SDK requests permission on both iOS and Android through `react-native-permissions`, which needs the setup below. Without it, the prompt can't appear: `enableLocation()` returns `false`, and on iOS a debug build shows "No permission handler detected."

In an Expo app, run `npx expo install @react-native-community/geolocation` (see **Dependency** below), add the permission to `app.json`, and then run `npx expo prebuild` again:

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSLocationWhenInUseUsageDescription": "Shows content for where you are."
      }
    },
    "android": {
      "permissions": ["android.permission.ACCESS_FINE_LOCATION"]
    },
    "plugins": [
      ["react-native-permissions", { "iosPermissions": ["LocationWhenInUse"] }]
    ]
  }
}
```

Merge these keys into your existing `app.json`, and replace the plain `"react-native-permissions"` entry in `plugins` with the one above.

In a bare React Native app, follow [react-native-permissions' iOS setup](https://github.com/zoontek/react-native-permissions#ios): add `'LocationWhenInUse'` to `setup_permissions` in your `Podfile` and run `pod install`, then add `NSLocationWhenInUseUsageDescription` to your `Info.plist`. On Android, add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />` to `AndroidManifest.xml`.

**Inside/outside is delivered through the flag you already observe** — there is no separate geo-fence callback. When the device crosses the fence, the flag re-evaluates and your existing `observe` handler fires with the new value.

**Fail-safe:** if permission is denied or location services are off, `device_location` stays unset and geo-fence rules fall through to the flag's default variation. No errors, no crash.

**Dependency:** location reads one GPS fix through the optional peer `@react-native-community/geolocation`. Install it only if you use location:

```sh
yarn add @react-native-community/geolocation
```

## **Troubleshooting**

**`initialize` rejects with an error.** This most often means the SDK key is missing or isn't in the right shape, and the error names the problem. A key starts with `cpk_mob_` followed by 32 lowercase letters and digits. Check that you copied the whole key with nothing added.

**Flags always return your defaults?** The `useCoproduct` hook above warns when the SDK stops fetching flags. To see the state yourself, log it from any component:

```tsx
import { useEffect } from 'react';
import { ProviderState } from '@coproduct/react-native-sdk';
import { useCoproduct } from '@/lib/coproduct';

export function CoproductStatus() {
  const client = useCoproduct();
  useEffect(() => {
    if (client) console.log('Coproduct state:', ProviderState[client.state]);
  }, [client]);
  return null;
}
```

`ProviderState.Fatal` means the SDK has stopped fetching flags, most often because the key was rejected. In that case `initialize` still resolves and every read returns the fallback you pass. Check that you copied the key your agent generated, or ask your agent to rotate it (see [If you forgot or lost the key](#2-if-you-forgot-or-lost-the-key)).

**Running in Expo Go?** Expo Go can't load native modules like this SDK. Use a development build instead (see [Expo](#expo)).
