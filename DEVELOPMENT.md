# Development

This file covers working on the Coproduct client SDKs: prerequisites, the build script for each surface, changing the SDKs, releasing them, and recovering disk space. Contributors start with `RELEASING.md`, which covers PR titles and the shared-core rule.

## Prerequisites

| Tool | Version | Source |
|---|---|---|
| Rust | 1.95.0 (pinned in `rust-toolchain.toml`) | `rustup` |
| JDK | 17 | `brew install openjdk@17` |
| Node | 24 (CI pins 24.14.0) | `nvm` or `asdf` |
| Flutter | 3.38.1 or later. Releases use exactly 3.44.0, and the floor gate uses 3.38.1, both through FVM | https://flutter.dev/docs/get-started/install |
| Android SDK | API 36.1 | Android Studio |
| Android NDK | 27.1.12297006 | Android Studio SDK Manager |
| Xcode | 16.0+ to build; exactly 26.5 to cut a release | Mac App Store |
| CocoaPods | 1.x | `brew install cocoapods` |

Required environment variables for Android builds:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006
```

## Build scripts

Every SDK surface has a build script under `scripts/build/`. The scripts run on macOS local dev and on GitHub Actions runners (Linux for Android-only surfaces, macOS for iOS-touching surfaces). Each prints a status line on success, such as `COPRODUCT_SOURCE_LINKED_IOS_DEMO_BUILD_STATUS pass=true`, that CI can match.

Two linkage models, named explicitly:

- **`source-linked-*`** — the SDK is consumed as workspace code (Gradle composite build, SwiftPM local reference, npm `path:`, Flutter `path:`). Fast inner loop for SDK authors. Not a release gate.
- **`artifact-linked-*`** — the SDK is consumed as a packaged release artifact (`.tgz`, mavenLocal, SwiftPM zip+checksum fixture). Catches publish/install/autolink bugs that source-linked builds cannot. Release gate.

### Source-linked (SDK author inner loop)

| Surface | Script |
|---|---|
| iOS native demo (`examples/ios-demo/`) | `./scripts/build/source-linked-ios-demo.sh` |
| Android native demo (`examples/android-demo/`) | `./scripts/build/source-linked-android-demo.sh` |
| React Native demo, iOS (`sdks/react-native/coproduct/example/`) | `./scripts/build/source-linked-rn-demo-ios.sh` |
| React Native demo, Android (`sdks/react-native/coproduct/example/`) | `./scripts/build/source-linked-rn-demo-android.sh` |
| Flutter demo, iOS (`sdks/flutter/coproduct/example/`) | `./scripts/build/source-linked-flutter-demo-ios.sh` |
| Flutter demo, Android (`sdks/flutter/coproduct/example/`) | `./scripts/build/source-linked-flutter-demo-android.sh` |

### Artifact-linked (release gate)

| Surface | Script |
|---|---|
| iOS consumer-test (`consumer-tests/ios/`) | `./scripts/build/artifact-linked-ios-consumer-test.sh` |
| Android consumer-test (`consumer-tests/android/`) | `./scripts/build/artifact-linked-android-consumer-test.sh` |
| React Native consumer-test, iOS (`consumer-tests/react-native/`) | `./scripts/build/artifact-linked-rn-consumer-test-ios.sh` |
| React Native consumer-test, Android (`consumer-tests/react-native/`) | `./scripts/build/artifact-linked-rn-consumer-test-android.sh` |
| Flutter consumer-test, iOS (`consumer-tests/flutter/`) | `./scripts/build/artifact-linked-flutter-consumer-test-ios.sh` |
| Flutter consumer-test, Android (`consumer-tests/flutter/`) | `./scripts/build/artifact-linked-flutter-consumer-test-android.sh` |

The React Native scripts take an optional app directory, such as
`consumer-tests/react-native-floor` for the minimum supported React Native, and
install a prebuilt package when `COPRODUCT_RN_TGZ` names one.

### Acceptance (device-running)

Two more gates run the Flutter SDK against an already-booted simulator or emulator, exercising real device runtime behavior rather than just a build. They do not boot or provision a device; point them at a device that is already running.

| Surface | Script | Required env var |
|---|---|---|
| Flutter acceptance, iOS | `./scripts/build/artifact-linked-flutter-acceptance-ios.sh` | `COPRODUCT_ACCEPTANCE_IOS_DEVICE` |
| Flutter acceptance, Android | `./scripts/build/artifact-linked-flutter-acceptance-android.sh` | `COPRODUCT_ACCEPTANCE_ANDROID_DEVICE` |

Find a booted device id with `flutter devices`. The Android gate also requires `JAVA_HOME`, `ANDROID_HOME`, and `ANDROID_NDK_HOME` as above.

Each acceptance gate runs the device suite twice. The first pass starts from an
uninstalled app and keeps it installed with `--no-uninstall`. That flag does not
exist in Flutter 3.38.1, the floor, so the gate needs a newer release. The
release gate suite runs it on 3.44.0. The runner waits, then runs the suite
again against the same install, so the second pass is a real process relaunch
and the session attributes are checked across it.
The runner reads the `first_seen_at` bounds from the device's own clock (a
simulator shares the host's), because an emulator can run minutes behind the
host, and it fails the run if that clock steps against the host's by more than a
few seconds across either pass. Each run logs the device's offset from the host.

Storage-failure behavior is verified through fault injection at the native
storage layer on both platforms and through Dart host tests for failed and
malformed native results. No device acceptance gate induces an actual
platform-storage failure. Persistence across a real process relaunch is covered
end to end. Concurrent callers and process-lifetime deduplication are verified
at the native transaction layer. Registration through two real FlutterEngines
and behavior through a driven Flutter hot restart are not covered end to end.

### Supporting packaging scripts

The iOS scripts depend on these packaging scripts that can also be run on their own:

- `./scripts/package/ios-build-xcframework.sh` — builds `CoproductFFI.xcframework` from Rust source: the three iOS triples, regenerated Swift bindings and C header, a lipo of the two simulator slices, then `xcodebuild -create-xcframework`. Run it whenever the Rust FFI surface changes so any SwiftPM consumer links against an xcframework that matches the live symbols. `source-linked-ios-demo.sh` runs it automatically.
- `./scripts/package/ios-spm-binary.sh` — archives the existing `CoproductFFI.xcframework` into a SwiftPM zip plus checksum under `build/ios-spm/`. It does not build the xcframework, so build it first.
- `./scripts/package/ios-spm-fixture.sh` — packages the full SwiftPM fixture (zip + checksum) that the iOS consumer-test consumes via `file:`. Invokes the binary script internally.

## Building your own app against the Flutter SDK

Adopters depend on the published `coproduct` package from pub.dev, as its README
shows. To try changes that are not published yet, in an app that is not the
example or the consumer test, depend on the working copy instead. This is the
path for a demo, a spike, or evaluating an unreleased change.

```bash
flutter create my_demo
cd my_demo
```

Point the dependency at the checkout, using an absolute path or one relative to
your app:

```yaml
dependencies:
  coproduct:
    path: /path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

**Build the native libraries first.** A `path:` dependency source-links the SDK,
whose libraries are gitignored build output and absent from a clean checkout.
Without them the app compiles and then fails at `initialize`:

