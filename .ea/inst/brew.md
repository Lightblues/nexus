## brew
我应该已经 bump 到 [0.7.0](https://github.com/Lightblues/homebrew-tap) 了, 应该如何更新本地安装的?

什么是 brew 的缓存机制?
```bash
# tap 本质是个 git repo，brew 不会每次都 pull
# 手动更新 tap 元数据：
brew update
# 或只更新特定 tap：
brew tap --force lightblues/tap
# brew 比较本地安装版本 vs cask 定义中的 version 字段
brew info --cask lightblues/tap/nexus
brew update                              # 1. 拉最新 cask 定义
brew upgrade --cask lightblues/tap/nexus  # 2. 对比版本，下载新包
```