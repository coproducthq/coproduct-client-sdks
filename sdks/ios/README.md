# Coproduct iOS SDK

Swift SDK for [Coproduct](https://coproduct.app), a feature management platform. It downloads your flags, evaluates them on the device, and keeps them up to date, so reading a flag is an instant call that works offline.

> **Releasing soon.** You can build this SDK from source, and [Building from source](#building-from-source) shows how. Installing it from a package URL arrives at release, and the API can still change before then.
>
> This SDK covers feature flags only: downloading them, evaluating them on the device, targeting them at users, and reacting to changes. It does not record which value a user saw and sends no analytics events.

A **feature flag** is a value you control from Coproduct rather than from your app's code: a switch that turns a feature on or off, or a piece of configuration you can change without shipping a release. In Coproduct you attach targeting rules to a flag. The rules match on **attributes** that describe the person using your app, so one flag can serve `true` to the users you choose and `false` to everyone else.

## Contents

- [Quick start](#quick-start)
- [Requirements and platform support](#requirements-and-platform-support)
- [Installation](#installation)
- [Keeping your key out of source](#keeping-your-key-out-of-source)
- [Key concepts](#key-concepts)
- [Initializing and shutting down](#initializing-and-shutting-down)
- [Reading flags](#reading-flags)
- [Reacting to flag changes](#reacting-to-flag-changes)
- [Identity and attributes](#identity-and-attributes)
- [Automatic attributes](#automatic-attributes)
- [Configuration](#configuration)
- [Checking for updates](#checking-for-updates)
- [SDK status](#sdk-status)
- [Lifecycle handlers and evaluation hooks](#lifecycle-handlers-and-evaluation-hooks)
- [Errors](#errors)
- [Threading](#threading)
- [Privacy and data](#privacy-and-data)
- [Testing and previews](#testing-and-previews)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)
- [Building from source](#building-from-source)
- [License](#license)

## Quick start

Follow these steps in order. At the end, a SwiftUI view in your app shows one of two screens depending on a flag you control from Coproduct.

**1. Check the requirements.** Your app must target iOS 15.0 or later. See [Requirements and platform support](#requirements-and-platform-support).

**2. Get an SDK key and create a flag.** At [coproduct.app](https://coproduct.app):

1. Sign in and open the project you want the app to read flags from, or create one.
2. Issue a **mobile** SDK key for that project. It looks like `cpk_mob_` followed by 32 characters. This SDK accepts only mobile keys.
3. Create a boolean flag with the key `new-checkout`. The steps below use that key. You can substitute a boolean flag you already have.

**3. Add the package.** Once the SDK is published, add it with Swift Package Manager. See [Installation](#installation). Until then, build it from source.

**4. Initialize the SDK when your app starts.** Call `initialize` once, then identify the signed-in user if there is one. Replace `cpk_mob_...` with your key.

```swift
import Coproduct
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await Coproduct.initialize(sdkKey: "cpk_mob_...")
                    } catch {
                        // Network problems never throw here, but a bad key or config does
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

`currentSignedInUserId()` stands in for however your app finds the signed-in account. On the first launch, `initialize` waits up to 3 seconds for your flags to download and then returns whether or not they arrived. On later launches it starts from the flags saved on the last launch and returns without waiting for the network. See [Initializing and shutting down](#initializing-and-shutting-down).

The placeholder key `cpk_mob_...` makes `initialize` throw `CoproductError.invalidSdkKey`, so a key you forgot to replace fails straight away.

The quick start writes the key inline to stay short. Before you commit, move it into your build configuration, as [Keeping your key out of source](#keeping-your-key-out-of-source) shows.

**5. Gate a view on the flag.** `@CoproductFlag` reads the flag and re-renders the view when it changes:

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

`NewCheckoutFlow` and `OldCheckoutFlow` stand in for two views from your app. Until the SDK has flags, `newCheckout` is the default you passed, so the view always has something to render. `@CoproductFlag` works even though the view is created before `initialize` runs: it connects as soon as the SDK starts.

**6. Identify users when they sign in.** Rules that target particular users need to know who is using the app. When someone signs in, call `identify` with that user's stable id and any attributes your rules match on:

```swift
Coproduct.identify(userId: account.id, attributes: ["plan": .string("pro")])
```

As in step 4, call it again on every launch once you know who is signed in. See [Identity and attributes](#identity-and-attributes).

That is a working integration. Flag changes you make in Coproduct reach the running app on the next check for updates, which happens every 60 seconds and whenever the app becomes active. See [Checking for updates](#checking-for-updates).

## Requirements and platform support

| | Supported |
|---|---|
| Platforms | iOS and the iOS Simulator only |
| iOS deployment target | 15.0 or later |
| Package manager | Swift Package Manager |
| Swift language mode | The package compiles in Swift 5 mode |

- **Other Apple platforms are not supported.** The package declares iOS only, and its binary contains only iOS device (`arm64`) and iOS Simulator (`arm64` and `x86_64`) code. Mac Catalyst, macOS, tvOS, watchOS, and visionOS are not supported.
- **Toolchain.** The package manifest declares Swift tools version 6.0, which needs a Swift 6.0 toolchain (Xcode 16) or later. The supported Xcode versions are set at release.
- **Swift 6 apps.** The package itself compiles in Swift 5 language mode. It is intended to work from apps in either Swift 5 or Swift 6 language mode.
- **Command-line builds.** `swift build` and `swift test` target macOS, so they cannot build the SDK. Build and test with `xcodebuild` and an iOS Simulator destination, for example `xcodebuild test -scheme YourScheme -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Installation

> Releasing soon. The package URL and version are set at release, so the lines below show the shape of the dependency rather than values you can copy. To use the SDK now, see [Building from source](#building-from-source).

In Xcode, choose **File > Add Package Dependencies**, enter the package URL, and add the `Coproduct` library to your app target.

In a `Package.swift`, add the package:

```swift
.package(url: "<published-package-url>", from: "<released-version>")
```

Then add the product to your target's `dependencies`:

```swift
.product(name: "Coproduct", package: "<package-name>")
```

The package vends a single library product, `Coproduct`. Import it where you read flags:

```swift
import Coproduct
```

## Keeping your key out of source

Keep your SDK key out of source control, so it is not shared with everyone who can read your repository. One way is to keep it in an Xcode build configuration file that is not committed, and read it at runtime through `Info.plist`.

**1. Add a committed configuration file.** In Xcode, add a new **Configuration Settings File** named `Config.xcconfig` to your project, with one line:

```
#include? "CoproductSecrets.xcconfig"
```

In the project editor, select the project, not a target, and open the **Info** tab. Under **Configurations**, set `Config` as the project's configuration file in each configuration. Xcode records this as the `baseConfigurationReference` of the project's build configurations in `project.pbxproj`. Setting it on the project leaves each target's own configuration file in place, including one CocoaPods generates, and every target still inherits `COPRODUCT_SDK_KEY`. Only files that belong to the project appear there, so a file created outside Xcode must be added to the project first. If the project already uses configuration files of your own, add the `#include?` line to each of them instead, because each configuration, such as Debug and Release, can use a different file. Do not edit a generated configuration file such as CocoaPods' `Pods-*.xcconfig`, because the next `pod install` overwrites it. The `?` makes the include optional, so a checkout without the secrets file still builds.

**2. Put the key in a file you do not commit.** Create `CoproductSecrets.xcconfig` beside it, and add `CoproductSecrets.xcconfig` to your `.gitignore`:

```
COPRODUCT_SDK_KEY = cpk_mob_...
```

Replace `cpk_mob_...` with your mobile SDK key.

**3. Expose the value through `Info.plist`.** In your app target's **Info** tab, add a row under **Custom iOS Target Properties** with the key `CoproductSDKKey`, the type `String`, and the value `$(COPRODUCT_SDK_KEY)`. This adds the entry below to the target's `Info.plist`, and Xcode substitutes the build setting when it builds the app:

```xml
<key>CoproductSDKKey</key>
<string>$(COPRODUCT_SDK_KEY)</string>
```

If the target generates its `Info.plist` and has no file of its own, create an `Info.plist` holding this entry next to the `.xcodeproj`, and set the target's `INFOPLIST_FILE` build setting to its path relative to the project directory, such as `Info.plist`. Xcode merges it with the generated keys. Keep the file out of any folder Xcode keeps in sync with the file system, which is how a new app's source folder works. Xcode adds every file in such a folder to the target and copies any file it does not compile into the app as a resource, so an `Info.plist` there fails the build with an error that begins `Multiple commands produce`. If you see that error after adding the row in the **Info** tab, move the file next to the `.xcodeproj` and update `INFOPLIST_FILE` to match.

**4. Read the key and pass it to `initialize`.** Replace the `.task` from the quick start with this one. It reads the key instead of writing it inline, and still identifies the signed-in user:

```swift
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
```

When `CoproductSecrets.xcconfig` is missing, `$(COPRODUCT_SDK_KEY)` expands to an empty string, so the guard reports the missing key instead of starting the SDK with a blank one.

On a build server, write `CoproductSecrets.xcconfig` from a secret before the build runs.

The key still ships inside your built app, like any value the app reads at runtime. This pattern keeps it out of your repository, not out of the binary.

## Key concepts

### Flags, flag keys, and default values

A **flag key** is the stable string your code uses to ask for one flag, such as `new-checkout`. Every read passes a key and a **default value** (the `default:` argument): the value your code uses when the SDK cannot resolve the flag. In prose this README also calls it your default.

Flags have four types: boolean, string, number, and JSON. Read each with the matching getter or observation. `getInt` reads a number flag.

### What a read serves

| Situation | What you get |
|---|---|
| The flag is on and the user matches a targeting rule | That rule's value |
| The flag is on and the user matches no rule | The flag's fallthrough value, the value you set in Coproduct for everyone else |
| The flag is switched off or paused | The flag's off value, set in Coproduct |
| The flag depends on another flag (a prerequisite) that is not met, or its rules use a condition this SDK version does not understand, or its prerequisites form a cycle or are nested too deeply | The flag's off value |
| The SDK has no flags yet: before `initialize`, or on a first launch before the first download completes | Your default value |
| No flag with that key exists in your SDK key's environment | Your default value |
| The flag's type does not match the read, such as a string flag read with `getBool` | Your default value |
| The SDK key was rejected, or the SDK was shut down | Your default value |

A switched-off flag and a user who matches no rule both serve real values from Coproduct, not your default. Your default appears only when the SDK cannot resolve the flag at all.

Reads never throw. The trade-off is that a mistake is quiet: a misspelled key or a flag of the wrong type serves your default with no error.

### Flags are evaluated on the device

The SDK downloads your flag definitions and their targeting rules, keeps them up to date in the background, and works out on the device which value applies. Reading a flag is an in-memory lookup. It makes no network request, so it is safe to call in a SwiftUI `body` and never fails because the network is down.

The user id and attributes you set stay on the device. The SDK does not send them to Coproduct. See [Privacy and data](#privacy-and-data).

## Initializing and shutting down

### What initialize does

`Coproduct.initialize(sdkKey:)` checks your SDK key and configuration, loads any flags saved on an earlier launch, sets the [automatic attributes](#automatic-attributes), and starts checking for updates. Then it waits, and what it waits for depends on whether saved flags exist:

| Launch | What `initialize` waits for | What reads serve when it returns |
|---|---|---|
| First launch, or no saved flags | The first download, for up to `startupTimeout` (3 seconds by default) | The downloaded flags, or your defaults if the download has not finished or failed |
| A later launch, with flags saved | Nothing from the network | The flags saved on the last launch. Fresh values replace them when the first check completes, a moment later |

`initialize` never throws because of the network. If the first download fails, for example because the device is offline, `initialize` stops waiting straight away and reads serve your defaults. If Coproduct asks the SDK to slow down, `initialize` waits out the full `startupTimeout`. Either way the SDK keeps checking in the background.

### Knowing when flags have arrived

`initialize` returning does not mean flags have arrived. Two ways to handle that:

- **Observe the flags you depend on.** `@CoproductFlag` and `Coproduct.observe` deliver the current value straight away and again whenever it changes, including when the first download lands. This is the recommended approach. See [Reacting to flag changes](#reacting-to-flag-changes).
- **Check `Coproduct.state`** after `initialize` returns. `.ready` means flags are loaded, either downloaded or saved from an earlier launch. See [SDK status](#sdk-status).

Do not wait for a `.ready` lifecycle event to learn that flags are available. Lifecycle events fire only when the state changes, and a handler registered after the change never sees it. You register handlers after `initialize` returns, so a handler misses a `.ready` that happened while `initialize` was waiting. When flags are loaded from the device at launch, the SDK starts in the `ready` state and no `.ready` event fires at all. A launch that waits for that event can wait forever.

### Before initialize

Before you call `initialize`, and after `shutdown()`:

- getters return your default, and detail getters return your default with the error code `PROVIDER_NOT_READY`;
- `Coproduct.state` is `.notReady`, `previousAnonymousId` is `nil`, and `snapshot` reports version 0;
- `identify`, `setContext`, `updateAttributes`, `removeAttributes`, and `signOut` log a message and do nothing;
- `@CoproductFlag` serves your default and connects when the SDK starts.

Make identity calls after `initialize` returns, so none is dropped.

`Coproduct.observe`, `addHandler`, and `addEvaluationHook` are different: they **crash with a fatal error** if the SDK is not running. That covers a call before `initialize`, after `initialize` threw, and after `shutdown()`. Call them only after `initialize` has returned successfully.

### Calling initialize again

The SDK runs one instance per process. Calling `initialize` again while it is running does nothing and returns straight away, without waiting for flags. This is true even with a different `sdkKey` or config. The first key and config stay in effect, and a different key logs a warning. A call made while the first `initialize` is still running waits for that call and gets its result. To switch keys or environments, call `await Coproduct.shutdown()` first, then `initialize` again.

### Shutting down

`await Coproduct.shutdown()` stops checking for updates and ends every observation, lifecycle handler, evaluation hook, and evaluation listener. Afterward:

- getters return your defaults;
- existing `FlagObservation` and `FlagBundleObservation` objects keep their last value and never update again, even after a new `initialize`. A `for await` loop over an old observation's `values` keeps waiting until its task is canceled;
- `@CoproductFlag` properties keep their last value and reconnect automatically if you call `initialize` again;
- the flags saved on the device are kept for the next launch.

After a new `initialize`, observe and register handlers again. If `shutdown()` runs while `initialize` is still in progress, that `initialize` throws `CoproductError.cancelledByShutdown`. Most apps never call `shutdown`.

## Reading flags

### Which read API to use

| What you are doing | Use |
|---|---|
| Building a SwiftUI view that should change when the flag changes | **`@CoproductFlag`**. Supports `Bool`, `String`, `Int`, and `Double` |
| Reading the current value once, in logic outside a view | **The getters**: `getBool`, `getString`, `getInt`, `getNumber`, `getJSON` |
| Holding a value in a view model, a UIKit controller, or an async loop | **`Coproduct.observe(_:default:)`**, for `Bool`, `String`, `Int`, and `Double` |
| Watching several flags together, or a JSON flag | **`Coproduct.observe(keys:)`** |

**Calling a getter inside a SwiftUI `body` does not make the view update when the flag changes.** It reads the value at that moment and nothing more. Use `@CoproductFlag` for views.

### Getters

Each getter takes the flag key and your default of the matching type:

```swift
let enabled = Coproduct.getBool("new-checkout", default: false)
let greeting = Coproduct.getString("greeting", default: "Hello")
let maxItems = Coproduct.getInt("max-items", default: 10)
let ratio = Coproduct.getNumber("rollout-ratio", default: 0.0)
```

Reads never throw or crash, at any point in your app's life. See [What a read serves](#what-a-read-serves) for when your default comes back. `getInt` reads a number flag and truncates a fractional value toward zero.

### JSON flags

`getJSON` decodes a JSON flag into any `Codable` type:

```swift
struct CheckoutConfig: Codable {
    let maxItems: Int
    let currency: String
}

let config = Coproduct.getJSON(
    "checkout-config",
    default: CheckoutConfig(maxItems: 10, currency: "USD")
)
```

It decodes with a default `JSONDecoder`, so property names must match the JSON keys exactly. Use `CodingKeys` for keys such as `max_items`. If decoding fails, you get your default back and nothing is logged.

### Evaluation details

The detail getters (`getBoolDetails`, `getStringDetails`, `getIntDetails`, `getNumberDetails`, and `getJSONDetails`) return the value together with why it was chosen, which helps when a flag does not behave as you expect:

```swift
let details = Coproduct.getBoolDetails("new-checkout", default: false)
print("served \(details.value) because \(details.reason)")
if let errorCode = details.errorCode {
    // Your default was served, or a rule failed and the flag's off value was served
    print("error \(errorCode): \(details.errorMessage ?? "no message")")
}
```

A `FlagEvaluationDetails` has these fields:

- `value`: the served value as a `FlagDetailValue`, such as `.bool(true)`;
- `variant`: the key of the variation that was served, or `nil` when your default was served;
- `reason`: why the value was chosen, such as `"TARGETING_MATCH"`;
- `errorCode` and `errorMessage`: `nil` unless something went wrong;
- `flagKey`: the key you read.

See [Reasons and error codes](#reasons-and-error-codes) for the values. `getJSONDetails` returns the flag's raw JSON text in `.json(String)` without decoding it, so it does not tell you whether `getJSON` would decode it into your type.

## Reacting to flag changes

### @CoproductFlag

`@CoproductFlag` binds a SwiftUI view to a flag, as in the [quick start](#quick-start). It supports `Bool`, `String`, `Int`, and `Double`.

- It works only inside SwiftUI views, because it is built on `@StateObject`.
- It serves your default until the SDK starts, including in SwiftUI previews, and needs no `initialize` call to be safe.
- It delivers values on the main thread. The first value arrives asynchronously, so a view's first render can show your default for a moment, even when flags are already loaded.
- `$newCheckout` is a Combine publisher of the same value.
- For a JSON flag, call `getJSON` or use `Coproduct.observe(keys:)`.

### Observations

Outside a SwiftUI view, observe the flag. `Coproduct.observe(_:default:)` returns a `FlagObservation`, which holds the current value from the moment you create it and delivers later values in order. If several changes land close together you may receive only the latest. Values arrive on a background thread, so move to the main thread before touching UI:

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

**Keep the observation alive.** An observation stops when nothing holds it. A Combine subscription holds it until the subscription is canceled, so store the `AnyCancellable` for as long as you want updates. Setting `cancellable` to `nil`, or releasing the model, ends the observation. A `FlagObservation` stored in a local constant ends when the function returns.

A `FlagObservation` has three members:

- `current`: the latest value, without subscribing;
- `publisher`: a Combine publisher that emits the current value when you subscribe, then each change;
- `values`: an `AsyncStream` of the same values.

With `values`, the observation stays alive for as long as the loop runs, and the loop ends when its task is canceled, for example when a SwiftUI `.task` ends:

```swift
func watchCheckoutFlag() async {
    // Call only after Coproduct.initialize has returned
    let observation = Coproduct.observe("new-checkout", default: false)
    for await isOn in observation.values {
        print("new-checkout is now \(isOn)")
    }
}
```

`values` keeps only the newest value for a slow consumer, so a loop that falls behind skips to the latest.

### Observing several flags

`Coproduct.observe(keys:)` returns a `FlagBundleObservation`. Its `current`, `publisher`, and `values` carry a `[String: FlagDetailValue]` dictionary. `FlagDetailValue` keeps each flag's type: a boolean flag arrives as `.bool`, a string flag as `.string`, a number flag as `.number(Double)`, and a JSON flag as `.json(String)`, the raw JSON text. A bundle never delivers `.int`.

```swift
import Combine
import Coproduct

final class SettingsModel {
    private var cancellable: AnyCancellable?

    // Call only after Coproduct.initialize has returned
    func start() {
        cancellable = Coproduct.observe(keys: ["new-checkout", "theme"]).publisher
            .receive(on: DispatchQueue.main)
            .sink { values in
                if case let .string(theme)? = values["theme"] {
                    print("theme is \(theme)")
                }
            }
    }
}
```

A bundle has no defaults. A key with no usable value, because no flags have downloaded yet, no flag has that key, or the flag's type is one this SDK version does not know, is left out of the dictionary. It appears when a value arrives.

## Identity and attributes

### The anonymous identity

Before you call `identify`, the SDK evaluates flags for an anonymous id. It generates this id the first time the SDK runs and keeps it in the Keychain, so an anonymous user stays in the same rollout group across launches. If the Keychain cannot be read at launch, for example during a background launch before the device's first unlock after a restart, the SDK uses a temporary id for that launch.

### identify

```swift
Coproduct.identify(userId: account.id, attributes: [
    "plan": .string("pro"),
    "seats": .number(12),
    "beta": .bool(true),
])
```

**Attributes are what your targeting rules match against.** A rule in Coproduct such as "plan is pro" matches the attribute you send here, so the names and values must match the rules on your flags exactly, including case. We recommend lower-case names with underscores, like the automatic attributes: `plan_tier`, `account_id`.

**Identity is not saved between launches.** Call `identify` on every launch, after `initialize` has returned, once you know who is signed in. An `identify` made before the SDK has started is logged and ignored.

None of the identity calls makes a network request. Each one re-evaluates the flags the SDK already has.

### The identity calls

```swift
Coproduct.updateAttributes(["plan": .string("enterprise")])
Coproduct.removeAttributes(["beta"])
Coproduct.setContext(targetingKey: team.id, attributes: ["region": .string("eu")])
Coproduct.signOut()
```

| Call | Effect |
|---|---|
| `identify(userId:attributes:linkAnonymous:)` | Sets the user id and **replaces** every attribute you set earlier. An attribute missing from the dictionary is cleared |
| `updateAttributes(_:)` | **Merges** into your attributes. Names you leave out stay as they are |
| `removeAttributes(_:)` | Removes the named attributes |
| `setContext(targetingKey:attributes:)` | Like `identify`, it replaces the identity and your attributes, but it takes the targeting key directly and does not touch `previousAnonymousId`. Use it when what you target is not a signed-in account, such as a team or a device |
| `signOut()` | Returns to this installation's anonymous id, clears your attributes, and clears `previousAnonymousId` |

`signOut` does not create a new anonymous id. The device returns to the same anonymous id it had before sign-in, so an anonymous rollout places it in the same group as before.

### When a change takes effect

The identity calls return immediately and apply in the background, in the order you make them. A read on the next line can still see the previous identity. Observations update when the change applies, which is the simplest way to follow it.

Each applied call fires a `.contextChanged` lifecycle event. The SDK also fires it when it updates an automatic attribute such as `network_type`, so a `.contextChanged` handler tells you the targeting context changed, not which call changed it.

`identify` with an empty `userId`, and `setContext` with an empty `targetingKey`, are rejected. The SDK logs the rejection, keeps the previous identity, and fires no event. The identity calls never throw.

### Attribute values

An attribute value is one of five kinds:

```swift
let attributes: [String: AttributeValue] = [
    "plan": .string("pro"),
    "seats": .number(5),                 // stored as a Double
    "beta": .bool(true),
    "groups": .stringList(["beta", "staff"]),
    "referrer": .null,                   // an explicit null, not a removed attribute
]
```

Pass large integer ids as strings. `.number` holds a `Double`, so an integer above 2^53, such as a 64-bit database id, loses precision.

### Reserved names

`user_id` and `targetingKey` are reserved. The SDK silently ignores them inside an attributes dictionary, so set identity through the `userId` or `targetingKey` parameter. A rule on `user_id` always matches the id you passed to `identify` or `setContext`, or the anonymous id before that.

### Your attributes and automatic ones

Your attributes and the [automatic attributes](#automatic-attributes) are stored separately. If you set an attribute with the same name as an automatic one, such as `locale`, your value is the one rules see while it is set. The automatic value is kept, and it applies again when you remove yours with `removeAttributes`. `identify`, `setContext`, and `signOut` never clear the automatic attributes.

### Linking an anonymous session

`Coproduct.previousAnonymousId` returns the anonymous id captured when someone signed in, so you can join their activity before sign-in to their account in your own analytics.

- `identify` captures the current anonymous id only when none is captured already, so a later `identify` does not overwrite it.
- `identify` with `linkAnonymous: false`, and `signOut`, clear it. Targeting uses the new `userId` either way.
- It is held in memory only, so it is `nil` after a relaunch until the next `identify`.
- It is not set on the line after `identify`, because the call applies in the background. Read it once the change has applied, for example in a `.contextChanged` handler.

```swift
import Combine
import Coproduct

final class SignInLinker {
    private var handle: AnyCancellable?

    // Call only after Coproduct.initialize has returned
    func signIn(userId: String) {
        handle = Coproduct.addHandler(event: .contextChanged) { _ in
            // Runs on every context change, so make the link safe to repeat
            if let anonymousId = Coproduct.previousAnonymousId {
                Analytics.link(anonymousId: anonymousId, to: userId)
            }
        }
        Coproduct.identify(userId: userId)
    }
}
```

`Analytics.link` stands in for your own analytics call. The SDK does not link the two ids anywhere or send them to Coproduct.

## Automatic attributes

The SDK sets ten attributes with no code from you, so you can target a platform, an app version, a locale, iPads, users on cellular, or new users straight away.

| Attribute | Value | Meaning | When it is set |
|---|---|---|---|
| `platform` | `"ios"` | The operating system | During `initialize` |
| `os_version` | String, three-part version, such as `"17.4.0"` | The iOS version, from `ProcessInfo.operatingSystemVersion` | During `initialize` |
| `app_version` | String, three-part version, such as `"2.3.0"` | Your app's `CFBundleShortVersionString`, padded or cut to three parts when it is a plain dotted version: `"2.1"` becomes `"2.1.0"` and `"2.1.0.5"` becomes `"2.1.0"`. A leading `v` is dropped. A value that is not a plain dotted number, such as `"2.0-beta"`, is kept as is | During `initialize`. Unset if your Info.plist has no value |
| `app_build` | String, such as `"42"` | Your app's `CFBundleVersion`. A string, not a number | During `initialize`. Unset if your Info.plist has no value |
| `locale` | Language tag, such as `"en-US"`, `"fr"`, or `"zh-Hans-CN"` | The user's first preferred language from the device settings (`Locale.preferredLanguages`), with `_` turned into `-`. Not your app's own localization | During `initialize` |
| `timezone` | IANA name, such as `"America/New_York"` | The device's time zone | During `initialize` |
| `device_type` | `"phone"` or `"tablet"`, or unset | `"phone"` for an iPhone interface, `"tablet"` for an iPad interface. Unset for any other interface idiom | During `initialize` |
| `network_type` | `"wifi"`, `"cellular"`, `"ethernet"`, `"other"`, or `"none"` | How the device is connected right now. `"other"` means connected over an interface that is none of the first three | Live. No value until the device first reports its connection, usually shortly after `initialize`. `initialize` never waits for it |
| `first_seen_at` | Number, whole seconds since the Unix epoch, UTC | When the SDK first ran in this installation of your app | During `initialize` |
| `session_count` | Number, starting at 1 | How many app launches have initialized the SDK in this installation, counting this one | During `initialize` |

- **Most are read once, when `initialize` runs.** If the device's language or time zone changes while your app runs, the old value stays until the SDK is shut down and initialized again. `network_type` is the exception: it updates when the connection changes, and observations update with it.
- **`network_type` starts unset.** Until the first reading, a condition on `network_type` does not match, except `is_not_set`, which does. Read flags that depend on connectivity through `@CoproductFlag` or an observation rather than a single getter call at launch. To match every connected device, use `network_type not_equals "none"` rather than listing the connected values.
- **Target numbers with numeric operators.** `first_seen_at` and `session_count` are numbers, so use `gte`, `lt`, and the other numeric operators.
- **How launches are counted.** `session_count` goes up once per process in which `initialize` runs, including a background launch. Calling `shutdown()` and then `initialize` again in the same process does not count again. A launch that never calls `initialize` is not counted.
- **Where they are stored.** `first_seen_at` and `session_count` are stored in your app's `UserDefaults`. They reset when the app is deleted, and they may survive a backup restore or a move to a new device. An app extension keeps its own separate values.

### Location attributes

Coproduct's servers estimate a coarse location from the device's IP address when it downloads flags, and return it with them. The SDK adds these attributes for targeting: `country` and `continent` (upper-case codes such as `"US"` and `"NA"`), `region_code` (the region or state code, upper-case), and `city`. Each is unset when Coproduct cannot determine it. Coproduct also estimates a time zone. They arrive with your flags, including the flags saved from an earlier launch, and are replaced on each successful download.

When the same name comes from more than one place, your own attributes win over the automatic ones, and the automatic ones win over the location attributes. For example, the device's `timezone` is used rather than Coproduct's estimate.

## Configuration

Pass a `CoproductConfig` to `initialize`. Every field has a default, so set only what you need:

```swift
try await Coproduct.initialize(
    sdkKey: "cpk_mob_...",
    config: CoproductConfig(
        // Check for updates every 5 minutes instead of every minute
        pollInterval: 300,
        // Wait up to 5 seconds for flags on a first launch
        startupTimeout: 5
    )
)
```

Arguments follow the initializer's order, so `pollInterval` comes before `startupTimeout`. An invalid value makes `initialize` throw `CoproductError.invalidConfig` rather than being silently corrected.

| Field | Type | Default | Notes |
|---|---|---|---|
| `pollInterval` | `TimeInterval` | `60` | Seconds between checks for updated flags. Must be at least 30 |
| `startupTimeout` | `TimeInterval` | `3` | The longest `initialize` waits for the first download. Must be at least 1. See [What startupTimeout bounds](#what-startuptimeout-bounds) |
| `pollOnForeground` | `Bool` | `true` | Check for updates whenever the app becomes active. See [Checking for updates](#checking-for-updates) |
| `endpoint` | `String?` | `nil` | Base URL flags are downloaded from. `nil` uses `https://sdk.coproduct.app`. Must be an `http` or `https` URL with a host. You only need this for a proxy |
| `requestTimeout` | `TimeInterval?` | `nil` | Timeout for each download, in seconds. `nil` uses `URLSession`'s default of 60 seconds. Applies only to the built-in transport, so if you pass your own `transport`, set timeouts there. A value that is not a positive number is ignored |
| `anonymousId` | `String?` | `nil` | Use this id instead of the generated anonymous id. It is saved in place of the stored one, so it stays in effect on later launches even if you stop passing it |
| `transport` | `(any HostTransport)?` | `nil` | Replaces the built-in `URLSessionTransport`. See [Custom transport and secure store](#custom-transport-and-secure-store) |
| `secureStore` | `(any HostSecureStore)?` | `nil` | Replaces the built-in `KeychainSecureStore`. See [Custom transport and secure store](#custom-transport-and-secure-store) |
| `evaluationListener` | `(any EvaluationListener)?` | `nil` | Receives an `EvaluationEvent` for every getter and detail getter call, synchronously on the calling thread. Values delivered through `@CoproductFlag` and observations are not reported. See [EvaluationEvent](#evaluationevent) |

`pollInterval` and `startupTimeout` must also be finite and not negative. Both are converted to whole seconds, rounding toward zero, before they are checked. So a `startupTimeout` below 1, such as `0.5`, becomes 0 and fails `initialize` with `invalidConfig`, and a `pollInterval` of `29.9` fails the 30-second minimum. A value that passes is used as given, so a `startupTimeout` of `2.5` waits up to 2.5 seconds.

### What startupTimeout bounds

`startupTimeout` limits only the wait for the first download of your flags. `initialize` returns as soon as flags are available from the device, when the first download finishes whether or not it succeeded, or when the timeout expires, whichever comes first. If Coproduct asks the SDK to slow down, the download does not count as finished, so `initialize` waits out the timeout. Setup before that wait, such as reading the Keychain and loading saved flags, is not counted, so `initialize` can take slightly longer than the value you set. `network_type` is never waited for.

## Checking for updates

While your app is running, the SDK checks Coproduct for updated flags when it starts, then every `pollInterval` (60 seconds by default). A change you make in Coproduct can take that long to reach a running app.

The SDK does not check while iOS has the app suspended in the background, and it does not use background fetch.

### Seeing a change while you develop

- **Background the app and bring it back.** With `pollOnForeground` left at `true`, the app becoming active triggers an immediate check. This is the quickest loop and needs no code change. The app also becomes active after a system alert, Control Center, or a phone call, so those trigger a check too.
- **Lower `pollInterval` while developing.** Thirty seconds is the minimum, so this halves the wait at most. Backgrounding is usually quicker.

Becoming active does not trigger a check while one is already running, while the SDK is backing off (`stale`, or when Coproduct has asked it to slow down), or after it has stopped (`fatal`).

### When checks fail

- **A failed check** is retried at the normal `pollInterval`, and `Coproduct.state` becomes `retrying`. The SDK keeps serving the flags it has.
- **After five failed checks in a row**, `Coproduct.state` becomes `stale` and the SDK checks every five `pollInterval`s (five minutes by default) until one succeeds.
- **If Coproduct asks the SDK to slow down**, it waits as long as asked, up to an hour, and never less than `pollInterval`.
- **Regaining a network connection** does not by itself trigger a check. The next check happens at the next interval or when the app becomes active.

### Saved flags

The SDK saves the flags after each successful download, in your app's Caches directory, one copy per SDK key. A launch that finds a saved copy starts in the `ready` state and serves it straight away. The saved copy survives relaunches and `shutdown()`. It is removed when the app is deleted, when the SDK key is rejected, or when iOS clears caches to free storage. In those cases the next launch behaves like a first launch.

## SDK status

`Coproduct.state` tells you what the SDK is doing. Its type is `ProviderState`. **Most apps never need it**, because getters and observations serve your defaults whenever real values are unavailable. Read it for diagnostics, a debug screen, or logging:

| State | Meaning |
|---|---|
| `notReady` | The SDK has no flags yet: nothing is saved from an earlier launch, and the first check has not completed. Also the state before `initialize` |
| `ready` | The SDK has flags, either downloaded in this session or loaded from the copy saved on an earlier launch |
| `retrying` | The last check failed, and the SDK is retrying at the normal interval. Any flags it already had are still served |
| `stale` | Five checks in a row have failed, and the SDK now checks less often. Any flags it already had are still served |
| `fatal` | Checks have stopped for this session because Coproduct rejected the request. A rejected SDK key also deletes the saved flags, so reads serve your defaults. Any other rejection, such as an endpoint that answers `404`, keeps the flags the SDK had. An endpoint that cannot be reached leads to `retrying` and `stale` instead |

On a first launch with no saved flags, `retrying` and `stale` can also mean the SDK has no flags at all.

To react when flags arrive, observe the flag you care about rather than watching `state`. See [Knowing when flags have arrived](#knowing-when-flags-have-arrived).

`fatal` is worth logging: checks have stopped and will not resume until the app restarts, or until you call `Coproduct.shutdown()` and then `initialize` again.

`Coproduct.snapshot` returns a `CoproductSnapshot` with the downloaded flags' `version`, `flagCount`, and `environment`, for diagnostics. Before `initialize` it reports version 0 and no flags.

## Lifecycle handlers and evaluation hooks

Both return an `AnyCancellable`. Store it for as long as you want the handler or hook to run. Calling `cancel()` or releasing it removes the registration. Both crash if the SDK is not running, so register them only after `initialize` has returned successfully.

```swift
import Combine
import Coproduct

final class FlagDiagnostics {
    private var handlers: Set<AnyCancellable> = []

    // Call only after Coproduct.initialize has returned
    func start() {
        Coproduct.addHandler(event: .configurationChanged) { _ in
            print("new flag definitions downloaded")
        }
        .store(in: &handlers)

        // Runs around every getter call at the chosen stage
        Coproduct.addEvaluationHook(.after) { context in
            print("\(context.flagKey) = \(String(describing: context.value))")
        }
        .store(in: &handlers)
    }
}
```

**Lifecycle handlers** receive a `LifecycleEvent`. They fire only on a change and are not replayed to a handler registered later. See [Lifecycle events](#lifecycle-events) for when each fires. Handlers for one event run one at a time, and each identity call waits for the `.reconciling` and `.contextChanged` handlers it triggers to finish, so a slow handler delays later identity calls. Keep them fast.

**Evaluation hooks** run synchronously around each getter and detail getter call, at one stage each. See [Hook stages](#hook-stages). The closure receives an `EvaluationHookContext` with the `stage`, `flagKey`, the served `value` (if any), your `defaultValue`, and the `errorCode`. For the reason and variant, use the detail getters. Values delivered through `@CoproductFlag` and observations do not run hooks.

## Errors

Flag reads, identity calls, and `shutdown()` never throw. Only `initialize` throws, never because of the network, and it always throws `CoproductError`:

| Case | When | What to do |
|---|---|---|
| `.invalidSdkKey(reason:)` | The key is empty, is not a mobile (`cpk_mob_`) key, such as a server key, or has the wrong length or characters. The reason never includes any part of the key you passed | Copy the mobile key again. It is `cpk_mob_` followed by 32 lowercase Crockford base32 characters: digits and letters other than `i`, `l`, `o`, and `u`, as issued by Coproduct |
| `.invalidConfig(field:reason:)` | A `CoproductConfig` value is out of range or malformed. `field` names it and `reason` says why | Fix the value. See [Configuration](#configuration) |
| `.cancelledByShutdown` | `shutdown()` ran before `initialize` finished | Expected if your app shuts the SDK down during startup. You can call `initialize` again |
| `.launchFailed(reason:)` | Any other startup failure | Log `reason` |

**A key with the right format that Coproduct rejects does not throw.** For example, a revoked key passes the format checks, so `initialize` succeeds. The first check is then rejected, `Coproduct.state` becomes `fatal`, and reads serve your defaults.

Rejected identity calls, such as `identify` with an empty id, are logged rather than thrown.

## Threading

Every API can be called from any thread or actor. None of it requires the main actor.

- **Getters** are synchronous reads from memory, safe to call in a SwiftUI `body`.
- **Evaluation hooks and the evaluation listener** run synchronously on the thread that called the getter, before the getter returns. Keep them fast.
- **Lifecycle handlers** run on a background thread. The closures you pass to `addHandler` and `addEvaluationHook` are `@Sendable`. Move to the main thread before touching UI.
- **`publisher` and `values`** deliver the current value on the thread that subscribes, and later values on a background thread. Use `.receive(on: DispatchQueue.main)` before touching UI.
- **`@CoproductFlag`** delivers on the main thread for you.

## Privacy and data

### What the SDK sends

The SDK makes one kind of request: it downloads your flag definitions from `<endpoint>/v1/snapshot`, which is `https://sdk.coproduct.app/v1/snapshot` unless you set `endpoint`. Each request carries:

- your SDK key;
- a `User-Agent` of `coproduct-ios/` followed by the SDK version;
- a tag identifying the flags the SDK already has, so an unchanged response can be skipped.

The system networking stack also adds standard headers. It carries no attributes, no user ids, no anonymous id, and no record of the flags you read. Flags are evaluated on the device.

Coproduct sees the IP address of each request, as any server does. It uses the address to derive the approximate location attributes `country`, `continent`, `region_code`, and `city`, and a time zone, and returns them with your flags. See [Location attributes](#location-attributes).

### What the SDK stores on the device

| Data | Where | Why |
|---|---|---|
| A random anonymous id | The Keychain, under the service `app.coproduct.sdk`, readable after the device's first unlock | So an anonymous user keeps the same rollout group across launches. Keychain items can survive deleting the app, so the id can outlive a reinstall. It is included in encrypted backups, so it can move to a new device |
| `first_seen_at` and `session_count` | `UserDefaults.standard`, under the keys `app.coproduct.firstSeenAt` and `app.coproduct.sessionCount` | To count launches |
| The last downloaded flags, with the approximate location Coproduct derived for the device | Your app's Caches directory, under `coproduct/`, one copy per SDK key | So later launches start with flags. See [Saved flags](#saved-flags) |

The user id you pass to `identify` and the attributes you set are held in memory only.

### Privacy manifest

The package does not yet include a privacy manifest (`PrivacyInfo.xcprivacy`), and one is required before it is released. The SDK reads and writes `UserDefaults`, which Apple lists as a required-reason API. If you ship an app build with this SDK, declare that access in your app's own `PrivacyInfo.xcprivacy`, under `NSPrivacyAccessedAPITypes`, with the category `NSPrivacyAccessedAPICategoryUserDefaults` and the reason `CA92.1`. The SDK's code is linked into your app's binary, so your app's manifest covers it. Add the same entry to any app extension that uses the SDK. The SDK has not yet been checked for every required-reason API it uses. If App Store Connect reports another missing reason after you upload a build, declare the reason that matches the SDK's use.

Google Play's Data safety form and Apple's App Privacy details can treat the approximate location above as collected data. Check both against Coproduct's data retention policy before you submit your app.

## Testing and previews

The SDK does not include a testing library yet.

- **SwiftUI previews** need nothing. Without `initialize`, `@CoproductFlag` and every getter serve your defaults.
- **Unit tests.** Put flag reads behind a small protocol your code depends on, and give tests a fake that returns the values each test needs:

  ```swift
  protocol FeatureFlags {
      func isEnabled(_ key: String) -> Bool
  }

  struct CoproductFlags: FeatureFlags {
      func isEnabled(_ key: String) -> Bool {
          Coproduct.getBool(key, default: false)
      }
  }

  struct FakeFlags: FeatureFlags {
      var enabled: Set<String> = []

      func isEnabled(_ key: String) -> Bool {
          enabled.contains(key)
      }
  }
  ```

- **Tests against the real SDK.** The SDK is one shared instance per process, so call `await Coproduct.shutdown()` between tests. Flags downloaded in one run are saved in the simulator's Caches directory and served on the next launch.
- **Running tests.** Use `xcodebuild` with an iOS Simulator destination. `swift test` cannot build the SDK.

## Troubleshooting

**A flag always returns the default I passed.** Your default appears only when the SDK cannot resolve the flag. Work through these in order:

1. The flag key is misspelled, or no flag with that key exists in the environment of your SDK key. This is the most common cause.
2. The flag's type does not match the read. A string flag read with `getBool` returns your default.
3. The SDK has no flags yet. `Coproduct.state` is `notReady` before the first check completes. On a first launch with no saved flags, `retrying` and `stale` mean the checks are failing and nothing has downloaded.
4. The SDK key was rejected. `Coproduct.state` is `fatal`, and the saved flags were deleted.
5. `initialize` has not been called, threw, or was followed by `shutdown()`.

`getBoolDetails` and the other detail getters tell you which it is: see `reason` and `errorCode` in [Reasons and error codes](#reasons-and-error-codes).

**A flag returns a value, but not the one I expect for this user.**

- A switched-off or paused flag serves its off value, and a user who matches no rule gets the fallthrough value. Check the flag's state and rules in Coproduct.
- Confirm that you called `identify` on this launch, after `initialize` returned. Identity is not saved between launches, and an `identify` before `initialize` is ignored.
- Check that your attribute names and values match the rule exactly, including case.
- `identify` and `setContext` replace every attribute you set earlier. Use `updateAttributes` to add to them.
- An attribute you set overrides an automatic attribute with the same name. See [Your attributes and automatic ones](#your-attributes-and-automatic-ones).
- A flag whose prerequisite is not met serves its off value even when it is switched on. So does a flag whose rules use a condition this SDK version does not understand. Check its prerequisites, and update the SDK if the flag uses a newer operator.
- If you just changed the flag, the app may not have checked for updates yet. See [Checking for updates](#checking-for-updates).

**The app shows last session's value for a moment after launch.** This is the saved copy from the previous launch. The SDK serves it straight away and replaces it when the first check completes.

**My view does not update when I change the flag.** If the value never updates however long you wait, you are probably calling a getter inside `body`, or an observation was released. Use `@CoproductFlag`, or store the observation's `AnyCancellable`. See [Which read API to use](#which-read-api-to-use). If it updates eventually, that is the interval between checks. See [Seeing a change while you develop](#seeing-a-change-while-you-develop).

**The app hangs at launch waiting for flags.** Do not wait for a `.ready` lifecycle event. It does not fire when flags come from the device, and a handler registered late misses it. See [Knowing when flags have arrived](#knowing-when-flags-have-arrived).

**The app crashes in `observe`, `addHandler`, or `addEvaluationHook`.** They need a running SDK. Call them after `initialize` returns successfully and before `shutdown()`, or use `@CoproductFlag`, which does not need one.

**`initialize` throws `invalidSdkKey`.** The key is not a mobile key, or it was mangled when copied. It must be `cpk_mob_` followed by 32 lowercase Crockford base32 characters: digits and letters other than `i`, `l`, `o`, and `u`, as issued by Coproduct.

**`initialize` throws `invalidConfig` for `startupTimeout`.** The value is below 1 second. See [Configuration](#configuration).

**`state` is `fatal`.** Coproduct rejected the requests. Check the SDK key and any custom `endpoint`. A revoked or unknown key also deletes the saved flags, so reads serve your defaults. Checks stay stopped until the next launch.

**A background launch right after the device restarts gets different values.** Before the device's first unlock, the Keychain cannot be read, so the SDK uses a temporary anonymous id for that launch. Percentage rollouts can place that launch in a different group.

**`swift build` or `swift test` fails with a missing module.** The SDK is iOS only. Build with `xcodebuild` and an iOS Simulator destination.

## Reference

### Lifecycle events

`addHandler(event:handler:)` takes a `LifecycleEvent`:

| Event | Fires when |
|---|---|
| `ready` | The state changes to `ready`, for example when the first download succeeds or checks recover. Not fired when flags are loaded from the device at launch |
| `configurationChanged` | New flag definitions were downloaded |
| `contextChanged` | The targeting context changed: an identity call applied, or the SDK updated an automatic attribute |
| `reconciling` | Just before each `contextChanged` |
| `retrying` | The state changes to `retrying` |
| `stale` | The state changes to `stale` |
| `fatal` | The state changes to `fatal` |

### Hook stages

`addEvaluationHook(_:handler:)` takes an `EvaluationHookStage`. `.before` runs before the flag is evaluated. After it, exactly one of `.after` (no error code) or `.error` (an error code was set) runs, and then `.finally` always runs.

### Reasons and error codes

On `FlagEvaluationDetails`, `reason` and `errorCode` are strings, so new values can be added. Handle unknown values with a default branch.

`reason` tells you why the value was chosen:

- `TARGETING_MATCH`: a targeting rule matched.
- `DEFAULT`: no rule matched, so the flag's fallthrough value was served. This is the flag's value in Coproduct, not the `default:` you passed.
- `DISABLED`: the flag is off or paused, or a prerequisite is not met, so its off value was served.
- `ERROR`: see `errorCode`. Your `default:` was served, except for `RULE_CIRCUIT_BREAK`, which serves the flag's off value.

`errorCode` is `nil` on success, or one of:

- `PROVIDER_NOT_READY`: no flags downloaded yet, or the SDK is not running;
- `FLAG_NOT_FOUND`: no flag with that key;
- `TYPE_MISMATCH`: the flag's type does not match the getter;
- `RULE_CIRCUIT_BREAK`: a rule uses a condition this SDK version does not understand, or the flag's prerequisites form a cycle or a chain more than five flags deep. The flag's off value is served;
- `PARSE_ERROR`, `PROVIDER_FATAL`, or `GENERAL`: other failures.

### EvaluationEvent

An `EvaluationListener` receives an `EvaluationEvent` for each getter call, with `flagKey`, `flagType`, `value`, `defaultValue`, `variant`, `reason`, `ruleId`, `errorCode`, and `evaluatedAt`. Its `reason` is an `EvaluationReason` enum with a different vocabulary from `FlagEvaluationDetails.reason`: `targetingMatch`, `fallthrough`, `off`, `prerequisiteFailed`, and `error`. This version never sets `ruleId`, so it is always `nil`. The listener runs on the calling thread, so keep it fast. The SDK does not send these events anywhere.

### Custom transport and secure store

By default the SDK downloads flags with `URLSessionTransport` and keeps its anonymous id in `KeychainSecureStore`.

`URLSessionTransport(session:requestTimeout:)` uses `URLSession.shared` by default. It follows App Transport Security and the system proxy settings, but does no certificate pinning of its own. To pin certificates, pass a `URLSession` configured with your own delegate:

```swift
let session = URLSession(configuration: .default, delegate: PinningDelegate(), delegateQueue: nil)

try await Coproduct.initialize(
    sdkKey: "cpk_mob_...",
    config: CoproductConfig(transport: URLSessionTransport(session: session))
)
```

`PinningDelegate` stands in for your own `URLSessionDelegate`.

`KeychainSecureStore(service:)` stores items under the service `app.coproduct.sdk` by default.

To replace either, conform to the protocol:

- `HostTransport` has one requirement, `func request(req: HttpRequest) async throws -> HttpResponse`. Return every HTTP response, including error statuses, as an `HttpResponse`: the SDK acts on the status code, and a `401` tells it the key was rejected. Any error the transport throws, including `TransportError.Unauthorized`, is treated as a temporary failure and retried. To report a rejected key, return the `401` response rather than throwing.
- `HostSecureStore` has two requirements, `func read(key: String) async throws -> String?` and `func write(key: String, value: String) async throws`. Return `nil` from `read` for a missing item. If `read` throws, the SDK uses a temporary anonymous id for that launch.

All three protocols are class-bound and `Sendable`, so conform with a `final class`. `EvaluationListener` has one requirement, `func onEvaluation(event: EvaluationEvent)`, called synchronously on the thread that called the getter.

## Building from source

Building the SDK from source needs the Rust toolchain pinned in the repository's `rust-toolchain.toml`, because the package's binary, `CoproductFFI.xcframework`, is built from Rust and is not checked in. The repository's `sdks/ios/BUILDING.md` lists the build steps. Once the binary is built, you can add the `sdks/ios` directory to an app as a local package.

## License

Apache License 2.0. See [LICENSE](../../LICENSE).
