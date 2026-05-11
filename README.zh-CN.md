<p align="center">
  <img src="Assets/Brand/atoll-app-icon.png" alt="Atoll" width="200" height="200">
</p>

<p align="center">
  <strong>专为 AI 编程 Agent 打造的原生 macOS 伴侣。</strong>
  <br>
  一个驻留在刘海区域、支持主题定制、本地优先的控制中心，监控你运行的每一个 Agent。
  <br><br>
  <strong>中文</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases/latest"><img src="https://img.shields.io/github/v/release/h4ckm1n-dev/atoll?style=flat-square&label=release&color=89b4fa" alt="最新版本"></a>
  <a href="https://github.com/h4ckm1n-dev/atoll/stargazers"><img src="https://img.shields.io/github/stars/h4ckm1n-dev/atoll?style=flat-square&color=f9e2af" alt="Stars"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-fab387?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.2-fab387?style=flat-square" alt="Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-a6e3a1?style=flat-square" alt="开源协议: GPL v3"></a>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases">下载</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#核心功能">核心功能</a> ·
  <a href="#路线图">路线图</a> ·
  <a href="docs/index.md">文档</a>
</p>

<img width="1800" height="1169" alt="Atoll 展示" src="https://github.com/user-attachments/assets/e8ffb3e8-2cb0-42a6-9b0a-f0591759950f" />

---

## Atoll 是什么？

**Atoll** 是一款原生 macOS 应用，它将你的 **刘海区域**（或顶部工具栏）转化为一个实时的、支持主题定制的 AI 编程 Agent 控制中心。它为你提供了会话管理、权限审批、内联 Diff 预览和计划执行的统一入口——全程本地运行，响应极快。

名字源于其几何形状：环绕着平静礁湖的一圈陆地——恰如包裹着 Mac 刘海的面板，Agent 的活动如同海鱼跃出水面。

> *支持 11 款 Agent，15+ 种终端。环绕刘海的珊瑚环。*

## 为什么选择 Atoll？

- **本地优先**：无服务器、无遥测、无需账号。一切都在你的 Mac 上运行。
- **原生 macOS**：基于 SwiftUI + AppKit 构建。专为 Mac 体验打造。
- **深度集成**：开箱即用支持 11+ 种编程 Agent 和 15+ 种终端/IDE。
- **全方位主题**：Catppuccin, Tokyo Night, Dracula 等。甚至 Diff 语法高亮也会随主题自动变色。
- **行动导向**：不只是观察。直接在刘海中审批权限、回答问题，或一键跳回正确的终端会话。
- **开源、GPL v3**：Fork 它、改它、发布你自己的版本。

---

## 界面截图

<p align="center">
  <img src="docs/images/screenshots/approval-card-with-diff.png" alt="权限审批卡片与内联 Diff" width="640">
</p>

<p align="center">
  <em>权限审批卡片与内联 Diff —— Myers 算法实现的 Swift 代码修改预览，随主题变化的语法高亮，桃色提醒边框。在点击“允许”前，清楚看到即将发生的改变。</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/question-card.png" alt="问题卡片" width="640">
</p>

<p align="center">
  <em>问题卡片 —— Agent 转发的结构化多选提示。无需离开刘海即可提交答案。</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/long-completion-card.png" alt="完成卡片" width="640">
</p>

<p align="center">
  <em>完成卡片 —— Agent 最终回复的主题化 Markdown 渲染。支持内联回复；Atoll 会将其自动键入你的终端。</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/completion-card.png" alt="简要完成通知" width="640">
</p>

<p align="center">
  <em>简要完成通知 —— 当 Agent 任务结束时从刘海弹出，随后自动消失。</em>
</p>

---

## 核心功能

### 🎨 主题定制与个性化
Atoll 为注重工作空间美感的开发者而生。
- **端到端主题重绘**：在 Catppuccin, Tokyo Night, Dracula, Gruvbox 等主题间无缝切换。整个 UI，包括语法高亮的 Diff 视图，都会瞬间适配。
- **内置主题编辑器**：不满意默认主题？使用包含 26 个色块的实时编辑器打造属于你的 JSON 主题并导出。
- **毛玻璃效果**：提供实体、薄毛玻璃、超薄毛玻璃三种材质，让壁纸颜色自然透出。
- **项目专属配色**：每个工作区都会根据路径生成唯一的稳定色调，让你一眼识别当前活跃的项目。

