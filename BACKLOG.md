# Backlog

Known gaps and deferred work, with enough context to decide whether each blocks
a release. Newest first within each section.

## Flutter SDK

### Three auto-populated attributes are advertised but never populated

**Status: open. Considered essential for 1.0.0 by the product owner; see the
decision note at the end of this entry.**

The `2026-07-08-auto-populated-attributes-design.md` spec defines ten attributes
the SDKs populate with no code from the developer. iOS implements all ten. The
Flutter SDK implements seven: `platform`, `os_version`, `app_version`,
`app_build`, `locale`, `timezone`, and `device_type`.

`device_type` has landed, from the interface idiom on iOS and `uiMode` plus
`smallestScreenWidthDp` on Android. The
"no reliable cross-platform classifier" assessment it carried here was wrong:
neither platform needs the screen-dimension inference that made it look blocked.

Still missing on Flutter:

| Attribute | iOS source | Why Flutter does not have it |
|---|---|---|
| `network_type` | `NWPathMonitor` (`NetworkMonitor.swift`) | Scoped out of the Flutter 0.1.0 milestone |
| `first_seen_at` | `UserDefaults` (`SessionStore.swift`) | Scoped out of the Flutter 0.1.0 milestone |
| `session_count` | `UserDefaults` (`SessionStore.swift`) | Scoped out of the Flutter 0.1.0 milestone |

The three milestone deferrals are recorded in
`2026-07-22-flutter-host-runtime-design.md`: "The typed reactive layer, provider
widget, detail getters, hooks, session attributes, `device_type`, and public
transport/store injection are out of scope (0.2.0+)." The reactive layer from
that same list shipped in 0.2.0. Of the four that did not, `device_type` has since
landed; the remaining three are still missing with 1.0.0 unpublished, and nobody
revisited them in the meantime.

**Why it matters more than a missing feature.** The platform advertises all ten
in `KNOWN_STANDARD_ATTRIBUTES` (`packages/snapshot-spec/src/standard-attributes.ts`)
and the authoring validator suppresses its unknown-attribute warning for
anything on that list. So an author writes `network_type not_equals "none"`
against a Flutter app, sees no warning, and publishes. The attribute is absent on
the device, the condition resolves indeterminate, the rule never matches, and
every user gets the fallthrough. Nothing on the device or in the dashboard says
so.

**What each would take.**

- `first_seen_at` and `session_count` need host-owned persistent storage.
  `UserDefaults` / `SharedPreferences`, and deliberately **not** the Rust cache
  directory: cache directories are OS-purgeable, and a purge would silently move
  users between cohorts. `first_seen_at` must survive process launches by
  definition, so this storage is required regardless of how sessions are counted.

  The session guard anchors to the OS process, not to the Dart entrypoint. The
  production case this protects against is add-to-app: a Flutter module embedded
  in a native host runs its entrypoint once per `FlutterEngine`, in the same
  process, so an in-memory guard resets when the host recreates an engine or uses
  `FlutterEngineGroup`, and `session_count` double-counts in release builds. Hot
  restart shows the same symptom in development, which is the easy way to notice
  it, but is not the reason for the rule. Standalone release apps get one
  entrypoint per process launch and would be unaffected either way.

  `session_count` is documented as approximate: the spec already accepts that
  Android multi-process apps double-count because `SharedPreferences` is not
  multi-process safe.
- `network_type` needs a connectivity source plus live updates through the
  existing bulk upsert, and carries a documented startup window where it is
  briefly absent.
**The platform-side counterpart is no longer needed.** The earlier plan was to
stop the validator silently accepting a rule on an attribute the target SDK does
not populate, by warning per-SDK or scoping `KNOWN_STANDARD_ATTRIBUTES` to what
the SDKs actually ship. The chosen fix is the other direction: every SDK that
ships populates every advertised attribute, so the list stays true and no
platform change is required.

**Decision note.** Design settled in
`docs/superpowers/specs/2026-09-21-flutter-auto-populated-attributes-completion-design.md`,
scoped into 1.0.0. The SDK ships a small native host-context plugin class for
`device_type` and an atomic session transaction, and a `connectivity_plus`
adapter for `network_type`. 1.0.0 is unpublished, so establishing this behavior
before the first release avoids a targeting shift on upgrade.

### The published Android toolchain floor is not proven, and the README is imprecise

**Status: open. A release gate for 1.0.0, and it predates the auto-populated
attribute work that surfaced it.**

The package declares Flutter `>= 3.38.1` and the README's requirements table says
`Gradle (Android side) | 8.x or later`. But `flutter_tools` at 3.38.1 generates
an Android project with AGP 8.11.1, Gradle 8.14, and Kotlin 2.2.20, while
`device_info_plus` 13.2.0 and `package_info_plus` 10.2.1, both already
dependencies, publish a requirement of AGP `>= 8.12.1` and Gradle wrapper
`>= 8.13` (plus Java 17, Kotlin 2.2.0, and Xcode `>= 26.1.1`). The generated AGP
is below what dependencies the SDK already ships say they need, and the README
names no AGP requirement at all.

Nothing here is caused by a new dependency. `AGENTS.md` already records that the
Flutter example pins AGP 8.12.1 because that is "the floor `device_info_plus` and
`package_info_plus` require". What was never reconciled is that number against
the Flutter version published as the package minimum.

