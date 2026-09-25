# Contributing

Thanks for helping make agents easier to live with.

## Development

```bash
swift test                    # fast, no app needed
scripts/build-app.sh --run    # build and relaunch build/Ambient.app
~/.ambient/bin/ambient demo   # drive every state
```

- Put logic in `AmbientCore` with tests (Swift Testing). The app target should only render decisions the
  core makes — see `Policy.swift`.
- The `ambient hook` path runs on every agent event. Keep it free of work beyond parsing and one socket
  write, and keep it silent on stdout (Gemini expects `{}` there).
- Never send prompt text or tool output over the socket; add fields only when a surface needs them, and
  truncate them.
- Adding an agent: write an adapter in `Sources/AmbientCore/Adapters`, an `AgentHookSpec` in
  `HookInstaller.swift`, fixtures in `AdapterTests.swift`, and a row in the README.

## Pull requests

Keep changes focused, describe what you verified (tests, and for UI a screenshot), and update the
CHANGELOG under an *Unreleased* heading.