```bash
scripts/package/flutter-build-native.sh all
```

Rerun it after any change to the Rust core or the FRB surface. A stale library
surfaces as an FRB content-hash mismatch at `initialize`, not as a link error.

**Set the iOS platform minimum.** A new Flutter app has no `ios/Podfile` until
its first iOS build generates one, and that build then stops because the pod
needs iOS 15.0. In the generated `ios/Podfile`, uncomment the `platform` line as
`platform :ios, '15.0'` and build again. Android needs nothing: a new app on
Flutter 3.38.1 or later already uses `minSdk = 24`.

Then use the SDK exactly as the package README describes. You need a mobile SDK
key and a flag from [coproduct.app](https://coproduct.app); the key is read
however your app chooses, and `--dart-define` keeps it out of source:

```bash
flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
```

Before demonstrating live, know that the poll interval defaults to 60 seconds
with a 30 second floor, so a flag changed in Coproduct takes up to a minute to
appear on its own. To show a change on demand, call `client.pollNow()`, or
background and foreground the app, which also polls.

## Changing the SDK

### Rust core or the Flutter FFI surface

Editing `core/coproduct-core` or `ffi/coproduct-ffi-frb/src/api.rs` is not
enough on its own. The Dart bindings under
`sdks/flutter/coproduct/lib/src/rust/` are generated, and a stale copy does not
fail to link: it surfaces at runtime as an FRB content-hash mismatch inside
`Coproduct.initialize`, far from the edit that caused it.

Regenerate, format, then rebuild the native libraries:

```bash
cd sdks/flutter/coproduct        # the only directory holding flutter_rust_bridge.yaml
flutter_rust_bridge_codegen generate
cd - && cargo fmt --all          # codegen output is not rustfmt-clean on its own
scripts/package/flutter-build-native.sh all
```

`flutter-build-native.sh` compiles the native libraries. It does **not**
regenerate bindings, and neither do the source-linked demo scripts, so the
codegen step is yours to remember after any change to the FFI surface.

### What to run before you push

```bash
cargo test --workspace                                    # the Rust core and both FFI crates
(cd sdks/flutter/coproduct && flutter analyze && flutter test)
(cd scripts/release/flutter && dart test)                 # the release tooling
(cd scripts/acceptance && dart test)                      # the device-acceptance harness
```

The Flutter release pipeline runs the second and third and fails on either. It
does not run `cargo test` or the acceptance harness's own tests, so run those
before pushing a change to the Rust core or to `scripts/acceptance`.

### Native unit suites

The Flutter plugin's Kotlin and Swift code (the session store, the device
classifier, and the network observer) has unit tests of its own. The release
gate suite runs them, but nothing else does, so run them whenever you change
anything under `sdks/flutter/coproduct/android/src` or
`sdks/flutter/coproduct/ios`. Both run against the example app.

```bash
# Kotlin, which needs JDK 17. `/usr/libexec/java_home -v 17` does not always
# find a Homebrew JDK, so set JAVA_HOME to it directly
(cd sdks/flutter/coproduct/example/android && \
  JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :coproduct:testDebugUnitTest)

# Swift, on a booted simulator. Run pod install after adding a file under
# ios/Classes or ios/Resources: CocoaPods records a development pod's files
# when it installs, so a new file is otherwise not compiled
(cd sdks/flutter/coproduct/example/ios && pod install && \
  xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
    -parallel-testing-enabled NO \
    -destination "platform=iOS Simulator,id=<booted simulator id>")
```

The same applies to `consumer-tests/flutter/ios`: run `pod install` there too
after adding a file under `ios/Classes`, or its stale CocoaPods snapshot fails
the iOS acceptance gate's build.

Read the Kotlin results from the JUnit reports under
`sdks/flutter/coproduct/example/build/coproduct/test-results/` rather than from
the exit status of a piped command. `-parallel-testing-enabled NO` keeps the
Swift tests on the simulator you named: the scheme allows parallel testing,
which runs them on a clone and shuts your simulator down.

## Manual build commands

The scripts above wrap these commands. Use them directly when you need partial steps or are debugging a specific stage.

### Source-linked

iOS native demo:

```bash
./scripts/package/ios-build-xcframework.sh
cd examples/ios-demo
xcodebuild -scheme ios-demo -destination 'generic/platform=iOS Simulator' build
```

Android native demo:

```bash
cd examples/android-demo
./gradlew :app:assembleDebug
```

React Native demo:

```bash
cd sdks/react-native/coproduct
yarn install --immutable
# Then either:
yarn example android --no-packager --active-arch-only
# OR
yarn example ios --no-packager
```

Flutter demo. The example source-links the SDK, whose native libraries are
gitignored build output and absent from a clean checkout, so build them first:

```bash
scripts/package/flutter-build-native.sh all
cd sdks/flutter/coproduct/example
flutter pub get
flutter run -d <device_id> --dart-define=COPRODUCT_SDK_KEY=<key>
```

The source-linked demo scripts do the native build for you and are the
supported path:

```bash
scripts/build/source-linked-flutter-demo-ios.sh
scripts/build/source-linked-flutter-demo-android.sh
```

### Artifact-linked

iOS consumer-test:

```bash
./scripts/package/ios-spm-fixture.sh
# then open consumer-tests/ios/CoproductConsumerIOS in Xcode and run on a simulator
```

Android consumer-test:

```bash
cd examples/android-demo
./gradlew :coproduct-android:publishToMavenLocal
cd ../../consumer-tests/android
./gradlew :app:assembleRelease
```

React Native consumer-test. The native libraries are gitignored, and packing
refuses to run without them, so build them first:

```bash
scripts/package/rn-build-native.sh
cd consumer-tests/react-native
npm run setup   # packs the SDK and installs the tarball
npm run android # or: cd ios && pod install && cd .. && npm run ios
```

Flutter consumer-test. **Run through the scripts, not by hand.** The checked-in
`consumer-tests/flutter` resolves `coproduct` through an in-repository `path:`
dependency, so running it directly tests the source tree and not a packaged
release — the opposite of what artifact-linked means. What makes it
artifact-linked is `stages/consumer-from-archive.sh`, which copies the app to a
disposable directory and repoints it at the extracted archive with a
`pubspec_overrides.yaml`.

```bash
scripts/build/artifact-linked-flutter-consumer-test-ios.sh
scripts/build/artifact-linked-flutter-consumer-test-android.sh
```

The release pipeline runs both, against the extracted package rather than the
checkout.

## Releasing

See `RELEASING.md` for the contributor rules. A React Native release needs a
maintainer at two points, merging the release PR and approving the npm
deployment. CI does the rest:

1. PRs merge to `main` with Conventional Commit titles, and release-please keeps
   a release PR, `chore(main): release react-native X.Y.Z`, open with the next
   version and changelog.
2. A maintainer merges the release PR when the release is ready. release-please
   tags the merge `react-native-vX.Y.Z`, creates a draft GitHub Release, and
   starts that tag's run of `.github/workflows/publish.yml`.
3. The run builds the package once and proves that exact file builds in test
   apps. Then its "Publish to npm" job waits.
4. A maintainer approves the `npm` deployment on the run's page (Review
   deployments).
5. CI publishes the tested file to npm with provenance, publishes the GitHub
   Release, and updates the documentation.

