<p align="center">
  <img src="Assets/Brand/atoll-app-icon.png" alt="Atoll" width="200" height="200">
</p>

<p align="center">
  <strong>The native macOS companion your AI coding agents deserve.</strong>
  <br>
  A themed, local-first control surface that lives in your notch and watches every agent you run.
  <br><br>
  <a href="README.zh-CN.md">中文</a> | <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases/latest"><img src="https://img.shields.io/github/v/release/h4ckm1n-dev/atoll?style=flat-square&label=release&color=89b4fa" alt="Latest Release"></a>
  <a href="https://github.com/h4ckm1n-dev/atoll/stargazers"><img src="https://img.shields.io/github/stars/h4ckm1n-dev/atoll?style=flat-square&color=f9e2af" alt="Stars"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-fab387?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.2-fab387?style=flat-square" alt="Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-a6e3a1?style=flat-square" alt="License: GPL v3"></a>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases">Download</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#features">Features</a> ·
  <a href="#whats-coming">Roadmap</a> ·
  <a href="docs/index.md">Docs</a>
</p>

<img width="1800" height="1169" alt="Atoll Hero" src="https://github.com/user-attachments/assets/e8ffb3e8-2cb0-42a6-9b0a-f0591759950f" />

---

## What is Atoll?

**Atoll** is a native macOS app that transforms your **notch** (or top-center bar) into a real-time, theme-aware control surface for your AI coding agents. It provides a central hub for session management, permission approvals, inline diff previews, plan execution, Git status, usage telemetry, and system media control — all while staying local, native, and incredibly fast.

The name reflects its design: a thin ring of activity wrapping your Mac's notch, like land around a calm lagoon.

> *Eleven agents. Fifteen-plus terminals. One coral ring around your notch.*

## Why Atoll?

- **Local-first.** No server. No telemetry. No account. Everything runs on your Mac.
- **Native macOS.** SwiftUI + AppKit. Built specifically for the Mac experience.
- **Deep Integration.** Works with 11+ coding agents and 15+ terminals/IDEs out of the box.
- **Theme Everything.** Catppuccin, Tokyo Night, Dracula, and more. Even the diff syntax colors match your theme.
- **Action-Oriented.** Don't just watch; approve permissions, answer questions, control media, and jump back to the right terminal in one click.
- **Stream-Ready.** Compact cards, redaction, OBS surfaces, keyboard navigation, and right-click notch controls keep live coding calm.
- **Open source, GPL v3.** Fork it, mod it, ship your own.

---

## Screenshots

<p align="center">
  <img src="docs/images/screenshots/approval-card-with-diff.png" alt="Permission approval card with inline syntax-highlighted diff" width="640">
</p>

<p align="center">
  <em>Approval card with inline diff — Myers-diff'd Swift edit, palette-driven syntax colors, peach attention border. See exactly what's about to change before you click Allow.</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/question-card.png" alt="Multi-choice question card from the agent" width="640">
</p>

<p align="center">
  <em>Question card — structured multi-choice prompt forwarded from the agent. Submit answers without leaving the notch.</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/long-completion-card.png" alt="Completion card with full markdown body" width="640">
</p>

<p align="center">
  <em>Completion card — themed markdown render of the agent's final reply. Reply inline; Atoll types it back into your terminal.</em>
</p>

<p align="center">
  <img src="docs/images/screenshots/completion-card.png" alt="Brief completion notification card" width="640">
</p>

<p align="center">
  <em>Brief completion notification — pops out of the notch when an agent finishes, auto-dismisses on its own.</em>
</p>

---

## Key Features

### 🎨 Theming & Personalization
Atoll is built for users who care about their workspace aesthetic.
- **End-to-End Retinting:** Switch between Catppuccin (all flavors), Tokyo Night, Dracula, Gruvbox, and more. The entire UI, including syntax-highlighted diffs, adapts instantly.
- **In-App Theme Editor:** Don't like the defaults? Use the 26-picker live editor to craft your own JSON theme and export it.
- **Frosted Material:** Choose between Solid, Frosted (thin), or Frosted (ultra-thin) materials that let your wallpaper bleed through.
- **Project Colors:** Each workspace gets a stable, hash-derived tint so you know exactly which project is active at a glance.
- **Live Avatars:** Pick from the built-in animated glyph set, unlock cyberpunk/hacker/manga styles in Lab, or upload a custom avatar image.

### 📝 Intelligent Agent Control
- **Inline Diff Previews:** See exactly what an agent is about to change with Myers-diff'd syntax highlighting before granting permission.
- **Plan Mode Checklists:** Interactive, structured checklists that agents tick off as they execute. Scan the plan before allowing, and track progress after.
- **Approval Cockpit:** A dedicated queue in the Control Center for managing multiple pending approvals and questions.
- **Session Timeline:** A detailed audit log of every session start, tool use, approval, and completion.

### ⌨️ Keyboard-First & Automation
- **Notch Navigation:** Navigate the island, cycle sessions, and execute actions entirely via keyboard (Tab, Arrows, Enter, Esc).
- **Reply Flow:** Press Enter on a selected session to type in the notch, Enter again to send, and Enter once more to jump back to the related terminal.
- **Right-Click Notch Menu:** Settings, debug tools, overlay visibility, and hook repair live behind the notch context menu instead of permanent chrome buttons.
- **Automation Deep Links:** Control Atoll via `atoll://` URLs. Perfect for Raycast, Stream Deck, or shell scripts.
- **Precision Jump:** One-click (or shortcut) to jump back to the exact terminal pane, IDE window, or `cmux` session.

