# consumer-tests/

Fresh third-party apps that install each platform SDK as a **packaged release artifact** (not a workspace source-link) and exercise it end-to-end. The role of these apps is to catch the class of bugs that only appears at publish / install / autolink time — peer-deps, podspec quirks, Gradle plugin compatibility, `package.json` `files` glob omissions, podfile `post_install` requirements — which the source-linked apps under `examples/` and `sdks/<platform>/coproduct/example/` cannot surface.

This is the release-verification gate, not a developer playground.

## Convention

```
consumer-tests/
  ios/             — Xcode project consuming Coproduct via SPM local file: dep
  android/         — Gradle project consuming Coproduct via mavenLocal / release artifact
  react-native/    — RN app installing react-native-coproduct from a local .tgz
  flutter/         — Flutter app consuming coproduct via path: against sdks/flutter/coproduct
```

See each subdirectory's `README.md` for that platform's exact run flow and what the green-state demo screen must print.

## What `examples/` is for instead

Apps under the top-level `examples/` directory (and the framework-nested `sdks/react-native/coproduct/example/`, `sdks/flutter/coproduct/example/` that `bob` and `flutter create --template=plugin` generate) are **source-linked** — they pull the SDK as workspace code and let SDK authors iterate against a sample app in seconds. They demonstrate usage and run fast; they do not test the publish/install pipeline.
