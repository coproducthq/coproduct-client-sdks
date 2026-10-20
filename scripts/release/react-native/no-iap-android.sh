#!/usr/bin/env bash
# Proves the paywall packages are optional on Android. An app without
# react-native-iap and react-native-nitro-modules imports the SDK's paywall
# entry point, builds a release APK against the packed SDK, and gets no
# BILLING permission. The import matters: without it Metro never bundles the
# paywall code, and a loading import of react-native-iap there would go unseen
#   scripts/release/react-native/no-iap-android.sh <tgz>
set -euo pipefail
tgz=${1:?usage: no-iap-android.sh <tgz>}
root=$(git rev-parse --show-toplevel)
src="$root/consumer-tests/react-native"
# Same depth as the original, because App.tsx imports ../../tests
app="$root/consumer-tests/react-native-no-iap.tmp"
rm -rf "$app"
mkdir -p "$app"
(cd "$src" && git ls-files -z | xargs -0 -I{} rsync -R "{}" "$app/")
node -e '
  const fs = require("fs"); const dir = process.argv[1];
  const p = dir + "/package.json"; const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
  delete pkg.dependencies["react-native-iap"]; delete pkg.dependencies["react-native-nitro-modules"];
  fs.writeFileSync(p, JSON.stringify(pkg, null, 2));
  const a = dir + "/App.tsx";
  fs.writeFileSync(a, "import \x27@coproduct/react-native-sdk/paywall\x27;\n" + fs.readFileSync(a, "utf8"));
' "$app"
"$root/scripts/release/react-native/install-tgz.sh" "$app" "$tgz"
if [ -d "$app/node_modules/react-native-iap" ] || [ -d "$app/node_modules/react-native-nitro-modules" ]; then
  echo "The paywall packages were installed anyway, so this build proves nothing. Check the SDK's peerDependenciesMeta." >&2
  exit 1
fi
(cd "$app/android" && ./gradlew :app:assembleRelease)
"$root/scripts/release/react-native/billing.sh" "$app" absent
echo "COPRODUCT_RN_NO_IAP_ANDROID_STATUS pass=true"
