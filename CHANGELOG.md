# Changelog

## 0.1.0 — 2026-09-26

First release.

- Notch island that grows out of the hardware notch (or a virtual notch on other displays): state orb,
  per-session dots, blooms on *needs you* / *done* / *error*, hover for every session, click to return.
- Notifications with synthesized chimes, suppressed while you're in the agent's app and for short turns;
  withdrawn once resolved.
- Menu bar status with the session list, quiet modes and a demo.
- Dock glow in the color of the agents' state, with an edge light when the Dock auto-hides and a glow
  behind the Dock's glass with Accessibility access.
- Claude Code, Codex and Gemini CLI support through background hooks; a safe, reversible installer that
  preserves other hooks, key order, symlinks and permissions, with backups.
- `ambient` CLI: install, uninstall, status, doctor, emit, demo, ack.
- Sessions survive app restarts; sessions whose agent exits are cleaned up automatically.