`scripts/release/identity/check.sh` checks the version lines on every PR.
Publishing React Native by hand is only for an emergency, through the runbook
below. Flutter is not on this pipeline and follows its own runbook.

### When a React Native release goes wrong

Every tag run ends in a job named "Result", whose summary records what happened
to npm, the provenance check, the GitHub Release, and the docs. The commands in
this section use `VERSION` and `R`. Replace `REPLACE_ME` with the release's
version, such as `1.4.2`, then list the release's runs, newest first. Every
block below checks its placeholders, and when one is left unedited it prints
what to replace and returns non-zero without running anything.

```bash
export VERSION=REPLACE_ME R=coproducthq/coproduct-client-sdks
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  gh run list -R "$R" -w publish.yml -e workflow_dispatch -L 100 \
    --json databaseId,headBranch,status,conclusion,createdAt \
    -q ".[] | select(.headBranch == \"react-native-v$VERSION\")"
else
  echo "Replace REPLACE_ME with the release version, such as 1.4.2"; false
fi
```

The Release Please run that started a Publish run links it in its summary. A run
a person starts on the tag runs only the checks and never publishes.

**A job failed.** Re-run only the failed jobs. Replace `REPLACE_ME` with the
run's ID, the number after `/runs/` in its link:

```bash
RUN_ID=REPLACE_ME
if [[ "$RUN_ID" =~ ^[0-9]+$ ]]; then
  gh run rerun "$RUN_ID" -R "$R" --failed
else
  echo "Replace REPLACE_ME with the run ID"; false
fi
```

The re-run reuses the run's sealed `react-native-package` artifact, so it
publishes the bytes the builds tested and never repacks. Before publishing, it
reads npm:

- npm already holds this version with the same bytes: it skips the publish and
  carries on with the provenance check, the Release, and the docs.
- npm holds this version with different bytes: it stops (see the bad-version
  runbook below).
- npm `latest` is newer than this version: it stops as stale (see the
  bad-version runbook below).

A re-run that reaches "Publish to npm" waits for approval again. A failed
"Release the docs" job re-runs the same way, and so does a provenance check that
failed with "was not visible with provenance in time", because npm was only slow
to show it. A build that failed before publishing, with the version absent from
npm, retitles the Release "react-native: vX.Y.Z (not published)", and the next
successful run restores the title. Done when the "Result" job passes.

The native libraries that "Pack react-native.tgz" reads are kept for one day. If
that job failed more than a day ago, start a fresh run as below instead.

A "Release the docs" job that failed because npm served a newer version as
`latest` before this one is expected. The newer release's docs win, and there
is nothing to fix.

**The run never started, or stopped before publishing.** Start a fresh Publish
run on the tag. The release App's runs for one tag queue behind each other, so
a fresh run waits while an older one is still live, for example one waiting on
approval. First list the tag's live runs:

```bash
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  gh run list -R "$R" -w publish.yml -e workflow_dispatch -L 100 --json databaseId,headBranch,status \
    -q ".[] | select(.headBranch == \"react-native-v$VERSION\" and .status != \"completed\") | .databaseId"
else
  echo "Export VERSION as in the first block of this section"; false
fi
```

Cancel each ID it prints, replacing `REPLACE_ME` with it, and rerun the list
until it prints nothing:

```bash
RUN_ID=REPLACE_ME
if [[ "$RUN_ID" =~ ^[0-9]+$ ]]; then
  gh run cancel "$RUN_ID" -R "$R"
else
  echo "Replace REPLACE_ME with the run ID"; false
fi
```

Then start the fresh run. The release App dispatches it, so it can still
release:

```bash
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  gh workflow run release-please.yml -R "$R" -f tag="react-native-v$VERSION"
else
  echo "Export VERSION as in the first block of this section"; false
fi
```

Done when that Release Please run's summary links a new Publish run. A dispatch
can succeed on GitHub's side and still report an error, which leaves a
duplicate Publish run queued behind the first. Cancel the duplicate, or reject
its `npm` deployment. If it runs anyway, it finds the version already on npm and
publishes nothing. It packs its own bytes, so it can stop with "npm already
holds a different package", which is expected here and needs no bad-version
work. A fresh run packs new bytes, so use it only for a version npm does not
have yet. For a version already on npm, re-run the failed jobs of the run that
published it.

**The approval expires.** A pending `npm` approval expires after 30 days, and
the run can't be re-run after that. Approve or reject it before then. An expired
run published nothing, so start a fresh run as above.

#### The bad-version runbook

A published version can never be replaced or reused. npm refuses a second
publish of the same version, even after an unpublish, so the only repair is a
newer version. Use this runbook when a published version is broken, or when a
run stops with an error that points here. Each case below needs `VERSION` and
`R` exported as in the first block of this section.

- **"npm already holds a different package"**: npm has this version with bytes
  this run did not test, for example from a hand publish. This run published
  nothing. Leave it alone, because re-running it stops the same way. Check
  whether the bytes on npm are a release you trust:
  ```bash
  if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    mkdir -p "$HOME/.coproduct-rn-npm-check" &&
      curl -fsSL "$(npm view "@coproduct/react-native-sdk@$VERSION" dist.tarball)" -o "$HOME/.coproduct-rn-npm-check/npm.tgz" &&
      shasum -a 256 "$HOME/.coproduct-rn-npm-check/npm.tgz" &&
      node scripts/release/react-native/check-pack.mjs "$HOME/.coproduct-rn-npm-check/npm.tgz" "$VERSION"
  else
    echo "Export VERSION as in the first block of this section"; false
  fi
  ```
  The bytes are acceptable only when the package check passes and the hash
  equals the `react-native.tgz.sha256` of a run whose builds all passed for this
  tag, such as the run used for a hand publish. A person decides whether they
  are, and whether to publish the Release. An agent runs the next command only
  with a person's explicit go-ahead. If they are acceptable, publish the draft
  Release with
  `gh release edit "react-native-v$VERSION" -R "$R" --draft=false --title "react-native: v$VERSION"`
  and update the docs as in step 8 of the emergency runbook. Otherwise treat it
  as a bad version.
- **"npm already has a release newer than"**: a later release overtook this one.
  Release PRs are cut from `main` in order, so the newer version already ships
  these changes, and there is nothing to publish. Mark the draft so it is not
  mistaken for a pending release. This edits a public page. A person decides
  it, and an agent runs it only with a person's explicit go-ahead:
  ```bash
  if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    gh release edit "react-native-v$VERSION" -R "$R" --title "react-native: v$VERSION (not published)"
  else
    echo "Export VERSION as in the first block of this section"; false
  fi
  ```
- **"published without provenance"**: this is expected only when someone re-ran
  a run after the version was published by hand, because a hand publish carries
  no provenance. Leave that run alone. In any other case, treat it as a bad
  version.
- **"provenance names ..., not the tag's ..." or "names no source commit"**: the
  version on npm is not proven to come from the tag. Treat it as a bad version.

For a bad version, replace both `REPLACE_ME` values (`BAD` is the broken
version, `FIXED` the release that replaces it), then work through the steps in
order:

```bash
export R=coproducthq/coproduct-client-sdks BAD=REPLACE_ME FIXED=REPLACE_ME
if [[ "$BAD" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$FIXED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "versions OK"
else
  echo "Replace both REPLACE_ME values with versions, such as 1.4.2"; false
fi
```

