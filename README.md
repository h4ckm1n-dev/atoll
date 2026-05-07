<p align="center">
  <img src="Assets/Brand/atoll-app-icon.png" alt="Atoll" width="128" height="128">
</p>

<h1 align="center">Atoll</h1>

<p align="center">
  <strong>A ring of native macOS goodness wrapping your Mac's notch.</strong>
  <br>
  Open-source, local-first companion for AI coding agents — themed, personalized, and fully under your control.
  <br><br>
  <a href="README.zh-CN.md">中文</a> | <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases/latest"><img src="https://img.shields.io/github/v/release/h4ckm1n-dev/atoll?style=flat-square&label=release&color=blue" alt="Latest Release"></a>
  <a href="https://github.com/h4ckm1n-dev/atoll/stargazers"><img src="https://img.shields.io/github/stars/h4ckm1n-dev/atoll?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="License: GPL v3"></a>
  <a href="#fork-of-open-island"><img src="https://img.shields.io/badge/fork-of%20Open%20Island-orange?style=flat-square" alt="Fork of Open Island"></a>
</p>

<p align="center">
  <a href="https://github.com/h4ckm1n-dev/atoll/releases">Download</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#whats-new-in-atoll">What's New</a> ·
  <a href="docs/plans/2026-05-06-theme-personalization-design.md">Roadmap</a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Atoll in action" width="720">
</p>

---

## What is Atoll?

**Atoll** sits in your Mac's **notch** (or the top-center bar on non-notch displays) and gives you a real-time, theme-aware control surface for your AI coding agents — session status, permission approvals, inline diff previews, plan-mode checklists, and one-click jump-back to the right terminal. All of it native, all of it local, all of it yours to mod.

The name comes from the geometry: a thin ring of land around a calm lagoon — exactly the shape of the panel that wraps your notch, with the agent activity surfacing through it like fish through reef water.

> *Imagine your AI coding agents as a coral ecosystem. The atoll is what you live on.*

## Fork of Open Island

