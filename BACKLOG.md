# Backlog

Known gaps and deferred work, with enough context to decide whether each blocks
a release. Newest first within each section.

## Flutter SDK

### Four auto-populated attributes are advertised but never populated

**Status: open. Considered essential for 1.0.0 by the product owner; see the
decision note at the end of this entry.**

The `2026-07-08-auto-populated-attributes-design.md` spec defines ten attributes
the SDKs populate with no code from the developer. iOS implements all ten. The
Flutter SDK implements six: `platform`, `os_version`, `app_version`,
`app_build`, `locale`, and `timezone`.

Missing on Flutter:

| Attribute | iOS source | Why Flutter does not have it |
|---|---|---|
| `device_type` | `UIUserInterfaceIdiom` (`DeviceContext.swift`) | Deferred for a technical reason: no reliable cross-platform classifier. Inferring phone versus tablet from screen dimensions guesses, and a wrong guess silently routes a user into the wrong cohort |
| `network_type` | `NWPathMonitor` (`NetworkMonitor.swift`) | Scoped out of the Flutter 0.1.0 milestone |
| `first_seen_at` | `UserDefaults` (`SessionStore.swift`) | Scoped out of the Flutter 0.1.0 milestone |
| `session_count` | `UserDefaults` (`SessionStore.swift`) | Scoped out of the Flutter 0.1.0 milestone |

The three milestone deferrals are recorded in
`2026-07-22-flutter-host-runtime-design.md`: "The typed reactive layer, provider
widget, detail getters, hooks, session attributes, `device_type`, and public
transport/store injection are out of scope (0.2.0+)." The reactive layer from
that same list shipped in 0.2.0. These four did not, and 1.0.0 arrived without
anyone revisiting them.

**Why it matters more than a missing feature.** The platform advertises all four
in `KNOWN_STANDARD_ATTRIBUTES` (`packages/snapshot-spec/src/standard-attributes.ts`)
and the authoring validator suppresses its unknown-attribute warning for
anything on that list. So an author writes `device_type equals "tablet"` against
a Flutter app, sees no warning, and publishes. The attribute is absent on the
device, the condition resolves indeterminate, the rule never matches, and every
user gets the fallthrough. Nothing on the device or in the dashboard says so.

**What each would take.**

- `first_seen_at` and `session_count` need host-owned persistent storage. The
  spec is specific that this is `UserDefaults` / `SharedPreferences` and
  deliberately not the Rust cache directory, because cache directories are
  OS-purgeable and a purge would silently move users between cohorts. It also
  names a Flutter-specific trap: hot restart re-runs `main()` without a new OS
  process, so an in-memory session guard would double-count.
- `network_type` needs a connectivity source plus live updates through the
  existing bulk upsert, and carries a documented startup window where it is
  briefly absent.
- `device_type` remains genuinely blocked on the classifier problem above.

**The platform-side counterpart, which is separate and cheaper.** Even with the
Flutter work done, the validator should not silently accept a rule on an
attribute the target SDK does not populate. Either warn per-SDK, or scope
`KNOWN_STANDARD_ATTRIBUTES` to what the SDKs actually ship. This fix reaches
every author the moment it deploys, with no SDK release.

**Decision note.** Adding auto-populated attributes is additive, so shipping
1.0.0 without them breaks nothing later. The argument for blocking is not
compatibility, it is that the platform promises targeting that silently does not
work on Flutter. The cheapest fix for that specific harm is platform-side.
Whether the SDK work blocks 1.0.0 is a product call, not a technical one.

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
