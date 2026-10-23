<img src="https://raw.githubusercontent.com/coproducthq/coproduct-client-sdks/main/docs/images/coproduct-logo.png" alt="coproduct.app" width="301">

# iOS Integration

## **For Humans to Get Started**

### **Get started in 2 minutes (do not skip)**

1. **Sign up** at [coproduct.app](https://coproduct.app).
2. **Configure MCP** in Claude Code:
   ```bash
   claude mcp add --transport http coproduct https://mcp.coproduct.app/mcp
   ```
3. **Prompt** your agent: `Integrate the Coproduct iOS SDK`
   - Generates your project key and wires the SDK into your app as a local Swift package, since it is not yet on a package registry.
4. **Prompt** your agent: `Create a new onboarding with 5 steps`
5. **Prompt** your agent: `Rebuild and open the app`

### **Agentic integration mindset**

Coproduct is built from the ground up for agentic coding.
Traditional developer platforms expect humans to manually click through web dashboards: opening a browser, generating API keys in settings, creating feature flags in an admin UI, copying and pasting secrets into code, and toggling release percentages by hand.
Coproduct is designed for developers using AI coding agents, including Claude Code, Codex, Cursor, and any MCP-compatible assistant connected to the Coproduct MCP server:

* Zero dashboard context switching: Your AI agent creates feature flags, sets targeting rules, generates environment SDK keys, authors multi-step onboarding flows, and configures paywalls directly from conversational prompts in your editor.
* Synchronized remote and local development: While your agent executes remote platform actions via Coproduct MCP tools, it simultaneously writes, wires, and verifies the corresponding Swift client code in your project.
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

For other MCP-compatible tools (Cursor, Codex, etc.), add https://mcp.coproduct.app/mcp as an HTTP MCP server in your tool's configuration.
When you first use a Coproduct tool, your agent will prompt you to sign in and grant access. Approve the request in the browser — you'll be redirected back automatically.

### **Getting your SDK key & environments**

Each environment in Coproduct has its own mobile SDK key — formatted as `cpk_mob_` followed by 32 characters. SDK keys are generated exclusively through your AI coding tool via the Coproduct MCP integration — there is no manual button to generate keys in the dashboard.

#### **1. Prompt your agent to generate the key**

Ask your agent to issue a key for the environment you are integrating:

```prompt
Generate a mobile SDK key for the development environment.
```

Your agent calls `create_sdk_key` and provides your environment key (`cpk_mob_...`).
**IMPORTANT**
The SDK key is revealed only once upon generation. Save it immediately in a private location (such as an untracked `.xcconfig` file, or your team's secrets manager). Coproduct never stores or displays the raw secret again.

#### **2. If you forgot or lost the key**

Raw keys cannot be retrieved after generation. If you lose or forget your key, prompt your agent to rotate or reset it:

```prompt
Rotate my mobile SDK key for the development environment.
```

Tools invoked: `rotate_sdk_key`
Your agent initiates a rotation and returns a one-time confirmation link. Opening the link confirms the action, invalidates the old key across all active sessions, and reveals the new replacement key.

#### **Separate keys per environment**

Use the key corresponding to the environment you want flags evaluated against:

* Development or Staging — use while building features, debugging locally, and running test suites.
* Production — use in release builds published to TestFlight or the App Store.

Never hardcode or commit keys into source control. Keep the key in an Xcode configuration file that is in your `.gitignore`, and read it at runtime through `Info.plist`:

1. Add a committed `Config.xcconfig` with `#include? "CoproductSecrets.xcconfig"`, and set it as your project's configuration file.
2. Put `COPRODUCT_SDK_KEY = cpk_mob_...` in `CoproductSecrets.xcconfig`, which you add to `.gitignore`.
3. Add a `CoproductSDKKey` row of type `String` with value `$(COPRODUCT_SDK_KEY)` to your target's **Custom iOS Target Properties**.

The key still ships inside your built app, like any value the app reads at runtime, so this keeps it out of your repository rather than out of the binary.

## **Requirements**

| iOS deployment target | 15.0+ |
| :---- | :---- |
| Package manager | Swift Package Manager |
| Swift language mode | Swift 5 (the package compiles in Swift 5 mode; works from apps in Swift 5 or Swift 6 mode) |
| Toolchain | Swift tools version 6.0 (Xcode 16+) |
| Platforms | iOS and the iOS Simulator only — no Mac Catalyst, macOS, tvOS, watchOS, or visionOS |

`swift build` and `swift test` target macOS by default and cannot build this package. Build and test with `xcodebuild` and an iOS Simulator destination, for example `xcodebuild test -scheme YourScheme -destination 'platform=iOS Simulator,name=iPhone 16'`.

## **Installation**

### **Prompting your agent**

```prompt
Add the Coproduct iOS SDK to this app as a local Swift package, following
sdks/ios/BUILDING.md in the coproduct-client-sdks repository to build
CoproductFFI.xcframework from source, then add the Coproduct product to the
app target.
```

### **Manual reference**

The SDK is not yet on a package registry. Build `CoproductFFI.xcframework` from source per `sdks/ios/BUILDING.md`, then add the `sdks/ios` directory as a local package:

In Xcode, choose **File > Add Package Dependencies**, choose **Add Local...**, and select the `sdks/ios` directory. Add the `Coproduct` library to your app target.

In a `Package.swift`, add it as a local package and depend on the product:

```swift
.package(path: "../path/to/sdks/ios")
```

```swift
.product(name: "Coproduct", package: "ios")
```

Import it where you read flags:

```swift
import Coproduct
```

Once the SDK is published, installing it with a package URL and version replaces this local reference.

## **Basic integration**

Initialize the SDK once at app startup — typically in your `App`'s root scene.

### **Prompting your agent**

```prompt
Initialize the Coproduct client at app startup, reading the SDK key from
Info.plist's CoproductSDKKey entry (backed by CoproductSecrets.xcconfig).

Identify the signed-in user, if any, once initialize returns.
```

### **Code reference**

```swift
import Coproduct
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard let sdkKey = Bundle.main.object(forInfoDictionaryKey: "CoproductSDKKey") as? String,
                          !sdkKey.isEmpty else {
                        print("Coproduct SDK key is missing. Set COPRODUCT_SDK_KEY in CoproductSecrets.xcconfig.")
                        return
                    }
                    do {
                        try await Coproduct.initialize(sdkKey: sdkKey)
                    } catch {
                        print("Coproduct failed to start: \(error)")
                        return
                    }
                    // The SDK does not remember the signed-in user between launches
                    if let userId = currentSignedInUserId() {
                        Coproduct.identify(userId: userId)
                    }
                }
        }
    }
}
```

The SDK loads your flags from the on-device cache immediately so the client is ready to use as soon as `initialize` resolves. Flag evaluations and updates run against cached snapshots with background polling.

## **Onboarding flows**

Coproduct allows authoring and publishing interactive, multi-step onboarding flows directly on the platform. The flow content is fetched dynamically at runtime — zero onboarding screen code or layouts need to be bundled into your binary.

### **Creating an onboarding flow**

Here is a realistic prompt asking your agent to integrate a 4-screen onboarding flow and wire up each screen's native interactions:

```prompt
Create an OnboardingScreen view in SwiftUI using CoproductOnboardingFlow from
the Coproduct package.

Connect it to the string flag welcome-onboarding and handle each screen of our
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

```swift
import SwiftUI
import Coproduct

struct OnboardingScreen: View {
    let onFinish: () -> Void

    var body: some View {
        CoproductOnboardingFlow(
            // String flag that resolves to the target flowId
            flagKey: "welcome-onboarding",
            client: DefaultCoproductClient(),
            onEvent: { event, screenId, answers in
                // Tracks progression through screens:
                // "welcome" -> "user-goals" -> "notifications-optin" -> "plan-reveal"
                print("[Onboarding] \(event) on screen '\(screenId)'", answers)
                if event == "flow_completed" || event == "flow_dismissed" {
                    await MainActor.run { onFinish() }
                }
            },
            onRequestPermission: { permission in
                // Screen 3: called when the user taps the opt-in. The SDK shows the
                // OS permission dialog itself, so use this to sync your app's state
                if permission == "notifications" {
                    print("Notification permission requested from onboarding")
                }
            },
            onNativeOperation: { operation, params in
                // Screen 4: handles an "onLoad" operation ("wait for API" before showing a screen)
                if operation == "fetchRecommendedPlan" {
                    print("Calculating personalized plan with answers:", params)
                    // Example response injected back into the flow's answers
                    return [
                        "tier": "pro_annual",
                        "discountCode": "WELCOME20",
                        "headline": "Recommended for Growing Teams",
                    ]
                }
                return ["status": "error", "message": "Unhandled operation: \(operation)"]
            }
        )
    }
}
```

* Runtime content loading — the flow graph is fetched by `flowId`, the value the `flagKey` resolves to.
* Automatic progress persistence — answers and the current screen are preserved in on-device storage; resuming an interrupted flow happens seamlessly.
* Debug drawer — in `DEBUG` builds, a built-in overlay allows refreshing content or resetting progress to test the experience end-to-end.
* `client` defaults to needing no host wiring: `DefaultCoproductClient()` resolves the flag and fetches the flow directly through this SDK's existing flag/identity client.

### **Native interactions & lifecycle callbacks**

The WebView renders platform-authored UI, but all device capabilities and native events are handed back to your app through typed callbacks:

#### **1. Asking for permissions (onRequestPermission)**

Authored screens can prompt the user for native OS permissions (e.g. a push notification opt-in screen, camera upload screen, or location permissions):

* Built-in capability: When a user taps a CTA configured to request a permission, the runtime translates it to an OS request. Under the hood, Coproduct maps standard permissions (notifications, camera, photos, location, microphone) directly to native platform permission dialogs.
* Custom handling: Supply `onRequestPermission: (String) async -> Void`, which is called when a screen asks for a permission, to keep your app's own permission state in step.
* Conditional branching: Subsequent screens or transitions can branch on the result of the SDK's built-in permission request, granted or denied.

#### **2. Waiting for API calls (onNativeOperation & onLoad)**

Onboarding screens frequently need data that doesn't exist until the user answers prior questions — such as computing a custom diet plan, querying a credit limit, or reserving a username.

* The `onLoad` hook: In the Coproduct dashboard, any screen can be configured with an `onLoad` operation name (e.g. `operation: "fetchRecommendedPlan"`, `timeoutMs: 5000`).
* Instant suspension: The moment the user navigates to that screen, the flow pauses and presents a native loading spinner while calling your app's `onNativeOperation(operation, params)`.
* Answers returned to the flow: Your handler returns a `[String: String]` dictionary (e.g. `["tier": "pro_annual", "discount": "20%"]`). The SDK resolves the request, and the values are injected into the flow's state under `answers`.
* Dynamic screen rendering: The loaded screen and all subsequent screens can display the returned values dynamically using data bindings (such as `<span data-cp-answer="tier"></span>`), or route users down different paths based on the returned values.

#### **3. Event callbacks & analytics (onEvent)**

Every screen transition and user interaction emits a lifecycle event through `onEvent(event, screenId, answers)`:

* Events emitted:
  * `screen_viewed` — fires whenever a screen is rendered.
  * `action_tapped` — fires when buttons, choice cards, or inputs are tapped.
  * `flow_completed` — fires when the user successfully reaches the end of the onboarding flow.
  * `flow_dismissed` — fires when the user taps a close or skip button.
* Cumulative answers dictionary: Every event carries all answers collected up to that moment (form inputs, choice selections, and native API responses).
* Analytics integration: Plug `onEvent` directly into your analytics pipeline (PostHog, Segment, Mixpanel, Firebase) to track conversion funnels without manual instrumentation across individual screens.

#### **4. URL and paywall transitions**

* `onOpenUrl(url)`: Triggered when users tap external links (such as Privacy Policy or Terms of Service URLs), allowing you to open them in an in-app browser or `SFSafariViewController`.
* `onShowPaywall(paywallId)`: Triggered when an onboarding flow finishes with a purchase CTA, letting you immediately transition the user into `CoproductPaywall(paywallId: paywallId, ...)`.

### **Viewing and inspecting in the dashboard**

Every onboarding flow can be reviewed and previewed in the [Coproduct dashboard](https://dash.coproduct.app) under Onboarding:

* Visual flow inspection — explore the screen graph, screen transitions, default navigation branches, and `onLoad` asynchronous hooks.
* Interactive preview — click through the experience as a user would, previewing copy, form inputs, and animations before releasing.
* Deployment status — see exactly which draft or published version is pinned to each environment (Development, Production).

### **Multiple onboarding flows & variant testing**

Because an onboarding flag (e.g. `welcome-onboarding`) is a standard Coproduct string flag, its variations return flow IDs (`flowId`). This enables you to deploy multiple onboarding flows and test them across different variations and user segments without changing any mobile code:

* A/B test onboarding journeys: Point variation A to `flow-express` (e.g. 2 quick screens) and variation B to `flow-guided` (e.g. 4 interactive screens). Split traffic 50/50 with a percentage rollout rule to see which yields higher completion and sign-up conversion.
* Segment-specific onboarding: Serve tailored onboarding experiences depending on user attributes — such as showing a B2B flow for users with corporate email domains, or a simplified flow for users coming from specific marketing campaigns.
* Zero app updates: Swap variations, point to a brand-new flow, or change targeting rules remotely. The app simply queries the flag and immediately loads whichever flow ID it resolves to.

#### **Prompting your agent for variant testing**

```prompt
Configure our string flag welcome-onboarding with two variations: short-flow
(value: flow-quick-v1) and deep-flow (value: flow-interactive-v2).

Split rollout 50/50 across both variations in production.
```

Tools invoked: `create_flag` → `add_targeting_rule` (50% rollout split) → `publish_environment`

## **Paywalls**

Coproduct paywalls render web-driven, design-system-consistent paywall layouts while delegating transactions and pricing to StoreKit2.

### **Designing a paywall**

With Coproduct, developers and growth teams never need to hand-code native billing screens, pricing tables, or complex layout variants in SwiftUI. Instead, you instruct your AI coding agent (Claude Code, Cursor, Codex) to design, style, and publish the paywall directly.
The agent defines entitlements, configures offerings across subscription tiers, selects an optimal layout template, and writes custom HTML, CSS, and copy tailored to your brand.

#### **Prompting your agent to design a paywall**

```prompt
Design a high-converting annual subscription paywall for pro access in project
my-app.

Use a feature comparison layout comparing Free and Pro tiers, highlight a 7-day
free trial on the annual plan with a 40 percent savings badge, set up an
alternative monthly option, and include restore purchases and terms links.
```

Tools invoked: `create_entitlement` → `create_product` → `create_offering` → `create_paywall_template` → `update_paywall_content` → `deploy_paywall`

#### **Paywall templates and data attributes**

Your agent can scaffold paywalls using conversion-tested templates or generate completely custom layouts:

* Hero single offer (`hero_single_offer`): Focuses user attention on a single high-value tier, ideal for direct trial-to-paid conversions.
* Feature comparison (`feature_comparison`): Side-by-side comparison matrix highlighting differences between Free and Pro tiers.
* Plan grid (`plan_grid`): Multi-card layout presenting monthly, annual, and lifetime tiers side by side.

Interactive paywall behaviors (purchases, restores, dismissals) and live price placements are wired using standard Coproduct data attributes. When the paywall renders on iOS, the SDK automatically connects native StoreKit2 to these elements:

* `data-cp-action="purchase"`: Triggers a native in-app purchase for the target package.
* `data-package-key="annual"`: Links the button or card to a specific package defined in the offering.
* `data-cp-price-for="annual"`: Injects live localized pricing and trial terms directly from StoreKit2.
* `data-cp-action="restore"`: Triggers transaction restore with Apple.
* `data-cp-action="dismiss"`: Dismisses the paywall modal.

### **Store authorization & App Store Connect setup**

To enable server-driven paywalls with automated product syncing and receipt validation, authorize Coproduct with your App Store Connect account:

* In the [Coproduct dashboard](https://dash.coproduct.app), navigate to Settings → Integrations → App Store Connect.
* In App Store Connect (Users and Access → Integrations → App Store Connect API), create an API Key with App Manager permissions.
* Link your Issuer ID, Key ID, and downloaded private key (`.p8`), or ask your agent:

```prompt
Connect our App Store Connect credentials using our Issuer ID, Key ID, and
private key for project my-app.
```

Tools invoked: `connect_app_store_credentials` → `select_app_store_app`
Once authorized, Coproduct can create and sync subscription products, validate transactions, and record entitlement grants directly with Apple.

### **Changing pricing from prompts & dashboard (syncs to App Store Connect)**

With Coproduct paywalls, subscription pricing and package configurations are completely decoupled from your app binary, and price updates can be pushed to App Store Connect directly from an AI prompt or the dashboard:

#### **Changing prices from an agent prompt**

You can instruct your AI coding tool to change product prices in chat:

```prompt
Update the price of our iOS subscription product com.myapp.pro.annual to 49.99
USD in project my-app.
```

Tools invoked: `update_product`

When App Store Connect is connected, Coproduct pushes the new reference price directly to Apple via the App Store Connect API. Because price changes to existing approved subscriptions do not require a new app review, the updated price tier reflects in App Store Connect near-instantly.

#### **Changing prices and offerings in the dashboard**

You can also adjust prices, add promotional discounts, or swap packages visually in the [Coproduct dashboard](https://dash.coproduct.app) under Paywalls → Products & Offerings:

* Zero App Store resubmissions: Change monthly or annual subscription prices, introduce lifetime tiers, or adjust free-trial durations without submitting an app update.
* Dynamic StoreKit2 price injection: When `CoproductPaywall` renders on-device, it automatically queries native StoreKit2 for the user's localized currency prices and trial terms, then injects them into the paywall UI. Users worldwide always see prices formatted in their local currency.
* Price elasticity & A/B testing: Test different price points (e.g. $4.99/mo vs. $6.99/mo) or swap offering layouts between user segments using Coproduct targeting rules.

### **Prompting your agent for iOS integration**

```prompt
Create a PaywallSheet view using CoproductPaywall from the Coproduct package.

Pass the paywall ID premium-annual, current user ID, and SDK key.

Handle onPurchaseResult to unlock pro access when result.outcome is .success,
and handle onDismiss.
```

### **Code reference**

```swift
import SwiftUI
import Coproduct

struct PaywallSheet: View {
    let paywallId: String
    let appUserId: String
    let sdkKey: String
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CoproductPaywall(
            paywallId: paywallId,
            appUserId: appUserId,
            sdkKey: sdkKey,
            onPurchaseResult: { result, entitlements in
                if result.outcome == .success {
                    print("Purchase succeeded! Granted entitlements:", entitlements)
                    onSuccess()
                    dismiss()
                } else if result.outcome == .pending {
                    print("Purchase pending (e.g. Ask to Buy parent approval)")
                }
            },
            onPurchaseError: { error in
                print("Purchase failed:", error)
            },
            onDismiss: { dismiss() },
            onLoadError: { error in
                print("Failed to load paywall:", error)
                dismiss()
            }
        )
    }
}
```

* Live StoreKit2 pricing — local currency formats, subscription period terms, and trial labels are resolved natively and injected into the paywall automatically.
* Built-in purchase bridge — uses `StoreKitPaywallBridge` out of the box, with automatic transaction recording and backend entitlement synchronization. Restoring only ever returns subscriptions and lifetime (non-consumable) purchases, an Apple platform limitation, not a gap in this SDK.

## **Feature flags**

### **What you can ask your agent to do**

#### **Gate an onboarding flow**

```prompt
Create a boolean flag called onboarding-v2 in my development environment, off by
default.

Turn it on for 10% of users.
```

Tools invoked: `create_flag` → `add_targeting_rule` (10% rollout coverage) → `publish_environment`

#### **Set up a paywall or subscription feature**

```prompt
Create a flag called pro-features that is on for any user with a plan attribute
of pro or enterprise, off for everyone else.
```

Tools invoked: `create_flag` → `add_targeting_rule` (attribute condition: plan in [pro, enterprise]) → `set_variation_defaults` → `publish_environment`

#### **Roll out a new feature gradually**

```prompt
Roll out new-checkout to 20% of users in production.

Increase it to 50% once I say so.
```

Tools invoked: `create_flag` → `add_targeting_rule` (coverage: 20%) → `publish_environment`
Then on follow-up: `update_targeting_rule` (coverage: 50%) → `publish_environment`

#### **Target a specific group**

```prompt
Create a segment called beta-testers for users where is_beta is true.

Enable new-ui for that segment only.
```

Tools invoked: `create_segment` → `create_flag` → `add_targeting_rule` (segment condition) → `publish_environment`

#### **Toggle a flag**

```prompt
Turn onboarding-v2 on in production.
```

Or:

```prompt
Turn onboarding-v2 off in production.
```

Tools invoked: `toggle_flag` → *(auto-publishes the environment)*

#### **Emergency kill switch**

```prompt
Kill new-checkout everywhere immediately – something is broken.
```

Tools invoked: `kill_flag` → *(auto-publishes every environment)*

To undo:

```prompt
Revive new-checkout.
```

Tools invoked: `revive_flag`

#### **Audit recent changes**

```prompt
What changed in production in the last 24 hours?
```

Tools invoked: `read_audit_log`

### **Reading a flag**

Flag reads are instant and synchronous. There is no network latency or `await` needed.

### **Prompting your agent**

```prompt
Read the boolean flag new-checkout synchronously using Coproduct.getBool with a
default of false.
```

### **Code reference**

```swift
let newCheckoutEnabled = Coproduct.getBool("new-checkout", default: false)
```

The `default:` argument is the fallback value returned if the flag is missing, still loading from cold cache, or evaluated to a different type.
The client also provides typed getters for other value types:

```swift
let heroTitle = Coproduct.getString("hero-title", default: "Welcome")
let maxUploadMb = Coproduct.getInt("max-upload-mb", default: 10)
let discountPercent = Coproduct.getNumber("discount-percent", default: 0.0)

struct PromoConfig: Codable { let code: String }
let config = Coproduct.getJSON("promo-config", default: PromoConfig(code: "NONE"))
```

### **Reacting to flag changes**

When targeting rules change or a flag is toggled remotely, `@CoproductFlag` and the typed observations (`Coproduct.observe`) deliver the new value to subscribed listeners.

### **Prompting your agent**

```prompt
Gate ContentView on the boolean flag new-checkout using @CoproductFlag, so the
view updates automatically when the flag changes.
```

### **Code reference**

```swift
struct ContentView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool

    var body: some View {
        if newCheckout {
            NewCheckoutFlow()
        } else {
            OldCheckoutFlow()
        }
    }
}
```

Outside a SwiftUI view, observe the flag instead:

```swift
import Combine
import Coproduct

