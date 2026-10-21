![][image1]

# React Native Integration

## **For Humans to Get Started**

### **Get started in 2 minutes (do not skip)**

1. **Sign up** at [coproduct.app](https://coproduct.app).
2. **Configure MCP** in Claude Code:
   ```bash
   claude mcp add --transport http coproduct https://mcp.coproduct.app/mcp
   ```
3. **Prompt** your agent: `Integrate @coproduct/react-native-sdk`
   - Generates your project key and wires the SDK into your app.
4. **Prompt** your agent: `Create a new onboarding with 5 steps`
5. **Prompt** your agent: `Rebuild and open the app`

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

Each environment in Coproduct has its own mobile SDK key — formatted as cpk_mob_.... SDK keys are generated exclusively through your AI coding tool via the Coproduct MCP integration — there is no manual button to generate keys in the dashboard.

#### **1. Prompt your agent to generate the key**

Ask your agent to issue a key for the environment you are integrating:

```prompt
Generate a mobile SDK key for the development environment.
```

Your agent calls create_sdk_key and provides your environment key (cpk_mob_...).  
IMPORTANT  
The SDK key is revealed only once upon generation. Save it immediately in a private location (such as a local .env file that is in your .gitignore, or your team’s secrets manager). Coproduct never stores or displays the raw secret again.

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

Never hardcode or commit keys into source control. Keep the key in a `.env` file that is in your `.gitignore` and read it at build time: in Expo as `EXPO_PUBLIC_COPRODUCT_SDK_KEY`, or in a bare React Native app through [react-native-config](https://github.com/lugg/react-native-config). A plain `process.env.COPRODUCT_SDK_KEY` is undefined at runtime in both. A mobile key ships inside your app, so this keeps it out of source control rather than secret.

## **Requirements**

| React Native | 0.84+ |
| :---- | :---- |
| Architecture | New Architecture (TurboModules / Bridgeless) |
| iOS | 15.0+ |
| Android | API 24+ |

## **Installation**

### **Prompting your agent**

Ask your agent to install the packages and sync iOS dependencies:

```prompt
Install @coproduct/react-native-sdk and its required native packages from npm,
using the command in the SDK's manual reference. If the app will show
paywalls, also install the paywall packages listed there.

Then run pod install for iOS.
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

Then install the iOS pods:

```bash
cd ios && pod install
```

The SDK requires React Native 0.84 or later. In an app on an earlier release, npm stops the install with a peer dependency conflict, and Yarn and pnpm warn. Earlier releases fail to build under Xcode 26 once the paywall's purchase packages are installed.

## **Basic integration**

Initialize the SDK once at app startup — typically in your root component or app bootstrap script.

### **Prompting your agent**

```prompt
Initialize the Coproduct client at app startup, reading the SDK key from the
app's build configuration: EXPO_PUBLIC_COPRODUCT_SDK_KEY in Expo, or
Config.COPRODUCT_SDK_KEY from react-native-config in a bare React Native app.

Hold the initialized client in a ref or global provider so the rest of the app
can read flags.
```

### **Code reference**

```typescript
import Coproduct from '@coproduct/react-native-sdk';
import Config from 'react-native-config';

// In Expo, use process.env.EXPO_PUBLIC_COPRODUCT_SDK_KEY instead, written out
// in full: Expo replaces only that exact expression at build time
const sdkKey = Config.COPRODUCT_SDK_KEY;
if (!sdkKey) {
  throw new Error('COPRODUCT_SDK_KEY is not set in .env');
}
const client = await Coproduct.initialize(sdkKey);
```

The SDK loads your flags from the platform-local cache immediately so the client is ready to use as soon as initialize resolves. Flag evaluations and updates run against cached snapshots with background polling.

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
  const [value, setValue] = useState(defaultValue);
  useEffect(() => {
    if (!client) return;
    const sub = client.observeBool(key, defaultValue, setValue);
    return () => sub.cancel();
  }, [client, key, defaultValue]);
  return value;
}
```

Using the hook in a screen:

```tsx
function CheckoutScreen({ client }: { client: CoproductClient }) {
  const newCheckout = useFlag(client, 'new-checkout', false);
  return newCheckout ? <NewCheckoutFlow /> : <LegacyCheckoutFlow />;
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

[image1]: <data:image/png;base64,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>
