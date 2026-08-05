#!/usr/bin/env bash
# build/with-fvm-toolchain.sh <flutter-version> -- <command...>
#
# Runs a command with an exact FVM-managed Flutter toolchain forced onto PATH for
# the process and every nested shell and Dart subprocess, so a nested bare
# `flutter`/`dart` cannot resolve a globally installed SDK. FVM is maintainer-only
# release infrastructure that adopters never need. This never runs `fvm use`, which
# would mutate the repo.
set -euo pipefail

if [[ "${2:-}" != "--" || -z "${1:-}" ]]; then
  echo "usage: with-fvm-toolchain.sh <flutter-version> -- <command...>" >&2
  exit 2
fi
VERSION="$1"; shift 2
if [[ $# -eq 0 ]]; then
  echo "with-fvm-toolchain: no command given after --" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDK_DIR="$HOME/fvm/versions/$VERSION"

# Install the exact version only if it is not already cached, so a cached version
# is used hermetically without a network fetch
if [[ ! -x "$SDK_DIR/bin/flutter" || ! -x "$SDK_DIR/bin/dart" ]]; then
  fvm install "$VERSION" >/dev/null
fi
if [[ ! -x "$SDK_DIR/bin/flutter" || ! -x "$SDK_DIR/bin/dart" ]]; then
  echo "with-fvm-toolchain: FVM SDK $VERSION not found at $SDK_DIR/bin" >&2
  exit 1
fi

export PATH="$SDK_DIR/bin:$PATH"

# Enforcement: both must resolve INSIDE the selected SDK, not a global one
RESOLVED_FLUTTER="$(command -v flutter)"
RESOLVED_DART="$(command -v dart)"
if [[ "$RESOLVED_FLUTTER" != "$SDK_DIR/bin/flutter" || "$RESOLVED_DART" != "$SDK_DIR/bin/dart" ]]; then
  echo "with-fvm-toolchain: resolved flutter=$RESOLVED_FLUTTER dart=$RESOLVED_DART, expected under $SDK_DIR/bin" >&2
  exit 1
fi

# Audit trail
echo "with-fvm-toolchain: flutter=$RESOLVED_FLUTTER dart=$RESOLVED_DART"
flutter --version
dart --version

# Purge toolchain paths baked into native build config by a prior pub get, so a
# native compile cannot pin a global SDK even with PATH and versions correct
for f in \
  consumer-tests/flutter/ios/Flutter/Generated.xcconfig \
  consumer-tests/flutter/ios/Flutter/flutter_export_environment.sh \
  consumer-tests/flutter/android/local.properties ; do
  rm -f "$REPO_ROOT/$f"
done

exec "$@"
