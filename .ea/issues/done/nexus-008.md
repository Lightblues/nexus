---
id: nexus-008
title: Rename app to Nexus and set up Homebrew tap for distribution
status: done
priority: medium
estimate: L
labels: [infra, distribution, homebrew]
---

## Objective
Rename the application from "EA Nexus" to "Nexus" (cleaner branding) and set up a Homebrew tap for easy installation on new machines.

## Context
- Tap repo: `lightblues/homebrew-tap` at `/Users/frankshi/LProjects/app/homebrew-tap`
- App uses ad-hoc signing (no Apple Developer ID)
- Users need to run `xattr -dr com.apple.quarantine` after install
- Tracker feature requires Accessibility permission grant

## Tasks
- [x] Rename productName: "EA Nexus" → "Nexus"
- [x] Update appId: `com.ea.nexus` → `site.easonsi.nexus`
- [x] Update package.json name: `ea-nexus` → `nexus`
- [x] Keep data directory as `~/.ea/nexus/` (no migration needed)
- [x] Create `lightblues/homebrew-tap` GitHub repository
- [x] Write cask definition file for Nexus
- [x] Configure GitHub Actions to publish releases with ad-hoc signing
- [x] Document installation instructions (tap + cask + quarantine removal)

## Acceptance
- [x] App shows as "Nexus.app" in Finder and Dock
- [x] `brew install --cask lightblues/tap/nexus` installs successfully
- [x] App launches after `xattr -dr com.apple.quarantine` on fresh install
- [x] Existing user data in `~/.ea/nexus/` continues to work