final class CheckoutModel: ObservableObject {
    @Published private(set) var newCheckout = false
    private var cancellable: AnyCancellable?

    // Call only after Coproduct.initialize has returned
    func start() {
        cancellable = Coproduct.observe("new-checkout", default: false).publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in self?.newCheckout = isOn }
    }
}
```

### **Targeting your users**

Pass user identity and contextual attributes to Coproduct so targeting rules, percentage rollouts, and user segments evaluate accurately.

### **Prompting your agent**

```prompt
When a user signs in, identify them with Coproduct.identify(userId:) and set
their attributes (plan: "pro", country: "US").

On logout, call Coproduct.signOut().
```

### **Code reference**

```swift
// On user sign-in
Coproduct.identify(userId: "user-123", attributes: [
    "plan": .string("pro"),
    "country": .string("US"),
])

// Update specific attributes as state changes
Coproduct.updateAttributes([
    "cartItemCount": .number(3),
    "isSubscriber": .bool(true),
])

// On sign-out
Coproduct.signOut()
```

To replace the targeting key and attributes in one atomic call, for a target that is not a signed-in account, such as a team or a device:

```swift
Coproduct.setContext(targetingKey: "team-123", attributes: [
    "plan": .string("pro"),
    "region": .string("eu"),
])
```
