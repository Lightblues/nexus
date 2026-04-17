---
description: Tag a release and trigger CI build
allowed-tools: Bash(pnpm *) Bash(git *) Bash(gh *)
argument-hint: "[version|patch|minor|major]"
---

Context:
- Current version: `!node -p "require('./package.json').version"`
- Git status: `!git status --short`
- Recent commits: `!git log --oneline -5`

Instructions:
1. If git is not clean (there are uncommitted changes), show the context above and ask the user whether to commit first before proceeding with the release. If yes, create a commit with an appropriate message.
2. If `$ARGUMENTS` is provided, use it as the new version (e.g., `0.4.0` or `patch`/`minor`/`major`). Otherwise, bump the patch version automatically. If the argument is `patch`, `minor`, or `major`, calculate the new semver accordingly from the current version.
3. Update the `version` field in `package.json` to the new version.
4. Run `pnpm install --lockfile-only` to sync `pnpm-lock.yaml`.
5. Create a git commit with message: `release: nexus v{version}`
6. Create an annotated git tag: `git tag -a nexus-v{version} -m "nexus v{version}"`.
7. Push the commit and tag to origin: `git push origin main --follow-tags`
8. Report the tag name and the CI workflow URL (use `gh run list -w build.yml -L 1` to find it).
