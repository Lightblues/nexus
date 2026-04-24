# --- pnpm ---
pnpm install

pnpm build:mac  # dist/Nexus-0.3.5-arm64.dmg
pnpm dev

# --- url schema ---
open "nexus://command/pomodoro.toggle"
open "nexus://command/pomodoro.start"
open "nexus://command/pomodoro.pause"

open "nexus://command/window.openMain"

# --- brew ---
brew install --cask lightblues/tap/nexus
brew upgrade --cask nexus
brew upgrade --cask    # 更新所有 cask
brew uninstall --cask nexus           # 只删 app
brew uninstall --cask --zap nexus     # 删 app + 清数据 (~/.ea/nexus, ~/Library/Preferences/site.easonsi.nexus.plist 等)