Done when it prints `versions OK`.

1. **Fix forward.** Merge the fix in a PR titled `fix: ...`. release-please
   moves the release PR to the next patch version. Merge it and approve the
   run's `npm` deployment as usual. Done when
   `npm view @coproduct/react-native-sdk dist-tags.latest` prints `FIXED`'s
   version.
2. **Deprecate the bad version.** This changes the public registry for every
   installer. A person decides it, the registry owner runs it, and an agent never
   runs it without a person's explicit go-ahead. Run it once the fix is on npm,
   adding `--otp=<code>` if npm asks for a one-time password. If npm prints a
   link instead, open it and confirm in the browser, which is where a security
   key is used. Keep the message neutral
   and name the fixed version.
   ```bash
   if [[ "$BAD" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$FIXED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     npm deprecate "@coproduct/react-native-sdk@$BAD" "Use $FIXED or later, which fixes an issue in $BAD"
   else
     echo "Export BAD and FIXED as above"; false
   fi
   ```
   Done when `npm view "@coproduct/react-native-sdk@$BAD" deprecated` prints
   the message.
3. **Annotate the GitHub Release.** This edits a public page. A person decides
   it, and an agent runs it only with a person's explicit go-ahead. Add a note
   above the bad version's notes:
   ```bash
   if [[ "$BAD" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$FIXED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     notes=$(mktemp) &&
       { printf '> Deprecated. Use %s or later.\n\n' "$FIXED"
         gh release view "react-native-v$BAD" -R "$R" --json body -q .body; } > "$notes" &&
       gh release edit "react-native-v$BAD" -R "$R" --notes-file "$notes"
   else
     echo "Export BAD and FIXED as above"; false
   fi
   ```
   Done when `gh release view "react-native-v$BAD" -R "$R"` shows the note.
4. **Check the docs.** The fixed release's run moves the documentation to the
   fixed version in its "Release the docs" job. Done when that job passed. If it
   failed, re-run the failed jobs of that run.

### React Native, by hand in an emergency

A person decides to use this runbook at all, and an agent follows it only with a
person's explicit go-ahead. Use it only when CI can't publish a release whose
build passed, for example when npm trusted publishing is broken. It publishes
the exact package the tag's Publish run built and tested, so nothing is packed
on your machine. Run each block from the repository root as one command. Each
starts by sourcing the release's environment file, so it works in a fresh
shell. You need `gh` and `npm` signed in to accounts that can publish
`@coproduct/react-native-sdk`. release-please already tags the merged release
PR, creates its draft Release, and labels the PR as released, so this runbook
does none of those.

1. **Set the environment and find the tag's run.** Replace `REPLACE_ME` with the
   release's version, such as `1.4.2`, and run:
   ```bash
   cat > "$HOME/.coproduct-rn-release.env" <<'EOF'
   export VERSION=REPLACE_ME
   export OUT="$HOME/.coproduct-rn-release"
   export R=coproducthq/coproduct-client-sdks
   EOF
   source "$HOME/.coproduct-rn-release.env"
   if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     echo "Replace REPLACE_ME with the release version, then rerun this block"; false
   else
     RUN=$(gh run list -R "$R" -w publish.yml -e workflow_dispatch -L 100 --json databaseId,headBranch \
       -q "[.[] | select(.headBranch == \"react-native-v$VERSION\")][0].databaseId // empty")
     if [ -z "$RUN" ]; then
       echo "No Publish run found for react-native-v$VERSION. Take the run ID from the Release Please run's summary"; false
     else
       echo "export RUN=$RUN" >> "$HOME/.coproduct-rn-release.env"
       if [ "$(gh run view "$RUN" -R "$R" --json headSha -q .headSha)" = "$(gh api "repos/$R/commits/react-native-v$VERSION" -q .sha)" ]; then
         echo "run $RUN OK"
       else
         echo "MISMATCH: run $RUN is not on the commit of react-native-v$VERSION"; false
       fi
     fi
   fi
   ```
   Done when it prints `run <ID> OK`. The newest run on the tag is not always
   the release's run, because anyone can start a checks-only run on the tag, and
   step 2 tells the two apart. If no run was found, or step 2 rules this one
   out, take the run ID from the link in the Release Please run's summary, add
   the line `export RUN=` followed by that ID to
   `$HOME/.coproduct-rn-release.env`, and go on to step 2.
2. **Check that the build passed.**
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   gh run view "$RUN" -R "$R" --json jobs -q '.jobs[] | "\(.status) \(.conclusion) \(.name)"'
   ```
   Done when every Native, Pack, iOS build, and Android build job reads
   `completed success`, and "Publish to npm" is either waiting for approval or
   reads `completed failure` and the block below allows going on. A run where
   "Publish to npm" is skipped or missing is a checks-only run, so go back to
   step 1 and use the run the Release Please summary links. Never publish from
   a run whose build failed.

   If "Publish to npm" failed, read why before going on. A run that stopped
   because npm already has a newer release (`newer than`) or already holds a
   different package for this version (`different package`) must not be
   published by hand: stop and follow the bad-version runbook instead. A run
   that stopped because the package carries another version
   (`but this release is`) must not be published either: stop and find out how
   the tag and the package came apart.
   The log also echoes each step's script, which contains these phrases, so
   the checks below match only the errors GitHub rendered. GitHub puts
   `##[error]` after the job, step, and timestamp that start each log line.
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   if ! log=$(gh run view "$RUN" -R "$R" --log-failed); then
     echo "Could not read the failed log. Open the failed job on the run's page and read it"; false
   elif [ -z "$log" ]; then
     echo "STOP: the failed log came back empty. Open the failed job on the run's page and read it"; false
   elif grep -E '##\[error\]npm already (has a release newer than|holds a different package)' <<< "$log"; then
     echo "STOP: npm already has this version or a newer one. Follow the bad-version runbook"; false
   elif grep -E '##\[error\]The package is version' <<< "$log"; then
     echo "STOP: the package is not this release's version. Do not publish it"; false
   else
     grep -E '##\[error\]|npm (error|ERR!)' <<< "$log" | tail -n 20
     echo "Read the errors above before going on"
   fi
   ```
   Go on only when the errors show npm failing to authenticate or to publish,
   for example because trusted publishing is broken. For any other failure,
   stop and find its cause.
3. **Stop CI from publishing.** Skip this step if "Publish to npm" already
   failed, because that run publishes nothing more. Otherwise cancel the run so
   CI can't publish alongside you. Rejecting the deployment on the run's page is
   optional, since cancelling is enough.
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   gh run cancel "$RUN" -R "$R"
   ```
   Then rerun `gh run view "$RUN" -R "$R" --json status -q .status` until it
   prints `completed`. Don't re-run this run later, because its provenance check
   would fail on the hand-published version.
