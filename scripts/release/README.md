# Release scripts

One directory per SDK that has a release pipeline. Today that is `flutter/`.
Anything directly in `scripts/release/` is shared across SDKs.

| Path | What it is |
|---|---|
| `flutter/` | The Flutter SDK's release pipeline |
| `assert-safe-path.sh` | Shared guard: accepts only a path that does not exist, or one it already marked. Staging deletes and rewrites the directory it is given, so this is what stops it destroying a directory it does not own |

## The Flutter pipeline

Full runbook, prerequisites, and the publish procedure: the **Flutter** section
of [`DEVELOPMENT.md`](../../DEVELOPMENT.md). This file maps the pipeline to the
files that implement it.

Run everything through `flutter/measure.sh`. It wraps `flutter/release.sh`,
which runs the stages in order and stops at the first failure.

```
flutter/
├── release.sh        orchestrator: runs every stage in order
├── measure.sh        wraps release.sh and reports the archive sizes
├── publish.sh        the only supported way to publish
├── verify-seal.sh    re-seals the stage and diffs it against the pipeline's seal
├── stages/           the steps that produce the package
├── gates/            the checks that decide whether it may ship
├── bin/  lib/  test/ Dart tooling for the checks that need real parsing
├── assets/           canonical license texts the audit compares against
└── license-policy.json
```

### Stages — produce the package

| Script | Does |
|---|---|
| `stages/build-binaries.sh` | Builds the five shipped architectures from a clean `CARGO_TARGET_DIR`, verifies symbols and the iOS deployment target, and writes `BUILD-STAMP.json` (commit + per-file SHA-256) |
| `stages/stage-package.sh` | Copies tracked files plus the built binaries into the staging directory. Refuses a dirty tree, and refuses binaries whose stamp names a commit other than `HEAD` |
| `stages/seal-package.sh` | Prints one line per publishable file: sha256, size, mode, path. The file list comes from pub's own selection, not a directory walk |
| `stages/extract-archive.sh` | Extracts what pub would actually upload |
| `stages/consumer-from-archive.sh` | Builds a disposable consumer app against the extracted archive, so later gates test the shipped artifact rather than the source tree |

### Gates — decide whether it may ship

| Script | Checks |
|---|---|
| `bin/check_identity.dart` | The pubspec, SDK constant, README and podspec all name the same version |
| `bin/license_audit.dart` | Third-party notices match a fresh audit of the shipped dependency graph, and nothing copyleft ships |
| `bin/check_archive.dart` | Archive membership both ways, size limits, exact file count, and every staged binary re-verified against the build stamp |
| `gates/gate-suite.sh` | Both platforms on both Flutter toolchains, symbols in the shipped artifacts, device acceptance, the testing library, and both no-Rust gates |
| `gates/no-rust-gate.sh` | The package builds with no Rust toolchain reachable — the SDK's whole reason for shipping prebuilt binaries |
| `gates/mutation-gates.sh` | That the gates above actually fail on broken input |

### Why mutation gates exist

A gate that passes on a broken subject is worse than no gate: it reports
confidence it has not earned. `gates/mutation-gates.sh` breaks the package in
eight specific ways and requires each gate to fail *and name the mutation*, with
a green baseline established first so that a gate already red for an unrelated
reason cannot masquerade as a catch.

Every defect found in this pipeline so far was a gate verifying an adjacent
property rather than the one that mattered — the file exists, the symbols
resolve, the hash is self-consistent. A real arm64 library placed in
`armeabi-v7a/` passed everything, because nothing checked that a binary matched
the architecture its own path claimed.

**When you add a gate, add its mutation.** The question to answer is not "does
this pass on a good package" but "what would still get through".

## Related scripts outside this directory

The pipeline calls into these; they are not Flutter-release-only.

| Path | Role |
|---|---|
| `scripts/audit/frb-symbol-check.sh` | Verifies required symbols are defined, and that each library matches the architecture its path claims |
| `scripts/package/flutter-build-native.sh` | Maintainer debug build. Never a release input — the pipeline builds its own from a clean commit |
| `scripts/build/artifact-linked-flutter-*.sh` | Consumer-test and acceptance builds the gate suite runs |
| `scripts/build/with-fvm-toolchain.sh` | Pins an exact Flutter/Dart onto `PATH` for a command |
