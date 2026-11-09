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
   | `fix(flutter): handle an empty flag key` | patch |
   | `feat(rn): add typed getters` | minor |
   | `feat(rn)!: remove the legacy observer` | major |
   | `refactor:`, `test:`, `chore:`, `docs:`, `build:`, `ci:`, `style:` | none |

   A README fix that should reach the published documentation uses `fix:`,
   because documentation is published with each release.

   A releasing title becomes a public release note in the SDK's changelog, on
   pub.dev, and in the GitHub release, so write it for developers who use the
   SDK. Name the public API or the visible behavior and what it does for them.
   Leave out internal details, such as the FFI, caches, and internal module
   names. Leave out other SDKs' names.

   | Title | Verdict |
   |---|---|
   | `feat: add getStringList and getNumberList to read list flags` | good |
   | `feat: typed list flag getters across the FFI` | bad |

2. **If you changed the shared Rust core,** meaning `core/`, `ffi/`,
   `Cargo.toml`, `Cargo.lock`, or `rust-toolchain.toml`, the SDKs that ship the
   change need a `CORE_RELEASE_TRIGGER` file. For a pull request from a branch
   in this repository, the "Core release trigger" workflow writes and commits
   those files when a releasing title needs them. On such a pull request the
   "Shared core release" check can fail on your own commit until the workflow's
   commit lands, so wait for it rather than running the script. After it
   commits, run `git pull --rebase` before pushing again.

   The check says when you need to run the script yourself, for example on a
   pull request from a fork or one that edits the release config. Run it and
   commit the files it writes. They mark which SDKs ship the change:

   ```bash
   scripts/release/core-changed.sh
   ```

The PR checks run on every pull request. Each failure states what to fix.

Never edit version numbers, marked version lines, tags, or changelogs. Never
publish or tag by hand, except in an urgent or emergency release, which follows
the maintainer runbook in `DEVELOPMENT.md`.

## Checking locally

Running the PR checks before pushing is optional:

```bash
scripts/release/check-all.sh
```

It runs the checks that apply to your branch, and needs no credentials.
Commit first, because the title and shared core checks read commits. Set
`CHECK_TITLE` to your intended PR title when the branch has several commits.

## Platforms

React Native and Flutter versions are managed by
[release-please](https://github.com/googleapis/release-please). Merging the
Flutter release PR starts the `Publish Flutter` workflow, which publishes to
pub.dev once its checks pass. The merge is the release decision, and no one
approves the publish step afterward. The maintainer steps are in
`DEVELOPMENT.md`.
