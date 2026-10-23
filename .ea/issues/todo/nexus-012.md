---
schema_version: 1
id: nexus-012
title: Mount and inspect the produced DMG in CI
status: todo
priority: high
estimate: S
labels: [ci, dmg, verification]
isolation: local
delivery: none
---

## Objective
Add a CI step that attaches the produced DMG with `hdiutil attach -nobrowse -plist`,
asserts that `Nexus.app` and the `Applications` symlink exist under the mount point, then
detaches — so a DMG that cannot mount, or that mounts without the drag-install layout,
fails the build.

## Context
- `.github/workflows/build.yml:44-54` — the only assertions CI makes on the DMG today:
  `Upload DMG artifact` (`:44-50`) with `if-no-files-found: error` on `dist/Nexus-*.dmg`
  (`:49`), then `Show dist contents` (`:52-53`, `ls -la dist/`). "A file exists" is not
  "the volume mounts and contains the app".
- `scripts/build-mac.sh:109-123` — the packaging block this check verifies:
  `DMG_PATH="$DIST_DIR/Nexus-$VERSION.dmg"` (`:110`), a fresh staging dir (`:112-113`),
  `cp -R "$APP_PATH" "$STAGE_DIR/Nexus.app"` (`:114`),
  `ln -s /Applications "$STAGE_DIR/Applications"` (`:115`), and
  `hdiutil create ... -format UDZO` (`:118-123`). Nothing inspects the result; the script
  goes straight to `shasum` (`:126`).
- `scripts/build-mac.sh:125-127` — the sha256 sidecar is computed from the DMG's file
  bytes without mounting it, so an unusable volume still yields a valid-looking
  `.sha256` that the release job later publishes (`:126-127`).
- `scripts/install-local.sh:27-43` — the mount-and-parse idiom to reuse, already written
  and known to work: `hdiutil attach "$DMG" -nobrowse -plist` (`:31`), a `python3`
  `plistlib` parse that walks `system-entities` for `mount-point` (`:32-39`), a guard on
  the result (`:40`), a `trap ... EXIT` that detaches (`:41`), and the app assertion
  `[[ -d "$SRC" ]]` (`:42-43`). Its own comment at `:27-29` records why the plist path is
  used: `hdiutil`'s plain output is tab-separated and volume names can contain spaces.
- `.github/workflows/build.yml:55-58` — the `release` job's tag guard, which must stay
  untouched; the new step belongs in `build`.
- `.github/workflows/build.yml:84-90` — the release job's `Compute DMG sha256` step,
  which consumes the DMG the build job produced; a DMG that cannot mount is exactly what
  this step cannot detect.
- `.ea/spec/spec.md:44` — "Architectures | per-arch DMG | universal binary (single DMG)".
  The single-DMG distribution is a documented product property, so its usability is
  user-facing rather than cosmetic.
- `CLAUDE.md:10` — `./scripts/build-mac.sh` → `dist/Nexus-<version>.dmg`, the artefact
  this check must consume.
- `.ea/report/gap-analysis.md` §2 V-02 — the finding; its "Smallest automated check"
  paragraph is the shape of this issue.

## Tasks
- [ ] Add a step to the `build` job in `.github/workflows/build.yml` after `Build DMG` (`:39-42`) that resolves the produced `dist/Nexus-*.dmg` and mounts it with `hdiutil attach -nobrowse -plist`
- [ ] Parse the mount point out of the plist (`system-entities` → `mount-point`) using the `install-local.sh:32-39` idiom, and fail the step when no mount point is returned
- [ ] Assert `"$MOUNT/Nexus.app"` is a directory and `"$MOUNT/Applications"` is a symlink; print the mount contents on failure so the missing piece is visible in the job log
- [ ] Detach the volume on every exit path (`trap ... EXIT`, as at `install-local.sh:41`) so a failed assertion does not leave the runner with a mounted image
- [ ] Leave the existing `Upload DMG artifact` and `Show dist contents` steps working and leave the `release` job unchanged
- [ ] Settle with nexus-011 which issue owns the architecture assertion for the DMG's binary, and keep it in exactly one place

## Acceptance
- [ ] `.github/workflows/build.yml` contains a step that mounts the produced DMG with `hdiutil attach -nobrowse -plist`
- [ ] The step asserts both `Nexus.app` and the `Applications` symlink exist under the mount point, and fails when either is missing
- [ ] On the current tree the step passes: `dist/Nexus-<version>.dmg` mounts, contains `Nexus.app`, and contains an `Applications` symlink targeting `/Applications`
- [ ] With a deliberately truncated DMG, the step fails at the attach or parse stage with a message naming the DMG path
- [ ] With the `ln -s /Applications` line removed from `scripts/build-mac.sh:115`, the step fails on the symlink assertion instead of passing
- [ ] The volume is detached on success and on failure — `hdiutil info` shows no leftover mount after the step
- [ ] The step runs on a clean `macos-14` runner and does not depend on `scripts/install-local.sh` being present or executable

## Boundaries
- Always: mount with `-nobrowse -plist` and parse the plist — `install-local.sh:27-29` records that `hdiutil`'s tab-separated output breaks on a volume name containing spaces
- Always: assert the `Applications` symlink as well as `Nexus.app`; the drag-install depends on it and `build-mac.sh:115` is the only thing that creates it
- Always: detach on every exit path, so a failed assertion does not leave the runner holding a mounted image
- Never: substitute a `file`/`ls` check on the DMG — only mounting proves the volume is usable and carries the install layout
- Never: verify the DMG by running `scripts/install-local.sh` in CI; it writes to `/Applications` and launches the app, which is a different and destructive check
- Never: duplicate the architecture assertion nexus-011 adds to `build-mac.sh`; agree which issue owns it so one failure is reported once
- Ask: whether the step should also verify the sha256 sidecar against the DMG it mounted (the sidecar is written at `build-mac.sh:126-127` and trusted by the release job's cask bump at `.github/workflows/build.yml:84-90`). It would catch a stale sidecar before the release job publishes it, but it is beyond V-02's "smallest check"
- Ask: whether the mount check stays in the `build` job (as written) or becomes its own job. Keeping it in `build` means it also runs on the release path, which is where an unusable DMG matters most
