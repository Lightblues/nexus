---
description: Tag a release and trigger CI build
allowed-tools: Bash(pnpm *) Bash(git *) Bash(gh *)
argument-hint: "[version|patch|minor|major]"
---

Instructions:
1. Read the current version from `package.json`.
2. If `$ARGUMENTS` is provided, use it as the new version (e.g., `0.4.0` or `patch`/`minor`/`major`). Otherwise, bump the patch version automatically.
3. If the argument is `patch`, `minor`, or `major`, calculate the new semver accordingly from the current version.
4. Update the `version` field in `package.json` to the new version.
5. Run `pnpm install --lockfile-only` to sync `pnpm-lock.yaml`.
6. Create a git commit with message: `release: nexus v{version}`
7. Create a git tag `nexus-v{version}`.
8. Push the commit and tag to origin: `git push origin main --follow-tags`
9. Report the tag name and the CI workflow URL (use `gh run list -w build.yml -L 1` to find it).
