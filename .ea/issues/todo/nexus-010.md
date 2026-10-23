---
schema_version: 1
id: nexus-010
title: Build and test `main` on every push, not only on release tags
status: todo
priority: high
estimate: S
labels: [ci, build, verification]
isolation: local
delivery: none
---

## Objective
Add `push: branches: [main]` and `pull_request` triggers to a job that runs
`./scripts/build-mac.sh` on `macos-14`, so a compile break on `main` is caught at the
offending commit rather than when someone tries to cut a release — and stop discarding
the archive step's exit status so a failed compile actually fails that job.

## Context
- `.github/workflows/build.yml:3-13` — the entire `on:` block: `workflow_dispatch` with a
  `version` input (`:4-9`) plus `push: tags: [nexus-v*]` (`:10-12`). There is no branch or
  pull-request trigger, so between tags nothing builds at all.
- `.github/workflows/build.yml:14-53` — the `build` job this trigger belongs on:
  `runs-on: macos-14` (`:16`), `Select Xcode` (`:20-21`,
  `sudo xcode-select -s /Applications/Xcode.app` — selected by path, not by version),
  `Install XcodeGen` (`:23-24`), `Resolve version` (`:26-37`), `Build DMG` (`:39-42`,
  `./scripts/build-mac.sh`), `Upload DMG artifact` (`:44-50`), `Show dist contents`
  (`:52-53`).
- `.github/workflows/build.yml:55-58` — the separate `release` job, gated by
  `if: startsWith(github.ref, 'refs/tags/nexus-v')` (`:58`). This guard is what keeps
  publishing tag-only; a new trigger must not widen it.
- `.github/workflows/build.yml:82-125` — the cask-bump half of the `release` job, which
  must stay unreachable from a branch push.
- `scripts/build-mac.sh:30-34` — `xcodegen generate`, which regenerates
  `Nexus.xcodeproj` from `project.yml` (`Nexus.xcodeproj/` is gitignored, `.gitignore:10`),
  so the push job compiles the same generated project a release does.
- `scripts/build-mac.sh:57-69` — the archive invocation, ending
  `archive | grep -E "^\*\* |error:|warning:" || true` (V-05). The `|| true` is the
  defect: under `set -euo pipefail` (`:17`) it applies to the whole pipeline, so a failing
  `xcodebuild archive` does not stop the script.
- `scripts/build-mac.sh:88-96` — `xcodebuild -exportArchive`, where a failed archive
  currently surfaces instead — as a missing-archive error rather than the compile error
  the `grep` filter already discarded (`:96`,
  `[[ -d "$APP_PATH" ]] || { echo "Export failed: $APP_PATH not found"; exit 1; }`).
- `scripts/build-mac.sh:36-48` — the `objectVersion` → 56 patch, which exists only because
  CI's Xcode is older than the developer's; it is the clearest sign that the runner's
  toolchain, not the local one, is the gating build.
- `project.yml:15` and `project.yml:30` — `SWIFT_VERSION: "5.9"` and
  `SWIFT_STRICT_CONCURRENCY: "minimal"`, the two settings that exist to keep the CI Xcode
  building (the comment at `:25-29` says tightening is "a future refactor").
- `.ea/spec/pitfalls.md:17-36` (§1.1) — CI's Xcode 15 rejects `objectVersion = 77` emitted
  by a local Xcode 26; the pin to 56 is deliberate.
- `.ea/spec/pitfalls.md:38-115` (§1.2) — five Swift compile errors that appeared in CI
  (Xcode 15) and not locally (Xcode 26), including the v1.2.0 release blocker fixed by
  annotating `route()` at `Nexus/App/NexusApp.swift:36` (referenced at `:115`).
- `.ea/spec/pitfalls.md:117-124` (§1.3) — "Local `it builds` is not signal. The **only**
  signal is the CI runner's Xcode version." This sentence is the whole argument for a
  build-on-push job.
- `.ea/report/gap-analysis.md` §2 V-04 (nothing builds except a release tag) and §2 V-05
  (the discarded archive exit status); the section's "Folded into a candidate row" list
  records V-05 as riding along with this row.

## Tasks
- [ ] Add `push: branches: [main]` and a `pull_request` trigger to the `on:` block of `.github/workflows/build.yml`, keeping the existing `workflow_dispatch` and `push: tags: [nexus-v*]` entries working
- [ ] Confirm the added triggers start the `build` job (`:14-53`) and cannot reach the `release` job; leave `if: startsWith(github.ref, 'refs/tags/nexus-v')` (`:58`) as the gate
- [ ] Stop discarding the archive exit status: drop the trailing `|| true` on `scripts/build-mac.sh:69` (or capture `${PIPESTATUS[0]}` and exit on it), keeping the `grep -E "^\*\* |error:|warning:"` output so compiler errors stay visible
- [ ] Verify the happy path locally — `./scripts/build-mac.sh` still produces `dist/Nexus-<version>.dmg` after the change
- [ ] Verify the failure path: with a deliberate compile error, the script fails at the archive step with the `error:` lines in the output, not later at `-exportArchive`
- [ ] Add a short comment above the archive invocation explaining that its exit status is load-bearing, so `|| true` is not restored later for cosmetic reasons

## Acceptance
- [ ] The `on:` block of `.github/workflows/build.yml` contains `push: branches: [main]` and a `pull_request` trigger
- [ ] A commit pushed to `main` (or a PR opened against it) starts the `build` job; the `release` job does not run
- [ ] A `nexus-v*` tag still runs `build` and then `release`, with the release steps unchanged
- [ ] `sed -n '69p' scripts/build-mac.sh` does not end in `|| true`, and a failing `xcodebuild archive` exits the script non-zero
- [ ] With a deliberate compile error, the build log contains the `error:` lines from `xcodebuild` and the job fails
- [ ] `./scripts/build-mac.sh` still succeeds end to end locally and writes `dist/Nexus-<version>.dmg`
- [ ] The runner stays `macos-14` (`:16`) and no second build path is introduced — the job still calls `./scripts/build-mac.sh`

## Boundaries
- Always: gate the new triggers on the `build` job only; publishing a Release and bumping the Homebrew cask stay tag-only (`:58`, `:82-125`)
- Always: keep `grep -E "^\*\* |error:|warning:"` on the archive output — the fix is the exit status, not the filtering
- Never: remove `set -euo pipefail` (`scripts/build-mac.sh:17`) or weaken it to work around the pipeline; the discarded status is the bug, and strict mode is what makes the fix effective
- Never: add a second build path for the push job — it runs `./scripts/build-mac.sh`, the same script a release uses, so a green push job means the release path builds
- Never: let the push job publish or upload a DMG as a release artefact; that belongs to the `release` job behind the tag guard
- Ask: whether the push trigger should run the full `build-mac.sh` (archive + export + DMG) or a cheaper `xcodebuild build`. V-04 asks for the release path exactly; a lighter build is faster but does not exercise the archive/export steps where the failures in §1.1-§1.3 actually appear
- Ask: whether `pull_request` should cover all branches or only those targeting `main`, and whether to add a `concurrency` group to cancel superseded runs. Both are workflow-policy choices this issue does not settle
