# consumer-tests/react-native

Fresh React Native app installing `@coproduct/react-native-sdk` as a packaged tarball, not as a workspace source-link. Exists to catch issues only visible at publish/install time (autolinking, peer-deps, podspec quirks) that `sdks/react-native/coproduct/example/` cannot surface because it source-links the SDK.

## Toolchain

JDK 17, Gradle 8.14, AGP 8.12.0, Node 20, CocoaPods, Xcode 26+.

## Run

```bash
npm run setup         # packs the SDK at ../../sdks/react-native/coproduct and installs
cd ios && pod install && cd ..
npm run android       # or: npm run ios
```

The app runs React Native 0.88. Under Xcode 26, React Native 0.82 fails to compile `fmt` once the SDK's `react-native-nitro-modules` peer is installed, because Swift's C++ interop builds it as C++20, and a Podfile override of the `fmt` pod's language standard does not reach that import.

## Verifying green

The demo screen prints five status lines. All must be true:

- SDK ready: yes
- Host callbacks: yes
- Loaded from cache: no (first run) / yes (subsequent runs)
- getBool: false
- Observer fired: yes