The floor gate cannot catch it as written. `gates/gate-suite.sh` builds
`consumer-tests/flutter`, which pins AGP 9.0.1 and Gradle 9.1.0, and the example
pins 8.12.1 by hand. The floor is proven only against a hand-pinned modern AGP,
never against what `flutter create` emits at the declared minimum, which is what
an adopter actually gets.

Published requirements do not prove a build failure, so resolve it by building: a
clean consumer app at the advertised floor with generated defaults, establishing
what actually works. Then either align the dependencies with the floor or state
the additional host-project toolchain requirements accurately, replacing the
`8.x or later` line. Before 1.0.0 publishes.

This also gates a dependency decision. The completion design prefers
`connectivity_plus` 7.3.1 for `network_type` precisely because it adds no
published requirement beyond the current dependency set. If this task resolves by
downgrading `device_info_plus` or `package_info_plus` to support an unmodified
Flutter 3.38.1 project, that choice is revisited against the lowered floor.

## Flutter SDK, additive follow-ups

Ordered by cost against value. None is breaking; all can ship after 1.0.0.

- **A public `refresh()`.** The poll interval defaults to 60 seconds with a
  30-second floor, so a flag change takes up to a minute to appear and the only
  workaround is backgrounding the app. `poll_now` already exists in the core and
  is exposed through FRB, but it is wired into the Scheduler and the client has
  no path to it. Needs a designed contract: return type, behavior when a poll is
  already in flight, behavior in `fatal` where the scheduler has stopped, and
  what it means for the in-memory test harness.
- **Stream-shaped observations.** `FlagObservation` is a `ValueListenable`,
  which suits Provider. Riverpod and BLoC each need an adapter, roughly twenty
  lines for BLoC, repeated per flag. A subscription-owned stream whose
  cancellation disposes the underlying observation would remove that.
- **Leak accounting on `CoproductTestHarness`.** `addTearDown(harness.shutdown)`
  cleans up everything, which hides the exact observation leak these
  integrations are prone to. An `activeObservationCount` would let a test unmount
  a screen and assert disposal.
- **Evaluation details.** Blocked on core work, not on the Flutter surface:
  `EvaluationEvent` carries no targeting key or context, and `rule_id` is
  permanently `None` pending pipeline plumbing. The Flutter diagnostics spec is
  marked `deferred, revise before implementing`.
- **Experiment tracking.** No evaluation listener, so no exposure recording.
  1.0.0 is scoped to flags and the README and CHANGELOG say so.

## Cross-platform

### The React Native SDK namespaces itself `com.coproduct`

**Status: open. Cheap now, breaking after React Native publishes.**

Every other surface uses `app.coproduct.*`: the Android SDK's namespace and Kotlin
package are `app.coproduct`, and iOS namespaces every runtime identifier the same
way (`app.coproduct.firstSeenAt`, `app.coproduct.sdk`, the `app.coproduct.host-timer`
and `app.coproduct.network-monitor` queue labels, the `app.coproduct.defaultInstanceReady`
notification). The demo and consumer-test apps follow `app.coproduct.<role>.<framework>`.

React Native alone uses `com.coproduct`. It is a `create-react-native-library`
template default rather than a decision, the same way the Flutter plugin carried
`com.flutter_rust_bridge.coproduct` from its own scaffold.

Beyond consistency, `app.coproduct` is the correct reverse-DNS for the domain this
project actually owns, `coproduct.app`. `com.coproduct` asserts `coproduct.com`.

The change is six string sites plus one directory move:

```
package.json                       "javaPackageName": "com.coproduct"
android/build.gradle:54            namespace "com.coproduct"
android/build.gradle:142           codegenJavaPackageName = "com.coproduct"
android/src/main/java/com/coproduct/CoproductModule.kt
android/src/main/java/com/coproduct/CoproductPackage.kt
android/src/main/AndroidManifest.xml
```

Two of those are `codegenJavaPackageName`, so the generated sources follow rather
than needing hand edits. Move the source directory to `android/src/main/java/app/coproduct/`.

**Verify with a native build, not a typecheck.** The React Native ABI changes with the
FFI surface, and a package rename moves the generated JSI sources, so this needs
`scripts/build/source-linked-rn-demo-android.sh` rather than a TypeScript compile.

Do it before React Native publishes. A native namespace is compatibility surface once
consumers exist, and nothing downstream depends on it today: React Native is still at
the binding-validation stage.

### Flutter plugins that apply the Kotlin Gradle Plugin will stop building

**Status: open. Gated on the Flutter floor rising to the version that enforces it.**

Every Android build of a consuming app now prints:

> Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
> coproduct, flutter_timezone. Future versions of Flutter will fail to build if
> your app uses plugins that apply KGP.

The Coproduct plugin joined that list when it gained a Kotlin source set for the
host-context plugin class. `flutter_timezone` was already on it, so the SDK is not
the sole cause, but it is now one of them.

The fix Flutter documents is migrating to `com.android.built-in-kotlin`. Two
reasons not to do it yet, both concrete:

- `consumer-tests/flutter/android/gradle.properties` sets
  `android.builtInKotlin=false`, and its root build applies
  `org.jetbrains.kotlin.android` to every `com.android.library` subproject. A
  migrated module would conflict with the release gate's own project.
- Built-in Kotlin is not available at the Android Gradle Plugin version the
  declared Flutter floor generates.

Revisit when the floor rises. The module compiles today at both ends of the
supported range, AGP 8.11.1 through 9.0.1, so nothing is broken now.
