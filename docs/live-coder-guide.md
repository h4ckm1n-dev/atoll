# Live Coder Guide

Atoll can be used as a small production desk for live coding: it keeps agent
state visible, hides sensitive text, lets you approve or deny requests quickly,
and exposes local actions that can be bound to hardware keys or launchers.

## One-Minute Setup

1. Open **Settings > Setup**.
2. Use **Creator Quick Start** and click **Apply Stream Setup**.
3. Install hooks for the agents you use.
4. Paste the copied OBS URL into an OBS Browser Source.
5. Click **Copy Action URLs** and bind the URLs in Raycast, Stream Deck, or any
   launcher that can run `open`.

## Recommended Stream Controls

| Control | URL |
|---|---|
| Toggle island | `atoll://action/toggle-overlay` |
| Next pending request | `atoll://action/cycle-attention-session` |
| Jump to focused session | `atoll://action/jump-focused-session` |
| Approve focused permission | `atoll://action/approve-focused-permission` |
| Deny focused permission | `atoll://action/deny-focused-permission` |
| Toggle Live Coding Mode | `atoll://action/toggle-live-coding` |
| Copy OBS overlay URL | `atoll://action/copy-stream-overlay-url` |

## Stream-Safe Surfaces

- **Live Coding Mode** redacts visible paths, secrets, emails, tokens, and noisy
  diffs before text reaches stream-facing UI.
- **OBS overlay** binds to `127.0.0.1`, so it is meant for local browser-source
  use and does not expose a public network endpoint.
- **Approval cockpit** collects pending approvals and questions in one place,
  which is useful when multiple agents are running during a stream.
- **Session timeline** gives you a lightweight narration trail for starts,
  tools, approvals, questions, and completions.

## Going Live

Before starting a public session, confirm:

- Creator Quick Start shows Live Coding Mode and OBS overlay as ready.
- OBS Browser Source points at `http://127.0.0.1:47619/overlay`.
- Your launcher buttons use the `atoll://action/...` URLs you expect.
- Hooks are installed only for the agents you actually plan to show.
