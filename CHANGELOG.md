# Changelog

All notable changes to Atoll are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/); versioning follows [Semantic Versioning](https://semver.org/).

---

## Unreleased

This update makes Atoll's updater feel honest again: Settings now shows the newest release when it exists, and gives you a clear path to get it instead of hiding behind a stale "no update" answer.

### Update Experience

- Settings now checks the public GitHub release line, so a newer Atoll release can still appear even if the Sparkle feed is behind.
- The in-app changelog now lives only in Settings, next to the update action, instead of floating over every settings page.
- Release notes shown inside Atoll are curated around user-facing improvements instead of raw commit text.
- When a one-click Sparkle install is not available, the primary action becomes a direct download path instead of a misleading update button.
- Version detection now understands Atoll's current release line, so future updates do not get blocked by old Open Island build numbers.

### Release Quality

- Release builds now use monotonic build numbers that Sparkle can compare correctly.
- The release pipeline now refuses to publish an auto-update release unless the Sparkle signing key is configured.
- The appcast generator now points to Atoll's real GitHub repo and `Atoll.zip` artifact.

---

## v1.5.0

Atoll's release train is now much harder to stall. This release focuses on getting new builds from `main` to a downloadable macOS app reliably, so users spend less time waiting for a DMG after features land.

### Changes since v1.4.0

### Release Experience

- New versions created by automation now trigger the macOS build pipeline automatically (#61).
- The release workflow avoids duplicate uploads, so the GitHub Releases page stays clean even when automation retries.
- Unsigned fallback builds can still be produced when Apple signing secrets are not configured, which keeps test builds moving instead of blocking the release entirely.

### Behind the Scenes

- The workflow now handles both human-created tags and automation-created tags.
- Signing inputs are treated as a matched set, preventing broken `codesign` attempts when only part of the Apple signing setup exists.

---

## v1.4.0

Atoll gained a more predictable release rhythm. Merged work can now turn into a versioned release with less manual coordination, making feature delivery faster and reducing broken release-day surprises.

### Changes since v1.3.0

### Release Experience

- Atoll can now create the next version tag automatically when meaningful product work lands on `main` (#58).
- Fixes, features, and breaking changes map to the right kind of version bump, which makes the release history easier to trust.
- The release path now uses Atoll names and artifacts throughout, so packages are built as `Atoll.app`, `Atoll.dmg`, and `Atoll.zip` instead of leaking old Open Island names (#59).

### Reliability

- The release workflow now degrades gracefully when signing is unavailable, so a missing certificate does not kill every build (#59).
- Release skipping is controlled by the commit title only, which prevents release notes or PR bodies from accidentally cancelling a release (#59).
- The auto-tag parser is more robust across common commit shapes (#60).
- The GitHub checkout action was updated to keep the pipeline current (#56).

---

## v1.3.0

Atoll became more useful at a glance. The island now gives better context about what changed, completed work takes less space, and Settings makes updates feel like part of the app instead of a trip through GitHub.

### Changes since v1.2.0-atoll

### Island Experience

- The island badge now understands your branch context, so the change count better reflects the work you are actually doing (#52).
- Session cards received a more polished glass treatment, making active coding context easier to scan without feeling heavy.
- Completed plan cards now collapse by default, keeping the island calm once work is done while still leaving progress visible (#53).

### Settings and Updates

- Settings now includes an expandable update card with release notes, so users can see what is new before updating (#49).
- Update details are presented in-app with the GitHub changelog available when more context is needed.

### Packaging and Polish

- The installer artwork was refreshed so the first-run install flow feels more like Atoll and less like a generic build artifact (#54).
- Sparkle and app dependencies were refreshed to keep the update and app runtime foundation current (#51, #47).
- The changelog is now checked into the repo as the source of truth for release storytelling (#55).
- A visual experiment was rolled back where it made the island less clear, keeping the app closer to its compact notch-first feel.

---

## Installation

1. Download **Atoll.dmg**, open it, and drag **Atoll** to **Applications**.
2. Requires **macOS 14+**. Supports both **Apple Silicon** and **Intel** Macs.

> This build is signed and notarized with an Apple Developer ID. It opens without Gatekeeper warnings.
