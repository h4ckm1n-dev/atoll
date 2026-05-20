# Changelog | 更新日志

All notable changes to Open Island are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/) and the project adheres to [Semantic Versioning](https://semver.org/).

本文件记录 Open Island 的所有显著变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/)，版本编号遵循 [语义化版本](https://semver.org/)。

---

## Open Island v1.3.0 — Branch-aware island, refined glass cards
## Open Island v1.3.0 — 分支感知徽章与精炼玻璃卡片

Branch-aware diff badges, refined session glass cards with collapse-by-default for completed plans, refreshed installer artwork, and an in-app changelog viewer.
本版本带来按分支区分的差异徽章、精炼后的会话玻璃卡片（已完成的计划默认折叠）、更新的安装包外观，以及应用内更新日志查看器。

### Changes since v1.2.0-atoll | 自 v1.2.0-atoll 以来的变更

#### Features | 新功能

- **Island badge**: Branch-aware diff scope — WIP count on `main`/`master`, cumulative PR-size diff (`main...HEAD`) on feature branches (#52)
  **岛屿徽章**：按分支区分的差异统计 — `main`/`master` 显示工作目录差异，特性分支显示相对于 `main` 的累积差异（#52）
- **Settings**: Expandable update card with embedded GitHub changelog (#49)
  **设置面板**：可展开的更新卡片，内嵌 GitHub 更新日志（#49）
- **Session cards**: Polished glass aesthetic across the island panel
  **会话卡片**：灵动岛面板整体玻璃质感优化

#### Fixes | 修复

- **Plan cards**: Collapse completed plan cards by default to keep focus on in-progress work (#53)
  **计划卡片**：默认折叠已完成的计划卡片，让焦点保持在进行中的工作（#53）
- **Glass contrast**: Tune liquid glass contrast for better readability across appearance modes
  **玻璃对比度**：调整液态玻璃对比度，提升不同外观模式下的可读性

#### Maintenance | 维护

- **Brand**: Refresh DMG installer background artwork (#54)
  **品牌**：更新 DMG 安装包背景图（#54）
- **Dependencies**: Sparkle bumped to 2.9.2 (#51)
  **依赖**：Sparkle 升级至 2.9.2（#51）
- **Dependencies**: argmax-oss-swift bumped to v1 (#47)
  **依赖**：argmax-oss-swift 升级至 v1（#47）

---

## Installation | 安装说明

1. Download **Open Island.dmg**, open it, and drag **Open Island** to **Applications**.
   下载 **Open Island.dmg**，打开后将 **Open Island** 拖入 **Applications**。

2. Requires **macOS 14+**. Supports both **Apple Silicon** and **Intel** Macs.
   需要 **macOS 14+**。同时支持 **Apple Silicon** 和 **Intel** Mac。

> This build is signed and notarized with Apple Developer ID. You can open it directly without any security workaround.
> 本版本已通过 Apple 签名公证，可直接打开运行，无需任何安全设置。
