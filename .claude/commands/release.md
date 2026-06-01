---
description: Tag a release and trigger CI build
allowed-tools: Bash(git *) Bash(gh *) Bash(awk *) Bash(sed *) Bash(grep *) Bash(plutil *) Bash(xcodegen *)
argument-hint: "[version|patch|minor|major]"
---

Context:
- Current version: `!awk -F'"' '/CFBundleShortVersionString/ {print $2; exit}' project.yml`
- Git status: `!git status --short`
- Recent commits: `!git log --oneline -5`

Instructions:

The single source of truth for the app version is `project.yml`'s
`CFBundleShortVersionString`. `Nexus/Resources/Info.plist` mirrors it (xcodegen
regenerates Info.plist from project.yml on every build).

1. If git is not clean (there are uncommitted changes), show the context above and ask the user whether to commit first before proceeding with the release. If yes, create a commit with an appropriate message.
2. If `$ARGUMENTS` is `patch`, `minor`, or `major`, compute the new semver from the current version. Otherwise treat `$ARGUMENTS` as the new version literal (e.g. `1.2.0`). If `$ARGUMENTS` is empty, default to a patch bump.
3. Update both files to the new version:
   - `project.yml`: replace `CFBundleShortVersionString: "X.Y.Z"` line.
   - `Nexus/Resources/Info.plist`: update the `<string>X.Y.Z</string>` entry below `<key>CFBundleShortVersionString</key>`.
   Verify with `grep CFBundleShortVersionString project.yml` and `grep -A1 CFBundleShortVersionString Nexus/Resources/Info.plist` that both show the new version.
4. Create a git commit with message: `release: nexus v{version}`
5. Create an annotated git tag: `git tag -a nexus-v{version} -m "nexus v{version}"`.
6. Push the commit and tag to origin: `git push origin main --follow-tags`
7. Report the tag name and the CI workflow URL (use `gh run list -w build.yml -L 1` to find it).

Notes:
- CI (`.github/workflows/build.yml`) is triggered by tags matching `nexus-v*`. The `Build Nexus (Swift)` workflow archives a universal DMG, creates the GitHub Release, and bumps the Homebrew cask via the inline tap-update step.
- No `pnpm install` step — Nexus is Swift-only. There is no `package.json` and no Node lockfile to sync.
