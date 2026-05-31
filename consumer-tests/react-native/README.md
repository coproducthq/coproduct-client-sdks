# consumer-tests/react-native

Fresh React Native app installing `react-native-coproduct` as a packaged tarball, not as a workspace source-link. Exists to catch issues only visible at publish/install time (autolinking, peer-deps, podspec quirks) that `sdks/react-native/coproduct/example/` cannot surface because it source-links the SDK.

## Toolchain

JDK 17, Gradle 8.14, AGP 8.12.0, Node 20, CocoaPods, Xcode 26+.

## Run

```bash
npm run setup         # packs the SDK at ../../sdks/react-native/coproduct and installs
cd ios && pod install && cd ..
npm run android       # or: npm run ios
```

The Podfile carries a `post_install` hook that pins `fmt`'s `CLANG_CXX_LANGUAGE_STANDARD = c++17`, working around an upstream RN 0.82 + Xcode 26 consteval failure in `fmt::basic_format_string`. Not a Coproduct bug; do not remove.

## Verifying green

The demo screen prints five status lines. All must be true:

- SDK ready: yes
- Host callbacks: yes
- Loaded from cache: no (first run) / yes (subsequent runs)
- getBool: false
- Observer fired: yes
