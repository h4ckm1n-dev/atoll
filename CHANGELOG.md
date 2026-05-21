# Changelog

All notable changes to Atoll are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/); versioning follows [Semantic Versioning](https://semver.org/).

---

## Unreleased

### Fixes

- fix(update): surface newer GitHub releases in Settings even when the Sparkle appcast is stale, and fall back to the release download page when Sparkle cannot install directly.
- fix(release): use monotonic git-count build numbers for Sparkle, require `SPARKLE_EDDSA_KEY` before publishing, and generate Atoll appcast URLs instead of stale Open Island URLs.

---

## v1.5.0

Release pipeline plumbing — no user-facing app changes. Closes the `GITHUB_TOKEN` chaining gap that prevented auto-tagged releases from triggering the DMG build.

### Changes since v1.4.0

#### Features

- feat(release): dual-trigger on tag push and Auto-tag workflow_run (#61) — release.yml now listens for both `push: tags: v*` (human tag pushes) and `workflow_run: ["Auto-tag"]` (bot-pushed tags). The default `GITHUB_TOKEN` cannot fire downstream workflows on tag push by design, so bot-pushed tags from `auto-tag.yml` were silently not triggering release.yml. The `workflow_run` path bridges that gap. Includes idempotency (skip if release already exists) and concurrency-by-SHA to prevent races.

#### Fixes

- fix(release): pass empty `ATOLL_SIGN_IDENTITY` when cert is not imported (folded into #61) — without this, `codesign` failed with `no identity found` whenever the signing identity name was set as a secret but the `.p12` cert wasn't. Now the two related secrets vary together as one unit.

---

## v1.4.0

Release pipeline plumbing — no user-facing app changes. Adds conventional-commit-driven auto-tagging on every push to main, and makes the existing release workflow actually buildable for the first time post-`OpenIsland → Atoll` rename.

### Changes since v1.3.0

#### Features

- feat: auto-tag main on conventional-commit pushes (#58) — new `.github/workflows/auto-tag.yml`. Walks commits since the last `v*` tag, derives bump type (`BREAKING` → major, `feat` → minor, `fix` → patch, `chore`/`docs`/`refactor` skipped), and pushes the next `vX.Y.Z` tag. `[skip release]` in a commit subject opts out. Bot-authored commits are filtered to avoid release loops.

#### Fixes

- fix(release): best-effort signing and subject-only auto-tag skip (#59) — release.yml was broken in five overlapping ways since the Atoll rename: passed `OPEN_ISLAND_*` env vars (script reads `ATOLL_*`); verified `Contents/MacOS/OpenIslandApp` (script builds `AtollApp`); hard-coded `Open Island.app/.dmg/.zip` paths (script writes `Atoll.*`); used a stale keychain notary profile; and required signing secrets that were never configured. Now: signing is gated on cert presence, env vars and artifact names match the script, and the workflow ships an ad-hoc-signed unsigned DMG when secrets are absent. Also moved the auto-tag `[skip release]` check into a shell step that matches only the commit subject (not the body), fixing a self-skip when PR bodies documented the marker.
- fix(auto-tag): move regexes into variables to avoid bash conditional-expression parser (#60) — inline regexes containing nested escaped parens (`^[a-z]+(\([^)]*\))?\!:`) crashed bash's `[[ =~ ]]` parser with `syntax error: unexpected token ')'` before the regex engine even ran. Moving each pattern into a variable bypasses the conditional parser. Verified across 10 conventional-commit shapes.

#### Maintenance

- chore(deps): Update actions/checkout action to v6 (#56)

---

## v1.3.0

Branch-aware island badge, refined session glass cards with collapse-by-default for completed plans, refreshed installer artwork, and a checked-in changelog as the release source of truth.

### Changes since v1.2.0-atoll

#### Features

- feat: branch-aware diff scope for island badge (#52)
- feat(settings): expandable update card with GitHub changelog (#49)
- feat: polish session glass cards (cae4358)

#### Fixes

- fix: collapse completed plan cards by default (#53)
- fix: tune liquid glass contrast (8abd504)

#### Reverts

- revert: restore pre-session-glass state (0ba0133)

#### Maintenance

- chore: refresh dmg-background brand assets (#54)
- chore(deps): Update dependency sparkle-project/Sparkle to from: "2.9.2" (#51)
- chore(deps): Update dependency argmaxinc/argmax-oss-swift to v1 (#47)
- chore: cut v1.3.0 — activate release workflow and add bilingual changelog (#55)
- chore: prepare v1.3.0 release (268c875)

---

## Installation

1. Download **Atoll.dmg**, open it, and drag **Atoll** to **Applications**.
2. Requires **macOS 14+**. Supports both **Apple Silicon** and **Intel** Macs.

> This build is signed and notarized with an Apple Developer ID. It opens without Gatekeeper warnings.
