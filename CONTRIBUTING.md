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

## CI and releases

| Workflow | Runs on | Does |
| --- | --- | --- |
| **CI** | pushes to `main`, pull requests (not site/docs/marketing-only changes) | tests, universal build, CLI smoke test, site version check |
| **Release** | `v*` tags | checks tag, changelog and secrets → builds, signs, notarizes → publishes the GitHub release → deploys yaml.cafe |
| **Deploy site** | site changes on `main`, after a release, or by hand | deploys yaml.cafe with the published DMG and checks the live download's checksum |

To release: add a `## x.y.z — YYYY-MM-DD` section to `CHANGELOG.md`, then

```bash
scripts/cut-release.sh x.y.z --dry-run   # what would change
scripts/cut-release.sh x.y.z             # bump everywhere, commit, tag, push
```

The pipeline does the rest. It needs these repository secrets, set once with `scripts/setup-ci-secrets.sh`:
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` (the Developer ID certificate),
`NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (an App Store Connect API key) and
`NETLIFY_AUTH_TOKEN`. A local release still works without CI: `NOTARY_PROFILE=… scripts/release.sh`,
then `scripts/deploy-site.sh --prod`.
