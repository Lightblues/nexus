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

# NOTE: 刚 bump brew 项目可能无法直接更新
# tap 本质是个 git repo，brew 不会每次都 pull
# 手动更新 tap 元数据：
brew update
# 或只更新特定 tap：
brew tap --force lightblues/tap
# brew 比较本地安装版本 vs cask 定义中的 version 字段
brew info --cask lightblues/tap/nexus
brew update                              # 1. 拉最新 cask 定义
brew upgrade --cask lightblues/tap/nexus  # 2. 对比版本，下载新包

brew update && brew upgrade --cask nexus
