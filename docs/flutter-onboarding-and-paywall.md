# Flutter: onboarding and paywall

The integration guide ships with the package as
[`sdks/flutter/coproduct/doc/onboarding_and_paywall.md`](../sdks/flutter/coproduct/doc/onboarding_and_paywall.md),
so it is also readable on pub.dev.

## Keeping the bundled platform scripts in sync

Both features ship a compiled `assets/*-platform-script.js`, copied from the
platform's onboarding and paywall script packages. It is not rebuilt
automatically. After changing either package, re-run the matching sync script
before relying on the new behavior on a device:

```bash
sdks/flutter/coproduct/scripts/sync-onboarding-platform-script.sh
sdks/flutter/coproduct/scripts/sync-paywall-platform-script.sh
```

A stale bundle fails silently: the feature it is missing never triggers, with
no error.