4. **Download the tested package and check it.**
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   rm -rf "$OUT" && gh run download "$RUN" -R "$R" -n react-native-package -D "$OUT"
   (cd "$OUT" && shasum -a 256 -c react-native.tgz.sha256)
   node scripts/release/react-native/check-pack.mjs "$OUT/react-native.tgz" "$VERSION"
   ```
   Done when the hash reads `OK` and the package check passes.
5. **Publish that file.** A published version can never be reused. A person
   decides to publish, and an agent runs this block only with a person's
   explicit go-ahead. The block first asks npm whether it already has the
   version, and publishes only on a definite `E404`:
   - If npm has the version, the failed run did publish. The block stops, and
     you re-run that run's failed jobs instead.
   - If npm fails for any other reason, the block stops. Retry it, and never
     assume the version is absent.

   If npm asks for a one-time password, a person supplies it by adding
   `--otp=<code>` to `npm publish`. If npm prints a link instead, a person opens
   it and confirms in the browser, which is where a security key is used.
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     echo "Set VERSION in step 1 first"; false
   elif out=$(npm view "@coproduct/react-native-sdk@$VERSION" version 2>&1); then
     echo "STOP: npm answered for $VERSION (${out:-no output}). Do not publish"; false
   elif ! printf '%s\n' "$out" | grep -q 'E404'; then
     echo "UNCERTAIN: npm view failed without E404. Retry, and never assume the version is absent"; false
   else
     npm publish "$OUT/react-native.tgz" --access public
   fi
   ```
   Done when `npm publish` succeeds.
6. **Confirm npm serves that file.**
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   if [ "$(curl -sL "$(npm view "@coproduct/react-native-sdk@$VERSION" dist.tarball)" | shasum -a 256 | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$OUT/react-native.tgz.sha256")" ]; then
     echo MATCH
   else
     echo "MISMATCH: npm does not serve these bytes yet. Wait a minute and rerun. If it persists, stop and follow the bad-version runbook"; false
   fi
   ```
   Done when it prints `MATCH`.
7. **Publish the draft Release.** This makes the Release public. A person decides
   it, and an agent runs it only with a person's explicit go-ahead.
   ```bash
   source "$HOME/.coproduct-rn-release.env"
   if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     gh release edit "react-native-v$VERSION" -R "$R" --draft=false --title "react-native: v$VERSION"
   else
     echo "Set VERSION in step 1 first"; false
   fi
   ```
   Done when
   `gh release view "react-native-v$VERSION" -R "$R" --json isDraft -q .isDraft`
   prints `false`.
8. **Update the docs.** The run's "Release the docs" job does not run in a run
   that was cancelled or whose publish failed. The documentation update runs from
   a private repository, so a maintainer with access there starts it for
   `react-native` and the version, once
   `npm view @coproduct/react-native-sdk dist-tags.latest` prints it. If nobody
   does, the docs stay on the previous version until a later release, whose own
   "Release the docs" job moves them to that release.

A package published this way carries no npm provenance, because provenance comes
only from a CI publish.

### Flutter

The Flutter SDK ships prebuilt native libraries inside the pub.dev package, so an
integrating developer needs no Rust toolchain. Producing that package is what
this section covers. Scripts live under `scripts/release/flutter/`; see its
README for the layout.

#### Prerequisites

| | |
|---|---|
| `llvm-tools` for the pinned toolchain | `rustup component add llvm-tools --toolchain 1.95.0` — without it the symbol gate has no tool |
| `cargo-ndk` 4.1.2 | Android cross-compilation needs the NDK linker |
| Android NDK 27.1.12297006 | asserted from its own `source.properties`, not the directory name |
| Xcode 26.5, Rust 1.95.0, FRB codegen 2.12.0 | asserted before anything is built |
| An iPhone simulator, and an Android Virtual Device (`$ANDROID_HOME/emulator/emulator -list-avds` lists one) | step 2 boots them, and the acceptance gates neither boot nor provision a device |
| A pub.dev account with rights to publish `coproduct` | needed only at step 6, but it is the step where a first-time publisher discovers they lack them |
| `gh` signed in (`gh auth status`) | steps 4, 7, and 8 use it |
| Admin rights on the repository, or an admin on hand | step 7 pauses the tag ruleset |
| A checkout where `main` is not checked out in another worktree | steps 3 and 4 switch to `main` |

#### The release, end to end

Every command runs from the repository root, in this order. Steps 0, 2, and 3
write their settings to one environment file, and every later block starts by
sourcing it. Run each block as one command, so the release works the same in
one terminal or in a tool that starts a fresh shell per command.

**0. Set the environment.** Name scratch paths that do not exist yet: the
scripts create and mark their own space and refuse a directory they did not
create, because staging deletes and rewrites the path it is given. Reusing paths
from a previous run is fine, because they carry the marker. Adjust the Android
and Java paths to your machine. Step 1 confirms each one.

```bash
cat > "$HOME/.coproduct-release.env" <<'EOF'
export COPRODUCT_RELEASE_ROOT="$HOME/.coproduct-release"
export COPRODUCT_RELEASE_OUT="$COPRODUCT_RELEASE_ROOT/out"
export COPRODUCT_RELEASE_STAGE="$COPRODUCT_RELEASE_ROOT/stage/pkg"
export COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_RELEASE_ROOT/archive"
export COPRODUCT_CONSUMER_DIR="$COPRODUCT_RELEASE_ROOT/consumer"
export COPRODUCT_RELEASE_LOG="$COPRODUCT_RELEASE_ROOT.log"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.1.12297006"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
EOF
source "$HOME/.coproduct-release.env"
```

**1. Check the toolchains.** Every version the release pins, in one second,
rather than discovering a missing one part-way through a half-hour run:

```bash
source "$HOME/.coproduct-release.env"
scripts/release/flutter/preflight.sh
```

Done when the last line is `COPRODUCT_FLUTTER_PREFLIGHT_STATUS pass=true`. Each
failure names the command that fixes it. `llvm-tools` is the one worth
front-loading: it is a separate `rustup` component, and the first thing that
needs it is the symbol check, which runs only after every architecture has
finished compiling.

**2. Boot one iOS simulator and one Android emulator.** The gates consume an
already-booted device and neither boot nor provision one.

```bash
source "$HOME/.coproduct-release.env"
xcrun simctl list devices booted | grep -q Booted || xcrun simctl boot "$(
  xcrun simctl list devices available | grep iPhone | grep -oE '[0-9A-F-]{36}' | head -1)"
IOS_DEVICE="$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)"
xcrun simctl bootstatus "$IOS_DEVICE" -b

adb devices | grep -q '^emulator-' || nohup "$ANDROID_HOME/emulator/emulator" \
  -avd "$("$ANDROID_HOME/emulator/emulator" -list-avds | head -1)" \
  -no-snapshot-load >/dev/null 2>&1 &
adb wait-for-device shell 'while [ -z "$(getprop sys.boot_completed)" ]; do sleep 2; done'
ANDROID_DEVICE="$(adb devices | awk '/^emulator-.*device$/{print $1; exit}')"

echo "export COPRODUCT_ACCEPTANCE_IOS_DEVICE=$IOS_DEVICE" >> "$HOME/.coproduct-release.env"
echo "export COPRODUCT_ACCEPTANCE_ANDROID_DEVICE=$ANDROID_DEVICE" >> "$HOME/.coproduct-release.env"
echo "ios=$IOS_DEVICE android=$ANDROID_DEVICE"
```

Done when the last line prints both ids. A missing one fails at its guard
rather than part-way through a long run.

**3. Prepare the version.** Before this step, the CHANGELOG's first heading must
be `## Unreleased`. `prepare_release.dart` moves the pubspec version,
the SDK version constant and its derived `User-Agent`, the README install
example, the podspec version, and the CHANGELOG together, then audits that they
agree. The podspec is the costly one to get wrong: it is externally visible in
every consumer's `Podfile.lock`, where a published version can never be
replaced. Add an
`## Unreleased` heading to the CHANGELOG as you develop; this promotes it and
refuses to run without it.

