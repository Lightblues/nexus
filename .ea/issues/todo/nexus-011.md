---
schema_version: 1
id: nexus-011
title: Make the `codesign` and `lipo` checks fail the build
status: todo
priority: high
estimate: S
labels: [ci, codesign, verification]
isolation: local
delivery: none
---

## Objective
Drop the `|| true` on the deep signature check and assert that `lipo -archs` lists both
`arm64` and `x86_64`, so an unsigned or single-architecture bundle fails the build
instead of printing and passing.

## Context
- `scripts/build-mac.sh:101-103` — the ad-hoc signing block:
  `codesign --force --deep --sign - "$APP_PATH"` (`:102`) followed by
  `codesign --verify --verbose=2 "$APP_PATH" || true   # sanity check` (`:103`). The
  `|| true` makes the verification unconditionally succeed, which is the defect.
- `scripts/build-mac.sh:105-107` — `echo "==> Architecture check"` (`:106`) and
  `lipo -info "$APP_PATH/Contents/MacOS/Nexus"` (`:107`). `lipo -info` prints the
  architectures and exits 0 for any valid Mach-O, so nothing asserts that both
  architectures the build requested are present.
- `scripts/build-mac.sh:57-69` — the archive invocation that requests the universal
  build: `ARCHS="arm64 x86_64"` (`:64`) with `ONLY_ACTIVE_ARCH=NO` (`:65`). This is the
  promise the two checks must hold the output to.
- `scripts/build-mac.sh:17` — `set -euo pipefail`. Because `codesign --verify` and `lipo`
  are the last commands in their pipelines, removing `|| true` is enough to make a
  non-zero exit stop the script.
- `scripts/build-mac.sh:109-123` — the DMG staging and `hdiutil create`. A bundle that
  fails either check is still copied into the DMG at `:114`, so the checks have to fail
  before this block rather than after it.
- `project.yml:19-22` — `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "-"`,
  `DEVELOPMENT_TEAM: ""`, `ENABLE_HARDENED_RUNTIME: NO`. The bundle is ad-hoc signed by
  design, so the check is "the signature is intact", not "a Developer ID signature
  exists".
- `project.yml:17` — `ARCHS: "$(ARCHS_STANDARD)"`, which the archive step overrides to
  `arm64 x86_64` (`build-mac.sh:64`). The two halves of the universal-binary story live
  in different files, and only the archive half is asserted by anything today.
- `.ea/spec/spec.md:44` — the quick-reference row "Architectures | per-arch DMG |
  universal binary (single DMG)". Shipping a single-arch DMG is therefore a spec
  violation, not just a packaging detail.
- `.ea/spec/decisions.md:106-168` — SADR-006, the accepted decision to ad-hoc sign with
  no Developer ID and no notarization; its status line (`:107`) is "Deferred". This is
  why the check asserts integrity rather than identity.
- `CLAUDE.md:10` — `./scripts/build-mac.sh` → `dist/Nexus-<version>.dmg` is the only
  release path, so the assertion has exactly one place to live.
- `.ea/report/gap-analysis.md` §2 V-03 — the finding; its "Smallest automated check"
  paragraph is the shape of this issue.

## Tasks
- [ ] Drop `|| true` from the `codesign --verify` line (`scripts/build-mac.sh:103`) so a broken signature fails the script under `set -euo pipefail`
- [ ] Strengthen that check to a strict deep verification — `codesign --verify --strict --deep "$APP_PATH"` — and keep its own output so a failure names the offending file
- [ ] Replace the print-only `lipo -info` (`:107`) with an assertion that the `lipo -archs` output contains both `arm64` and `x86_64`, exiting non-zero with the actual arch list when either is missing
- [ ] Keep both checks ahead of the DMG staging block (`:109-123`) so a bad bundle never reaches `hdiutil create`
- [ ] Confirm the happy path still builds a DMG on the current tree, and that both checks actually execute in that run rather than being skipped

## Acceptance
- [ ] `sed -n '103p' scripts/build-mac.sh` does not contain `|| true`
- [ ] The script asserts that `lipo -archs "$APP_PATH/Contents/MacOS/Nexus"` output contains `arm64` and `x86_64`, and exits non-zero when either is absent
- [ ] `./scripts/build-mac.sh` still produces `dist/Nexus-<version>.dmg` on the current tree, and `lipo -archs` on the built binary prints `arm64 x86_64`
- [ ] With the signature deliberately damaged (e.g. `codesign --remove-signature` on the exported bundle), the script exits non-zero before `hdiutil create` runs
- [ ] With the archive forced to one architecture (e.g. `ARCHS="arm64"`), the script exits non-zero with a message naming the missing architecture
- [ ] Both checks run before the DMG is created, so a failing bundle never lands in `dist/`
- [ ] The failure messages are actionable alone — they name the arch list or the `codesign` complaint, without needing the surrounding build log

## Boundaries
- Always: keep the checks inside `scripts/build-mac.sh`, the single release path, rather than adding a separate verification script CI must remember to call
- Always: assert the signature is *intact* (`--verify --strict --deep`), not that it carries a particular identity — SADR-006 (`decisions.md:106-168`) makes ad-hoc signing the accepted state
- Never: reintroduce `|| true`, `continue-on-error`, or `set +e` around these checks; their only value is that they can fail the build
- Never: move the checks after the DMG staging block — a bundle that fails either check must not be copied into the DMG at `:114`
- Never: widen this into adding notarization or a Developer ID signature; that is SADR-006 / gap-analysis T-01 and needs an Apple Developer account and a human decision
- Ask: whether the arch assertion should derive the expected set from the archive invocation (`:64`) or hardcode `arm64 x86_64`. Hardcoding is simpler and matches the spec's universal-binary claim; deriving keeps the two in sync if the requested set ever changes
- Ask: whether the DMG's own binary should also be checked for architectures. Mounting the DMG is nexus-012's scope, so if both land, decide which issue owns the architecture assertion and keep the failure reported once, in the right place