### 🎵 Notch Media Controls & Git Status
- **Apple-Style Media Player:** Control system Now Playing from the notch with artwork, title, artist, timeline, scrubbing, elapsed/duration, previous/next, play/pause, 15-second seek, shuffle, and repeat.
- **Browser Media Support:** Uses macOS MediaRemote, so browser sources such as YouTube appear when macOS exposes them through Now Playing.
- **Lab Toggles:** Enable or disable the media player and artwork independently from Settings -> Lab.
- **Git Awareness:** Session badges show the current branch plus local diff counts, with additions and removals colored separately.
- **Badge Controls:** Settings -> Lab lets you independently toggle AI tool, terminal, Git branch, Git diff, context usage, and age badges.

### ⌚ Mobile & Watch Companion
Stay in control even when you're away from your desk.
- **Remote Approvals:** Receive notifications on your iPhone or Apple Watch for permission requests.
- **Actionable Notifications:** Allow or Deny agent actions directly from your wrist.
- **SSE Bridge:** A secure, local-network SSE bridge connects your mobile devices to your Mac.

### 🎥 Built for Creators
- **Live Coding Mode:** One-click redaction of sensitive paths and text for streaming.
- **OBS Overlay:** A local-only browser source for showing session status on stream without leaking terminal content.
- **Quick Start Guide:** A dedicated setup flow for streamers and creators.

---

## Supported Agents & Terminals

**11 agents**: Claude Code, Codex, Codex Desktop App, Cursor, Gemini CLI, Kimi CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy

**15+ terminals & IDEs**: Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, **cmux (native)**, Kaku, Warp, VS Code, Cursor, Windsurf, Trae, JetBrains IDEs

<details>
<summary>Full compatibility table</summary>

### Code Agents

| Agent | Status | Description |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking, plan-mode capture |
| **Codex** (CLI) | Supported | Full hook integration (SessionStart, UserPromptSubmit, Stop), usage tracking |
| **Codex Desktop App** | Supported | Hook integration + app-server JSON-RPC for real-time thread/turn lifecycle. Precise conversation jump via `codex://threads/<id>` deep-link |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format |
| **Qwen Code** | Supported | Claude Code fork — same hook format |
| **Factory** | Supported | Claude Code fork — same hook format |
| **CodeBuddy** | Supported | Claude Code fork — same hook format |
| **Cursor** | Supported | Hook integration via `~/.cursor/hooks.json`, session tracking, workspace jump-back |
| **Gemini CLI** | Supported | Hook integration via `~/.gemini/settings.json`, session tracking, fire-and-forget events |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]`, session tracking, permission flow |

### Terminals & IDEs

| Terminal / IDE | Support Level | Description |
|---|---|---|
| **Terminal.app** | Full | Jump-back with TTY targeting |
| **Ghostty** | Full | Jump-back with ID matching |
| **cmux** | **Native** | Reply-from-notch without tmux backend, direct AppleScript injection |
| **Kaku** | Full | Jump-back via CLI pane targeting |
| **WezTerm** | Full | Jump-back via CLI pane targeting |
| **iTerm2** | Full | Jump-back with session ID / TTY matching |
| **tmux** (multiplexer) | Full | Jump-back with session/window/pane targeting |
| **Zellij** | Full | Jump-back via CLI pane/tab targeting |
| **Warp** | Full | Precision tab jump via SQLite pane lookup + AX menu click |
| **VS Code** | Workspace | Activate workspace via `code` CLI |
| **Cursor** | Workspace | Activate workspace via `cursor` CLI |
| **Windsurf** | Workspace | Activate workspace via `windsurf` CLI |
| **Trae** | Workspace | Activate workspace via `trae` CLI |
| **JetBrains IDEs** | Workspace | IDEA, WebStorm, PyCharm, GoLand, CLion, RubyMine, PhpStorm, Rider, RustRover |

</details>

---

## Quick Start

### Build from source

```bash
git clone https://github.com/h4ckm1n-dev/atoll.git
cd atoll
zsh scripts/launch-dev-app.sh
```

That builds the app, copies it to `~/Applications/Atoll Dev.app`, signs it locally, and launches it. Hook installation is managed from the **Control Center** inside the app.

Run the same local verification path as CI with:

```bash
zsh scripts/harness.sh ci
```

> **Requirements**: macOS 14+, Swift 6.2, Xcode 16+

---

## Heritage & Vision

Atoll's code lineage traces back to [Open Island](https://github.com/Octane0411/open-vibe-island) by [@Octane0411](https://github.com/Octane0411), inspired by the original [Vibe Island](https://vibeisland.app/). 

Atoll was born from a fork in May 2026 to push the boundaries of what a local-first agent control surface could be. Since then, it has evolved into a comprehensive ecosystem featuring:
- A sophisticated **theming engine** and registry.
- **Mobile connectivity** for Apple Watch and iPhone.
- Deep **Git and Media** integrations.
- Advanced **developer-centric UX** like plan checklists and inline diffs.

While we share the foundation of the bridge/hook architecture with Open Island, Atoll is a distinct product focused on the "Pro" developer experience, high-end aesthetics, and multi-device interaction.

---

## Copyright & License

Copyright © 2026 Atoll Contributors.

Atoll is **free software**: you can redistribute it and/or modify it under the terms of the **GNU General Public License version 3** (GPL-3.0) as published by the Free Software Foundation. The full license text lives in [LICENSE](LICENSE).

---

<p align="center">
  <em>🌴 Built late at night with a coding agent and a fresh coconut.</em>
</p>