Set the version once and use it for both preparation and the tag, so the two
cannot drift apart. Prepare it on a release branch cut from an up-to-date
`main`, so the CHANGELOG it promotes is current. Replace `1.2.0` with the
version being released:

```bash
cat >> "$HOME/.coproduct-release.env" <<EOF
export COPRODUCT_RELEASE_VERSION=1.2.0
export COPRODUCT_RELEASE_DATE=$(date +%F)
EOF
source "$HOME/.coproduct-release.env"

git switch main && git pull --ff-only
git switch -c "release/flutter-$COPRODUCT_RELEASE_VERSION"

scripts/build/with-fvm-toolchain.sh 3.44.0 -- bash -c 'cd scripts/release/flutter && dart pub get \
  && dart run bin/prepare_release.dart \
       --version "$COPRODUCT_RELEASE_VERSION" --date "$COPRODUCT_RELEASE_DATE"'
```

The date defaults to today. To change it, reset the CHANGELOG heading to
`## Unreleased`, edit the date in the environment file, and rerun this step.

**If the CHANGELOG already carries a dated heading** for a version that was
prepared but never published, this refuses to run: it accepts only
`## Unreleased` or the exact heading it would write. Reset the first line to
`## Unreleased` and rerun, which is also what puts the real publication date on
a release that slipped.

On a write failure it rolls back. If a restore write itself fails it names the
files it could not restore and says the rollback was incomplete — reset those
with `git checkout` before retrying.

A dated heading is also what the archive gate expects. Left at `## Unreleased`,
pub emits a second warning and the gate fails, because it allows exactly one.

**4. Merge the version through a PR, then build from `main`.** The pipeline
builds from one identified commit: staging refuses a dirty tree, and refuses
binaries whose build stamp names a commit other than `HEAD`. Commit the changes
step 3 made and open a PR titled with the release:

```bash
source "$HOME/.coproduct-release.env"
git commit -am "chore(flutter): release $COPRODUCT_RELEASE_VERSION"
git push -u origin HEAD
gh pr create --title "chore(flutter): release $COPRODUCT_RELEASE_VERSION" \
  --body "Moves the Flutter SDK's version lines to $COPRODUCT_RELEASE_VERSION."
gh pr checks --watch
```

If `gh pr checks` reports no checks, the workflow has not registered yet, so wait
a few seconds and run it again. A tool that cannot wait on a long command runs
`gh pr checks` without `--watch` until every check reports. Merge when every
check passes. Merges squash, and the squash
creates a new commit, so run the pipeline only after switching to the merged
`main`:

```bash
source "$HOME/.coproduct-release.env"
gh pr merge --squash --delete-branch
git switch main && git pull --ff-only
```

A pipeline run on the branch would seal a package whose `PROVENANCE.json` names
a commit that the squash merge leaves off `main`.

**Publish only from the merged `main`.** The `PROVENANCE.json` of an immutable
release must name a commit anyone can fetch.

**5. Run the pipeline.** Expect roughly 20-30 minutes on a healthy machine, most
of it the gate matrix building both platforms on two Flutter toolchains.

```bash
source "$HOME/.coproduct-release.env"
scripts/release/flutter/measure.sh 2>&1 | tee "$COPRODUCT_RELEASE_ROOT/measure.out"
```

Done when the output ends with `COPRODUCT_FLUTTER_MEASURE_STATUS pass=true`. A
tool that cannot hold a command open for half an hour starts it detached, with
`nohup scripts/release/flutter/measure.sh > "$COPRODUCT_RELEASE_ROOT/measure.out" 2>&1 &`,
and polls `tail -n 3 "$COPRODUCT_RELEASE_ROOT/measure.out"` until it shows that
line or `ERROR:`.

`COPRODUCT_ACCEPTANCE_TIMEOUT_MINUTES` overrides the acceptance budget, which
spans the Gradle build as well as the device run. The default is 8. The no-Rust
gate builds with an empty Gradle cache every time, so if a cold build on a
healthy machine turns out not to fit, raise the override, record what the build
actually took, and change the default from that measurement rather than from a
guess.

**It changes your working tree and your DerivedData.** The run regenerates the
FRB bindings and runs `cargo fmt --all` in place, then aborts if that moved
anything — leaving you with modified tracked files to `git checkout .` before
retrying. It also deletes `~/Library/Developer/Xcode/DerivedData/Runner-*`,
which is every Flutter app's DerivedData on the machine, not only this one.

It stops at the first failure and prints the full log to `$COPRODUCT_RELEASE_LOG`.
Fix a failure on a branch, through a PR with a Conventional Commit title such as
`style(flutter): …` or `fix(flutter): …`, then pull the merged `main` and run the
pipeline again from the start. The pipeline's first stage runs the package's
`dart format`, `flutter analyze`, and `flutter test` with the pinned toolchain,
so running those first saves a run that fails a few minutes in:

```bash
(cd sdks/flutter/coproduct && ../../../scripts/build/with-fvm-toolchain.sh 3.44.0 -- \
  bash -c 'flutter pub get && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test')
```

Each stage emits a status line, so `grep 'STATUS pass=' "$COPRODUCT_RELEASE_LOG"`
shows how far it got.

| Stage | Script | Status line |
|---|---|---|
| Codegen pin, clean checkout, zero diff | `release.sh` | — |
| The SDK's own analyze and tests | `release.sh` | `COPRODUCT_FLUTTER_SDK_TESTS_STATUS` |
| The release tooling's own tests | `release.sh` | `COPRODUCT_RELEASE_TOOLING_TESTS_STATUS` |
| Version coherence across all four files | `bin/check_identity.dart` | `COPRODUCT_FLUTTER_IDENTITY_STATUS` |
| License audit | `bin/license_audit.dart` | `COPRODUCT_LICENSE_STATUS` |
| Build six architectures | `stages/build-binaries.sh` | `COPRODUCT_FLUTTER_RELEASE_BUILD_STATUS` |
| Stage the package | `stages/stage-package.sh` | `COPRODUCT_FLUTTER_RELEASE_STAGE_STATUS` |
| Seal the publishable set | `stages/seal-package.sh` | — |
| Archive membership and size | `bin/check_archive.dart` | `COPRODUCT_FLUTTER_ARCHIVE_STATUS` |
| Extract the archive | `stages/extract-archive.sh` | `COPRODUCT_FLUTTER_EXTRACT_STATUS` |
| Consumer from the archive | `stages/consumer-from-archive.sh` | `COPRODUCT_FLUTTER_CONSUMER_FROM_ARCHIVE_STATUS` |
| Both platforms, both toolchains | `gates/gate-suite.sh` | `COPRODUCT_FLUTTER_GATE_SUITE_STATUS` |
| Prove the gates fail | `gates/mutation-gates.sh` | `COPRODUCT_FLUTTER_MUTATION_STATUS` |
| Re-verify the seal | `release.sh` | `COPRODUCT_FLUTTER_RELEASE_STATUS` |
| The whole run, timed | `measure.sh` | `COPRODUCT_FLUTTER_MEASURE_STATUS` |

