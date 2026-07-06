# consumer-tests/android

Fresh Android app that consumes the native Android SDK through `mavenLocal`, not through a source-linked Gradle project dependency.

## Verify locally

From `coproduct-client-sdks/`:

```bash
cd examples/android-demo
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=$HOME/Library/Android/sdk \
ANDROID_SDK_ROOT=$HOME/Library/Android/sdk \
ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006 \
./gradlew :coproduct-android:publishToMavenLocal

cd ../../consumer-tests/android
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=$HOME/Library/Android/sdk \
ANDROID_SDK_ROOT=$HOME/Library/Android/sdk \
ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006 \
./gradlew :app:installRelease
```

The consumer app depends on `app.coproduct:coproduct-android:0.0.1-SNAPSHOT`. The publish step above is intentionally separate so the app exercises Maven metadata and artifact consumption rather than the local SDK source tree.

The release build type uses the debug signing config so this test fixture can install a minified release APK on an emulator. This is only for consumer-test verification; it is not a production signing model.

After install, launch and verify:

```bash
adb shell am force-stop app.coproduct.consumer.android
adb shell am start -n app.coproduct.consumer.android/.MainActivity
adb logcat -d -s CoproductConsumer:I '*:S'
```

Green when logcat includes:

```text
COPRODUCT_ANDROID_CONSUMER_STATUS ready=true hostCallbacks=true getBool=false observerRegistered=true
```
