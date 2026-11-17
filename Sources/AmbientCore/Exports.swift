// While AmbientCore is split into modules (docs/superpowers/specs/2026-11-13-modular-packages-design.md), it re-exports
// the ones taken out of it, so the app, the CLI and the voice helper keep compiling unchanged. Phase 4 removes this,
// and each of them then imports the modules it uses.
@_exported import AmbientBase
@_exported import AmbientContracts