**6. Publish.** Only through the wrapper:

```bash
source "$HOME/.coproduct-release.env"
git fetch -q origin && git merge-base --is-ancestor HEAD origin/main && echo "HEAD is on main"
scripts/release/flutter/publish.sh
```

**Never run `dart pub publish` yourself.** Every gate validates the staging
directory, but the obvious place to run a publish from is the source package
directory — and it publishes cleanly. The native binaries there are gitignored
build output, so pub omits them and offers a ~91 KB archive with no
`CoproductFFI.xcframework` and no `jniLibs`, carrying only the same single
warning the real release carries. pub.dev accepts it, every consumer fails at
load. A published version can never be replaced. Within seven days it can be
retracted to stop new resolutions. Retraction does not delete it, and existing
lockfiles keep using it.

The wrapper re-verifies the seal (`COPRODUCT_FLUTTER_SEAL_VERIFY_STATUS
pass=true`), changes into the staged package, and publishes it. pub asks for a
y/N confirmation, and `publish.sh --force` answers it for a tool that cannot. A
first publication from a machine opens a browser sign-in that only a person can
complete. Done when pub reports the upload succeeded.

**Authentication.** If you have never published from this machine, pub opens a
browser for a Google sign-in and stores the result in
`~/Library/Application Support/dart/pub-credentials.json`; `preflight.sh`
reports whether that file exists. Signing in is not the same as being allowed
to publish this package: for a first publication the package name must be
available on pub.dev, and for later ones your account must be an uploader.
Confirm both before starting a run, because neither is visible until the moment
you publish.

**7. Tag, only after pub.dev accepts.** A repository ruleset lets only the
release automation create `*-v*` tags, so a person's tag push is rejected. An
admin sets the ruleset to evaluate for the push and back to active straight
after:

```bash
source "$HOME/.coproduct-release.env"
R=coproducthq/coproduct-client-sdks
gh api -X PUT "repos/$R/rulesets/25455144" -f enforcement=evaluate
git tag -a "flutter-v$COPRODUCT_RELEASE_VERSION" \
  -m "Flutter SDK $COPRODUCT_RELEASE_VERSION" \
  && git push origin "flutter-v$COPRODUCT_RELEASE_VERSION"
gh api -X PUT "repos/$R/rulesets/25455144" -f enforcement=active
gh api "repos/$R/rulesets/25455144" -q .enforcement   # must print active
```

If any command between the two `PUT`s fails, still run the `enforcement=active`
`PUT` and the check before stopping, so the tags stay protected.

If the push is rejected, delete the local tag with
`git tag -d "flutter-v$COPRODUCT_RELEASE_VERSION"` before retrying.

**8. Publish the GitHub Release.** Developers read releases, not tags, and in a
repository with several SDKs the title names the SDK. Use this version's changelog entry as the notes:

```bash
source "$HOME/.coproduct-release.env"
awk -v v="## $COPRODUCT_RELEASE_VERSION " \
  'index($0, v) == 1 {on = 1; next} on && /^## / {exit} on' \
  sdks/flutter/coproduct/CHANGELOG.md > "$COPRODUCT_RELEASE_ROOT/notes.md"
test -s "$COPRODUCT_RELEASE_ROOT/notes.md" || echo "no changelog entry for this version"
gh release create "flutter-v$COPRODUCT_RELEASE_VERSION" \
  --title "flutter: v$COPRODUCT_RELEASE_VERSION" \
  --notes-file "$COPRODUCT_RELEASE_ROOT/notes.md" --verify-tag
```

#### iOS and Android version identity

The React Native and Flutter pipelines check version identity automatically.
For iOS and Android, confirm by hand before publishing, as Release Identity in
`AGENTS.md` describes:

- [ ] The `User-Agent` version (`coproduct-<platform>/<version>`) equals the
      version being published, and carries no `-dev` suffix.
- [ ] The published package or git tag matches that version.
- [ ] The built or packaged artifact version matches that version.
- [ ] The install instructions in the platform README point at the real
      published repo and version, and read as installable now.

#### Tag names

Each SDK versions independently, so every tag names its SDK:
`<sdk>-v<version>`, where `<sdk>` is `flutter`, `android`, `react-native`, or
`ios`, as in `flutter-v1.0.0`. This is also the default that release-please uses
for a repository with several components. A GitHub Release is titled the way
release-please titles it, `<sdk>: v<version>`, such as `flutter: v1.1.0`.

Swift Package Manager is the exception. It reads only a `Package.swift` at a
repository's root and only plain version tags, so the iOS SDK is distributed
from its own repository with plain version tags, such as `1.0.0`. This
repository still gets an
`ios-v<version>` tag on the commit the release was built from.

#### Who does what

| Step | Who |
|---|---|
| 0, 1, 2, 5: the environment, the toolchain check, the devices, the pipeline | automated once started |
| Before the first publication: archive a clean consumer in Xcode, generate the privacy report in the Organizer, and confirm it lists the `UserDefaults` declaration from the `coproduct_privacy` bundle | human: the pipeline checks the manifest inside the release app, but Xcode generates the report only from the Organizer |
| Before the first publication: the session check on a physical iPhone, below | human: no simulator or emulator can be put in the state before the first unlock after boot |
| 3 and 4: preparing the version and merging its PR | human |
| 6: `publish.sh` | human, and the only supported way to publish |
| Transferring the package to the verified publisher | human, and it cannot be undone |
| 7 and 8: the tag and the GitHub Release | human, and the ruleset change needs an admin |

A row marked human needs a person to run it, or to approve an agent running it.

Dart cannot publish a new package directly to a verified publisher, which is why
the first publication and the transfer are both manual.

#### The session check on a physical iPhone

Before the user first unlocks an iPhone after a restart, the file the session
record lives in cannot be read, and `UserDefaults` reports it as empty. The SDK
detects that and leaves `first_seen_at` and `session_count` unset for the
launch rather than restarting the count over the real record. No simulator can
be put in that state, so it is checked on a device before the first
publication. An app runs before the first unlock only if something launches it
in the background, and Xcode cannot launch an app on a locked device, so the
check needs a test app with a background mode. The example app has none.

1. Build a signed test app that depends on the SDK and can be launched in the
   background by an exact, repeatable trigger, such as a specific silent push
   or background task. Write the trigger down.
2. Give it a `FlutterError.onError` handler that logs
   `details.exception.runtimeType` and, for `SessionAttributesUnavailable`, its
   `cause`. The default handler is not enough: it prints only the first error
   in full and does not reliably name the exception's type.
3. Install and open the app once, then terminate it. Download its container
   from Xcode's Devices window and record `firstSeenAt` and `sessionCount` from
   the `app.coproduct.flutter.session` entry in
   `Library/Preferences/<bundle id>.plist`.
4. Restart the phone without unlocking it and trigger the background launch.
   Confirm that the process ran and that it reported
   `SessionAttributesUnavailable` with the `storageFailure` cause.
