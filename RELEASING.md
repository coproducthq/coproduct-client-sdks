# Releasing

The version, tag, and changelog of each Coproduct SDK release come from the
commits merged to `main`, so nobody edits them by hand.

## Contributing a change

1. **Title your pull request with a Conventional Commit type.** Pull requests
   merge as a single squashed commit whose message is the title, and the type
   decides the version:

   | Title | Release |
   |---|---|
   | `fix(rn): handle an empty flag key` | patch |
   | `feat(rn): add typed getters` | minor |
   | `feat(rn)!: remove the legacy observer` | major |
   | `refactor:`, `test:`, `chore:`, `docs:`, `build:`, `ci:`, `style:` | none |

   A README fix that should reach the published documentation uses `fix:`,
   because documentation is published with each release.

2. **If you changed the shared Rust core,** meaning `core/`, `ffi/`,
   `Cargo.toml`, `Cargo.lock`, or `rust-toolchain.toml`, run:

   ```bash
   scripts/release/core-changed.sh
   ```

   and commit the files it writes. They mark which SDKs ship the change.

The PR checks run on every pull request. Each failure states what to fix.

Never edit version numbers, marked version lines, tags, or changelogs, and
never publish or tag by hand.

## Checking locally

Running the PR checks before pushing is optional:

```bash
scripts/release/check-all.sh
```

It runs the checks that apply to your branch, and needs no credentials.
Commit first, because the title and shared core checks read commits. Set
`CHECK_TITLE` to your intended PR title when the branch has several commits.

## Platforms

React Native versions are managed by
[release-please](https://github.com/googleapis/release-please). Flutter is
published through its release pipeline in `scripts/release/flutter/`.