### 📝 智能 Agent 掌控
- **内联 Diff 预览**：在授予权限前，直接查看 Agent 准备修改的代码差异（Myers 算法，带语法高亮）。
- **计划模式清单**：交互式的结构化清单。在审批前查看计划，在执行过程中跟踪 Agent 勾选的每一个步骤。
- **审批驾驶舱**：在控制中心提供专用队列，集中管理多个待审批的权限请求和问题。
- **会话时间线**：详细的审计日志，记录会话启动、工具调用、权限审批和完成的每一个瞬间。

### ⌨️ 键盘优先与自动化
- **刘海键盘导航**：完全通过键盘（Tab, 方向键, Enter, Esc）即可浏览岛屿、切换会话和执行操作。
- **自动化深度链接**：通过 `atoll://` URL 控制 Atoll。完美适配 Raycast, Stream Deck 或 Shell 脚本。
- **精准跳转**：一键（或快捷键）跳回到准确的终端面板、IDE 窗口或 `cmux` 会话。

### 🎵 刘海媒体控制与 Git 状态
- **集成媒体面板**：在刘海下方的独立面板中直接控制音乐播放（播放/暂停/切歌）并查看专辑封面。
- **Git 实时感知**：在刘海的会话行中实时显示当前分支、未提交更改数、新增与删除行数。

### ⌚ 移动端与 Watch 伴侣
即便离开座位，也能掌控全局。
- **远程审批**：在 iPhone 或 Apple Watch 上接收权限请求通知。
- **快捷操作**：直接在手腕上点击“允许”或“拒绝” Agent 的操作。
- **本地桥接**：基于本地网络的 SSE 桥接，安全地连接你的移动设备。

### 🎥 为创作者打造
- **直播模式**：一键脱敏敏感路径和文本，专为直播和录屏设计。
- **OBS 覆盖层**：本地浏览器源，可将会话状态显示在直播画面中，而不泄露终端内容。
- **创作者快启指南**：专为直播主和创作者设计的配置向导。

---

## 支持的 Agents 与终端

**11 款 Agent**：Claude Code, Codex, Codex Desktop App, Cursor, Gemini CLI, Kimi CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy

**15+ 终端与 IDE**：Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, **cmux (原生)**, Kaku, Warp, VS Code, Cursor, Windsurf, Trae, JetBrains 全家桶

---

## 快速开始

### 从源码构建

```bash
git clone https://github.com/h4ckm1n-dev/atoll.git
cd atoll
zsh scripts/launch-dev-app.sh
```

该脚本将构建应用，拷贝至 `~/Applications/Atoll Dev.app`，进行本地签名并启动。Hook 安装可在应用内的 **控制中心** 完成。

> **系统要求**：macOS 14+, Swift 6.2, Xcode 16+

---

## 传承与愿景

Atoll 的代码血脉源自 [@Octane0411](https://github.com/Octane0411) 的 [Open Island](https://github.com/Octane0411/open-vibe-island) 项目，并深受原始 [Vibe Island](https://vibeisland.app/) 的启发。

Atoll 于 2026 年 5 月从 Open Island 分叉，旨在探索本地化 Agent 控制中心的极致可能。此后，它演变成了一个功能完备的生态系统：
- 极其精细的 **主题引擎** 与注册表。
- 连接 Apple Watch 与 iPhone 的 **移动端扩展**。
- 深度集成的 **Git 与媒体控制**。
- 进阶的 **开发者交互体验**，如计划清单和内联 Diff。

虽然我们与 Open Island 共享基础的桥接/Hook 架构，但 Atoll 是一个独立的、专注于“Pro”开发者体验、高阶审美和多端协同的产品。

---

## 开源协议

Copyright © 2026 Atoll Contributors.

Atoll 是 **自由软件**：你可以根据自由软件基金会发布的 **GNU General Public License version 3** (GPL-3.0) 协议条款重新分发或修改它。完整协议内容见 [LICENSE](LICENSE)。

---

<p align="center">
  <em>🌴 椰林树影下，与 AI Agent 共同打磨至深夜。</em>
</p>