5. Unlock, terminate that process, and open the app. Download the container
   again and confirm `firstSeenAt` equals the recorded value and `sessionCount`
   is the recorded value plus one.

Android has the equivalent only for an app that opts into direct boot, where
the preferences file cannot be opened before the first unlock. The same check
applies to such an app.

#### When a gate fails

The gates are built so a failure names its own cause; read the status line that
is missing rather than the last line of output. A failing gate-matrix step
prints its last five lines and the path to its full log, one file per step under
`/tmp/gate-suite-*.log`. Three failures are procedural rather than defects:

- **"the release must start from a clean checkout"**, **"the binaries were built
  at X but HEAD is Y"**, or, at publish, **"this stage was built from X but HEAD
  is now Y"** — fix it on a branch, merge it through a PR, then
  `git switch main && git pull --ff-only` and rerun. The pipeline describes
  exactly one commit, and it must be the one on `main`.
- **A gate that is slow or hangs** — check the machine before the code:
  `uptime`, `sysctl vm.swapusage`, and whether a build that once took seconds now
  takes minutes. A cold Gradle cache and a thrashing machine both look like a
  hung gate, and neither is a defect in the package.
- **"the device clock moved Ns against the host during the run"**: an Android
  acceptance run stopped because the emulator's clock drifted while it ran,
  which happens when the host is overloaded. Free memory, cold-boot the emulator
  with `"$ANDROID_HOME/emulator/emulator" -avd <name> -no-snapshot-load`, and
  check that its offset holds steady for a minute or two by comparing
  `adb shell date +%s` with `date +%s`, then rerun. Do not raise
  `kClockStepSeconds`: a clock that moves during a run is exactly when the
  `first_seen_at` bounds stop proving anything.

#### Toolchains and the compatibility floor

FVM is for maintainers. Adopters never need it. Release and floor-verification
commands run through
`scripts/build/with-fvm-toolchain.sh <flutter-version> -- <command>`, which pins
the exact Flutter/Dart onto `PATH` for every nested process, verifies both
resolve inside the selected SDK, and purges the native config that would pin a
global SDK. It never runs `fvm use`, so it does not mutate the repository.

The floor is a tested matrix, never a claim from dependency metadata. Before
lowering the published `environment` constraints, the full matrix must pass on
both the candidate and the primary toolchain. `gates/gate-suite.sh` runs it.

Clean the artifact consumer's build state before switching toolchains. Flutter
versions ship different `Flutter.framework` headers, so a build reusing output
from another version fails with:

```
Swift Compiler Error (Xcode): File '.../Flutter.framework/Headers/FlutterPlugin.h'
has been modified since the precompiled header ... was built
```

That means the precompiled state is stale, which after a toolchain switch is
almost always the build directory, not an incompatibility. Reading it the other
way sends you hunting a bug that does not exist, or raising the published floor
to make a stale artifact go away. Clean and retry first; a recurrence from a
clean build is a real failure.

`flutter pub publish --dry-run` exits nonzero on the expected
flutter_rust_bridge pin warning; the gate accepts that and fails only on errors
or unexpected warnings. `pubspec.lock` is not committed, so record the resolved
dependency and native toolchain versions as release evidence.

#### What CI would require

This pipeline runs on one developer's machine. Nothing about it is hostile to
CI, but it is not a workflow file away either. The list below is the scope.

Constraints that are already true, and that any design has to accept:

- **The no-Rust gate needs a runner that never had a Rust toolchain**, or the
  deliberately constructed fresh `HOME` and sanitized `PATH` the gate builds.
- **iOS acceptance needs an arm64 macOS runner** for the simulator.
- **Android acceptance needs a Linux runner.** GitHub documents Android hardware
  acceleration on its Linux runners and states nested virtualization is
  unsupported on macOS runners, so one macOS runner cannot reliably host both.

Prerequisites a CI design needs:

- **Splitting the pipeline across runners.** `release.sh` runs every stage in
  one process and shares the staging directory by path. Putting iOS on macOS and
  Android on Linux means decomposing it into jobs that pass the staged package
  and its build stamp between them as artifacts, and re-verifying the stamp on
  arrival. That is a structural change, not configuration.
- **Portability for the Linux half.** `stages/seal-package.sh` uses BSD
  `stat -f` and `gates/mutation-gates.sh` uses BSD `sed -i ''`. Both fail on a
  GNU userland, so the seal, which establishes what the package *is*, does not run on
  Linux.
- **Non-interactive publishing.** `publish.sh --force` skips pub's confirmation,
  but publishing still needs stored pub.dev credentials, and nothing in the
  repository reads a pub token or handles credentials as a secret.
- **Device provisioning.** Both acceptance scripts consume an already-booted
  device id and neither boot nor provision one. The runbook's boot commands are
  written for a human at a terminal, not as workflow steps.

Two properties are worth preserving in any CI design, because they are what the
gates are for. The pipeline must still build from exactly one identified commit,
and the mutation gates must still run — a CI job that skips them proves the
package was built, not that anything would have caught it if it were wrong.

## Recovering local disk space

Every gitignored directory is a regenerable cache or build output. None of these contain durable work.

| Directory | Recovery command | Rough rebuild time |
|---|---|---|
| `target/` (Cargo cache, can grow to 10+ GB) | `cargo clean` | 3-5 min full workspace rebuild |
| `**/build/` (Gradle, Flutter, Xcode build output) | `./gradlew clean` or `flutter clean` or remove manually | 1-5 min per surface |
| `**/.gradle/`, `**/.kotlin/`, `**/.cxx/` (Gradle, Kotlin, NDK caches) | automatic on next Gradle command | seconds |
| `**/.dart_tool/` (Dart analyzer and build cache) | automatic on `flutter pub get` | seconds |
| `**/node_modules/` (npm / yarn install output) | `rm -rf node_modules && yarn install` | 30s-2 min per dir |
| `**/Pods/` (CocoaPods install output) | `cd <ios dir> && pod install` | 1-3 min per dir |
| `sdks/ios/CoproductFFI.xcframework/` (Rust to iOS binary) | `scripts/package/ios-build-xcframework.sh` | ~1-2 min |
| `sdks/react-native/coproduct/ios/CoproductFFI.xcframework/` (Rust to RN iOS binary) | `scripts/package/rn-build-native.sh ios` | ~1-2 min |
| `sdks/react-native/coproduct/android/src/main/jniLibs/` (Rust to RN Android binaries) | `scripts/package/rn-build-native.sh android` | ~2-4 min |
| `sdks/android/src/main/jniLibs/` (Rust to native Android binaries) | `scripts/package/android-build-jnilibs.sh` | ~2-4 min |
| `build/ios-spm/` (SwiftPM fixture build output) | `scripts/package/ios-spm-fixture.sh` | ~30s |

Worst-case full-cold rebuild after deleting all 25+ GB is roughly 15-25 minutes assuming dependency downloads succeed.

**Do not delete tracked lockfiles** (`Cargo.lock`, `Podfile.lock`, `yarn.lock`, `package-lock.json`, `Gemfile.lock`). They pin exact dependency versions for reproducible builds. The first-party Dart `pubspec.lock` files (the SDK package, its example, `consumer-tests`, and the `scripts/*` tool packages) are regenerable and gitignored, so deleting them is harmless; `flutter pub get` or `dart pub get` recreates them.
