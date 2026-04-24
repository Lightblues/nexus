# nexus

macOS menu bar toolkit — Pomodoro timer, image uploader, time tracker.

## Quick Reference
- **Install**: `brew install --cask lightblues/tap/nexus`
- **Dev**: `pnpm dev`
- **Build**: `pnpm build:mac` → `.dmg` installer
- **Release**: tag `nexus-vX.Y.Z` → push → CI builds DMG + creates GitHub Release + bumps Homebrew cask
- **Bundle ID**: `site.easonsi.nexus`
- **Data**: `~/.ea/nexus/`
- **Spec**: `.ea/spec/` (spec.md → architecture, pomodoro, tracker, uploader, palette, decisions, changelog)

## Coding Style
- Compact and type-hinted
- Minimal docstrings (for public methods with complex logic only)
- Simple and clear, avoid over-engineering
- Language: English

## TypeScript Environment
- Package manager: `pnpm`
- Run scripts via `pnpm <script>`

## Git
- NEVER use `git commit` directly — code must be reviewed first
- Only use `gh` CLI tools after user approval
