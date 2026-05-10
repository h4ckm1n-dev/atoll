# Automation Actions

Atoll exposes local URL actions for Raycast, Stream Deck, shell scripts, and
other launchers that can run `open`.

Use:

```bash
open "atoll://action/toggle-overlay"
```

The app also accepts the `openisland://` and `open-island://` scheme aliases.
Settings > Setup > Creator Quick Start can copy the OBS overlay URL and a
ready-to-paste action URL list.

## Actions

| Action | URL |
|---|---|
| Toggle island overlay | `atoll://action/toggle-overlay` |
| Show island overlay | `atoll://action/show-overlay` |
| Hide island overlay | `atoll://action/hide-overlay` |
| Jump to focused session | `atoll://action/jump-focused-session` |
| Approve focused permission | `atoll://action/approve-focused-permission` |
| Deny focused permission | `atoll://action/deny-focused-permission` |
| Cycle to next pending approval/question | `atoll://action/cycle-attention-session` |
| Open Settings | `atoll://action/show-settings` |
| Open Control Center | `atoll://action/show-control-center` |
| Toggle Live Coding Mode | `atoll://action/toggle-live-coding` |
| Start stream overlay endpoint | `atoll://action/start-stream-overlay` |
| Stop stream overlay endpoint | `atoll://action/stop-stream-overlay` |
| Copy stream overlay URL | `atoll://action/copy-stream-overlay-url` |

## Raycast

Create a Script Command that runs:

```bash
#!/bin/zsh
open "atoll://action/cycle-attention-session"
```

## Stream Deck

Use a System > Open action with the URL directly, or a System > Run Shell
Script action with:

```bash
open "atoll://action/toggle-live-coding"
```