Atoll is a friendly fork of [Open Island](https://github.com/Octane0411/open-vibe-island) (originally inspired by [Vibe Island](https://vibeisland.app/)). Upstream stewardship has been slow on merging substantial personalization and theming work, so this fork ships those features now under a distinct identity. Full attribution to the upstream maintainers — they built the foundation we extend here. License remains GPL v3.

## What's New in Atoll

These are the things Atoll ships that the upstream does not (yet):

### Catppuccin theme system
Full **System / Latte / Frappé / Macchiato / Mocha** flavors propagated across the entire panel — surface, recessed cards, agent indicators, attention badges, completion banners, plan checklists, prompt cards, Yes/No/Always Allow buttons, syntax highlighting in inline diffs. Switch flavors live from **Settings → Appearance**; the panel retints instantly. Latte is a real working light theme, not "dark with light accents".

The Mocha flavor's deep tones are tinted toward **blue-teal** rather than canonical Catppuccin's purple-grey, so the panel reads as a calm ocean-night that matches the atoll metaphor. Accent colors stay on Catppuccin spec for cross-app muscle memory.

> **Coming next**: import/export custom themes as JSON, plus an in-app 26-color picker editor with live preview. See `docs/plans/2026-05-06-theme-personalization-design.md`.

### Inline diff in approval cards
When an agent asks to write or edit a file, Atoll renders the **actual diff** inline in the approval card — Myers algorithm, lightweight syntax highlighting (Swift / TS / JS / Python / shell / etc.), palette-driven add/remove colors. You see exactly what's about to change before you click Yes. Hardened against agent-side spoofing — the diff comes from the tool payload, not the agent's narrative.

### Plan mode
Atoll captures plan-mode plans from skill-driven `Write` events, parses them with a structured `PlanModeParser`, and renders them as:
- A **read-only review block** in the approval card so you can scan the plan before granting permission
- A **post-approval interactive checklist** the agent ticks off as it executes — collapsible, scrollable, persisted across launches via `PlanModeRegistry`

### Notch personalization
- **Project colors** — each project (workspace path) gets a stable hash-derived tint, with a swatch picker in **Settings → Appearance** to override per project. Persisted to `~/Library/Application Support/Atoll/project-colors.json`.
- **Ambient theme overlay** — the project tint subtly bleeds into the panel surface (opacity-controlled) so glancing at the notch tells you which project is active without reading text.
- **Notch widgets** — extensible widget kinds for the closed-state idle bar (`NotchWidgetKind` infrastructure ready for clock / battery / agent-count / project-tint chips).

### Coconut tree menu bar icon
The menu bar icon is now a custom SwiftUI-drawn island with a coconut palm — static `Path` shapes (not `Canvas`, learned the hard way after a 100% CPU SwiftUI invalidation loop) tinted via macOS template style so it picks up dark/light/active states automatically.

### cmux native support (no tmux required)
Reply-from-notch into [cmux](https://github.com/saghul/cmux) sessions without a tmux backend — direct AppleScript text injection with main-thread guarantees and frontmost-window handling.

### Layered Catppuccin depth
Panel surface uses `palette.mantle` (second-deepest tone) while session cards use `palette.crust` (deepest). The result is the classic Catppuccin recessed-card layering — cards visibly "sink" below the panel surrounding them on every flavor instead of blending into one flat sheet.

### Architecture niceties
- **`@Environment(\.themePalette)`** — palette flows automatically through every SwiftUI view via the Environment, with a `ThemedHostingRoot` wrapper that re-injects on every theme switch so AppKit-hosted views (overlay panel, control center) retint live without window rebuilds.
- **`palette.role(_:)`** — a small semantic API (`.warning`, `.danger`, `.success`, `.working`, `.attention`, `.question`, `.completion`) so call sites name *intent* over *color*.

## Why Atoll?

- **Open source** — GPL v3, fork it, mod it, ship your own version (we did 🌴)
- **Local-first** — No server, no telemetry, no account. Everything runs on your Mac
- **Native macOS** — SwiftUI + AppKit, not an Electron wrapper
- **Themed end-to-end** — Pick Catppuccin, get Catppuccin everywhere, including the diff colors
- **Multi-agent** — One surface for Claude Code, Codex, Cursor, Gemini CLI, OpenCode, and more
- **Multi-terminal** — Jump back to the exact terminal/IDE session in one click

## Supported Agents & Terminals

**11 agents**: Claude Code, Codex, Codex Desktop App, Cursor, Gemini CLI, Kimi CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy

**15+ terminals & IDEs**: Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, **cmux (native)**, Kaku, Warp, VS Code, Cursor, Windsurf, Trae, JetBrains IDEs (IDEA, WebStorm, PyCharm, GoLand, CLion, RubyMine, PhpStorm, Rider, RustRover)

<details>
<summary>Full compatibility table</summary>

### Code Agents

| Agent | Status | Description |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking, plan-mode capture |
| **Codex** (CLI) | Supported | Full hook integration (SessionStart, UserPromptSubmit, Stop), usage tracking |
| **Codex Desktop App** | Supported | Hook integration + app-server JSON-RPC for real-time thread/turn lifecycle. Precise conversation jump via `codex://threads/<id>` deep-link |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format, config at `~/.qoder/settings.json` |
| **Qwen Code** | Supported | Claude Code fork — same hook format, config at `~/.qwen/settings.json` |
| **Factory** | Supported | Claude Code fork — same hook format, config at `~/.factory/settings.json` |
| **CodeBuddy** | Supported | Claude Code fork — same hook format, config at `~/.codebuddy/settings.json` |
| **Cursor** | Supported | Hook integration via `~/.cursor/hooks.json`, session tracking, workspace jump-back |
| **Gemini CLI** | Supported | Hook integration via `~/.gemini/settings.json`, session tracking, fire-and-forget events |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]`, session tracking, permission flow (reuses Claude payload) |

### Terminals & IDEs

| Terminal / IDE | Support Level | Description |
|---|---|---|
| **Terminal.app** | Full | Jump-back with TTY targeting |
| **Ghostty** | Full | Jump-back with ID matching |
| **cmux** | **Native** | Reply-from-notch without tmux backend, direct AppleScript injection on main thread |
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

### Other Features

| Feature | Description |
|---|---|
| Notch / top-bar overlay | Notch area on notch Macs, top-center bar on others |
| Control center | Hook status, usage dashboard, theme picker, project colors |
| Notification mode | Auto-height panel for permission requests and session events |
| Notification sounds | Configurable system sounds, mute toggle |
| Inline diff preview | Myers diff + lightweight syntax highlighting in approval cards |
| Plan mode | Pre-approval review + post-approval interactive checklist |
| Catppuccin themes | System / Latte / Frappé / Macchiato / Mocha (Mocha tinted blue-teal) |
| Project colors | Hash-derived per-project tint with override picker |
| Ambient theme overlay | Project tint bleeds into panel surface (opacity-controlled) |
| i18n | English, Simplified Chinese, Traditional Chinese |
| Session discovery | Auto-discover from local transcripts, persist across launches |
| Auto-update | Sparkle-based automatic updates |
| Signed & notarized | DMG packaging with Apple notarization |

</details>

## Quick Start

### Option 1: Download

Grab the latest DMG from [GitHub Releases](https://github.com/h4ckm1n-dev/atoll/releases) — signed and notarized, ready to run.

### Option 2: Build from source

```bash
git clone https://github.com/h4ckm1n-dev/atoll.git
cd atoll
open Package.swift   # Opens in Xcode — hit Run
```

On first launch, Atoll auto-discovers your active agent sessions and starts the live bridge. Hook installation is managed from the **Control Center** inside the app.

> **Requirements**: macOS 14+, Swift 6.2, Xcode 16+

## How It Works

```
Agent (Claude Code / Codex / Cursor / cmux / ...)
  ↓ hook event
AtollHooks CLI (stdin → Unix socket)
  ↓ JSON envelope
BridgeServer (in-app)
  ↓ state update
Notch overlay UI ← retinted by your active palette ← you see it here
  ↓ click
Jump back → correct terminal / IDE / cmux pane
```

Hooks **fail open** — if Atoll isn't running, your agents continue unaffected.

<details>
<summary>Architecture details</summary>

Four targets in one Swift package:

| Target | Role |
|---|---|
| **OpenIslandApp** | SwiftUI + AppKit shell — menu bar, overlay panel, control center, settings, theme manager |
| **OpenIslandCore** | Shared library — models, bridge transport (Unix socket IPC), hooks, session persistence, theme palette, plan-mode parser, Myers diff |
| **OpenIslandHooks** | Lightweight CLI invoked by agent hooks, forwards payloads via Unix socket |
| **OpenIslandSetup** | Installer CLI for managing `~/.codex/config.toml` and hook entries |

> *The Swift package + bundle ID were renamed to **Atoll** in v1.0; some source file names still carry the legacy `OpenIsland*` prefix (e.g. `OpenIslandApp.swift`) — file/type renames are a deferred cosmetic pass.*

See [docs/index.md](docs/index.md) for the full doc map (architecture, hooks, theme personalization plans, etc.) and run [`scripts/harness.sh`](scripts/harness.sh) for the local CI pipeline (`lint` / `docs` / `test` / `build` / `smoke`).

</details>

## Theming

Atoll ships five flavors out of the box:

| Flavor | Vibe | Best for |
|---|---|---|
| **System** | The pre-rebrand black-and-grays look | Users who don't want the rebrand |
| **Catppuccin Latte** | Warm cream with dark text | Daylight, sun-on-screen sessions |
| **Catppuccin Frappé** | Soft dusk-blue | Late-afternoon focus |
| **Catppuccin Macchiato** | Deeper night-blue | Evening sessions |
| **Catppuccin Mocha** | Tinted blue-teal (deeper than canonical Catppuccin) | Default · ocean-night for long sessions |

Switch from **Settings → Appearance**. The panel retints live — surfaces, accents, attention indicators, completion banners, prompt cards, Yes/No/Always Allow buttons, plan checklists, inline diffs, syntax highlighting, project-color overlays.

The full color taxonomy is the standard Catppuccin 26-field palette: 6 surfaces (base / mantle / crust / surface 0–2) + 6 foregrounds (text / subtext 0–1 / overlay 0–2) + 14 accents (rosewater, flamingo, pink, mauve, red, maroon, peach, yellow, green, teal, sky, sapphire, blue, lavender). Views read it via either an explicit `palette:` parameter or `@Environment(\.themePalette)`.

A semantic role API (`palette.role(.warning / .danger / .success / .working / .attention / .question / .completion)`) lets call sites name intent rather than literal color, so a future palette tweak doesn't require a code sweep.

**Coming in v1.1**: custom themes — fork-from-preset + 26-picker editor + JSON import/export. Design at `docs/plans/2026-05-06-theme-personalization-design.md`.

## Roadmap

- [x] Catppuccin theme system
- [x] Inline diff preview in approval cards
- [x] Plan-mode capture + interactive checklist
- [x] Project colors + ambient theme overlay
- [x] cmux native support
- [x] Coconut palm menu bar icon
- [x] Layered card depth (mantle/crust)
- [ ] **Phase 2**: custom theme registry (JSON import/export, library UI)
- [ ] **Phase 3**: in-app 26-picker theme editor with live preview
- [ ] Notch widget kinds (clock / battery / agent count chips)
- [ ] Translucent material panel option (`.ultraThinMaterial`)
- [ ] Per-agent UI density preference

## Community

Issues, pull requests, and feature ideas welcome. We're a small fork — be patient with response times, but real maintainers (👋) are reading.

We welcome new contributors. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## Report a Bug via Your Code Agent

Copy this prompt into your agent (Claude Code, Codex, etc.) to auto-generate a well-structured issue:

<details>
<summary>Click to expand</summary>

```
I'm having an issue with Atoll (https://github.com/h4ckm1n-dev/atoll).

Please help me file a GitHub issue. Do the following:

1. Collect my environment info:
   - Run `sw_vers` to get macOS version
   - Run `swift --version` to get Swift version
   - Check if Atoll is running: `ps aux | grep -iE "atoll|OpenIslandApp" | grep -v grep`
   - Get the app version: `defaults read ~/Applications/Atoll.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || defaults read ~/Applications/Open\ Island\ Dev.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown"`
   - Check which terminal I'm using
   - Note which Catppuccin flavor I have selected (Settings → Appearance)

2. Ask me to describe:
   - What I expected to happen
   - What actually happened
   - Steps to reproduce

3. Create the issue on GitHub using `gh issue create` with this format:
   - Title: concise summary
   - Body with sections: **Environment** (incl. theme), **Description**, **Steps to Reproduce**, **Expected vs Actual Behavior**
   - Add label "bug" if applicable

Repository: h4ckm1n-dev/atoll
```

</details>

## Credits

- **Upstream foundation**: [Open Island](https://github.com/Octane0411/open-vibe-island) by [@Octane0411](https://github.com/Octane0411) and contributors — the entire bridge / hooks / session-discovery / control-center machinery is theirs. Atoll layers personalization, theming, and richer agent-interaction UI on top.
- **Visual inspiration**: [Vibe Island](https://vibeisland.app/) — the closed-source product the open-source line traces its DNA from.
- **Color system**: [Catppuccin](https://github.com/catppuccin/catppuccin) — the soothing pastel palette the theme system is built on.
- **The vibe**: every coding agent that ever asked "Allow this command? (y/n)" at 2 AM and made you wish there was a calmer way to answer.

## License

GPL v3 — same as upstream. Fork it, mod it, ship your own. If you do, drop a link in a GitHub issue here so we can cross-reference each other's work.

---

<p align="center">
  <em>Built late at night with a coding agent and a fresh coconut. 🌴</em>
</p>
