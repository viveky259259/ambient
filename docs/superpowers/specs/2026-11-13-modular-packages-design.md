# Modular packages: AmbientCore as libraries anyone can use, joined by contracts

Date: 2026-11-13
Revised: 2026-11-14, with the decisions at the end; 2026-11-15, with what phase 1 found.
Status: phase 1 built on `refactor/modular-phase-1`, from `main` at `999cda6`. The dependency analysis is from `main`
at `86c1785` (2026-11-12).

## Problem

`AmbientCore` is one 12,300-line module. Its folders suggest features (`Remote/`, `Speech/`, `Memory/`, `LocalAgent/`),
but nothing enforces them, and they already reach into each other:

- `Session` holds `RemoteOrigin` from `Remote/`, while `Remote/` takes `Session`.
- `Remote/` and `VoiceSync/` use each other's types in both directions.
- `RemotePurge` in `Remote/` rewrites `StateFile`, `TaskFile` and `DayLogFile` directly.
- `TaskStore` takes `TaskSemantics` from `LocalAgent/`, and `LocalAgent/` takes `TaskStatus` from `Task.swift`.
- `Memory/` reaches into `SessionStore` for `processExists`.
- `Install/` and `HookHealth` use each other's types.

So no part of Core can be used without the rest of it. Someone who only wants to turn Claude Code, Codex or Gemini hook
payloads into events has to take the remote transport, the local model runner and the wallpaper scenes too. The voice
helper in `Voice/` uses only `VoiceWire`, yet it links all of `AmbientCore`.

## Goals

1. Every public module works on its own: another Swift package can add it and use it without the rest of Ambient.
2. Modules talk only through one shared contract, `AmbientContracts`, and the compiler enforces that.
3. Every public API, and every format that crosses a process boundary or is saved to disk, is a versioned contract
   that CI checks.
4. No change in behavior or file formats, and no big-bang rewrite. Each phase ships on its own.

## Non-goals

- Splitting `AmbientApp`. It is the composition root and stays one target until Core is modular.
- Separate repositories, or a separate version per module (see "Shipping").
- New features.

## Shipping: one package, many products

Nine modules are library **products** of the root `Package.swift`: `AmbientBase`, `AmbientContracts`,
`AmbientAgents`, `AmbientSpeech`, `AmbientMemory`, `AmbientLocalAgent`, `AmbientRemote`, `AmbientScene` and
`AmbientCore`. Another package uses one like this:

```swift
.package(url: "https://github.com/viveky259259/ambient", .upToNextMinor(from: "0.9.0")),
// ...
.product(name: "AmbientAgents", package: "ambient")
```

Then SwiftPM builds only `AmbientAgents` and what it depends on. `Voice/Package.swift` already uses Ambient this way
(by local path), taking `AmbientCore` as a product.

Two modules are **internal** targets, not products: `AmbientState` and `AmbientInstall`. They are shaped around
Ambient's own app and its own hook layout, so they can change freely. Other packages can't depend on them.

Why not one `Package.swift` per module under a `Packages/` folder: SwiftPM can depend on a git repository only through
a `Package.swift` at the repository root. Packages in subfolders could be used by local path, but not by URL. If a
module ever needs its own release cycle, it moves to its own repository; until then, all modules share Ambient's
version number.

## Layers and the dependency rule

```
Composition      ambient (CLI) · AmbientApp · ambient-voice (uses AmbientSpeech only)
Internal         AmbientState · AmbientInstall
Public, top      AmbientCore (Wire)
Public features  AmbientAgents · AmbientSpeech · AmbientMemory · AmbientLocalAgent · AmbientRemote · AmbientScene
Public, shared   AmbientContracts
                 AmbientBase
```

A module may use the layers below it, within these **rules**:

1. A public feature depends only on `AmbientBase` and `AmbientContracts`, never on another feature.
2. `AmbientCore` may depend on public features.
3. An internal module may depend on any public module.
4. No public module depends on an internal one. (`AmbientCore`'s re-exports break this during the migration only.)

Modules that must cooperate do it through a protocol (a *port*) declared in `AmbientContracts`. One module implements
the port, and the composition root (the CLI or the app) hands that implementation to the other.

| Module | Kind | Contents (from today's `Sources/AmbientCore`) | Used on its own for |
|---|---|---|---|
| `AmbientBase` | public | `JSON/`, `Paths`, `Trim`, `UnixSocket`, `PerfLog`, `Version`, `SecretStore`, plus the helpers moved down (below) | JSON without Foundation's encoder, a Unix socket, Keychain access |
| `AmbientContracts` | public | Shared values and ports (next section) | Speaking Ambient's event and session vocabulary |
| `AmbientAgents` | public | `Adapters/`, `Host`, `Permissions` | Turning coding-agent hook payloads into events; answering permission prompts |
| `AmbientSpeech` | public | `Speech/` | Chunking text for TTS, voice packs, the voice helper protocol |
| `AmbientMemory` | public | `Memory/` | A shared, expiring memory store for agents |
| `AmbientLocalAgent` | public | `LocalAgent/` | Running a local model to summarize sessions |
| `AmbientRemote` | public | `Remote/`, `VoiceSync/` | Pairing machines and taking agent events from them safely |
| `AmbientScene` | public | `SceneState`, `ScenePolicy`, `DayLight`, `SolarLayout`, `Notch*`, `Wallpaper*`, `Pet/`, and `Policy.swift`'s `AlertPolicy`, `IslandPolicy`, `Palette`, `GlowStyle` | Deciding what to show for a set of sessions |
| `AmbientCore` | public | `Wire`, `Demo`, `FeatureRequests` | The CLI↔app protocol |
| `AmbientState` | internal | `SessionStore`, `TaskStore`, `TaskFile`, `StateFile`, `SessionTitles`, `DayLogFile`, `Focus` | — shaped around Ambient's app |
| `AmbientInstall` | internal | `Install/` (`HookInstaller`, `OpenCodePlugin`), `HookHealth` | — writes Ambient's own hook layout |

Two groups stay together on purpose:

- **`Remote/` and `VoiceSync/`** share one transport, one line format and one audit log in both directions. Splitting
  them would need a port for every call.
- **`Install/` and `HookHealth`** use each other's types (`InstallState`, `AgentRecord`). `AmbientInstall` uses
  `PermissionSettings` and `PermissionReply` from `AmbientAgents`, which rule 3 allows. Nothing in `AmbientAgents` uses
  the installer; `Adapters.swift` only names `OpenCodePlugin` in a comment.

## The contract: `AmbientContracts`

### What may go in

- Value types: `Sendable` and `Equatable`, and `Codable` when they are stored or sent.
- Protocols (ports).
- Pure functions over those values, such as `Describe`'s wording.

### What may not

- File or network I/O, file paths, singletons, global state.
- AppKit, SwiftUI or any other UI framework.
- Anything that only one module uses. It stays in that module.

A member that other Ambient modules need, but outside users shouldn't, uses `package` access: visible to every target
in this package, tests included, and to nothing else. `Session.beforeCompaction`, `Session.beforeWaiting`,
`Need.fromText` and `Need.named` are `package`, because `SessionStore`, the adapters and `RemoteEvent` use them.

### Shared values

Most of the contract is values that several modules already pass around. They move as they are; only their module
changes.

| Type | Today | Used across modules by |
|---|---|---|
| `AgentKind`, `AgentEvent`, `EventKind`, `HostInfo` | `Event.swift` | everyone |
| `Session`, `SessionChange`, `Activity`, `Mood` | `Session.swift` | everyone |
| `AgentTask`, `TaskStatus` | `Task.swift` | State, Scene, LocalAgent, Wire |
| `MachineRef`, `RemoteOrigin` | `Remote/Machine.swift` | `Session`, `AgentTask`, State |
| `RemoteCursor`, `RemoteDelivery` | `Remote/RemoteIngest.swift` | `SessionStore`, `StateFile` |
| `RemoteEvent` and its version constants | `Remote/RemoteEvent.swift` | `SessionStore.apply`; it is also the shim↔hub wire format. `RemoteEventDecoder` (the security boundary) and `redacted(to:)` stay in Remote, in `RemoteEventDecoder.swift` |
| `Need`, and `ToolNames`' naming tables | `Need.swift`, `Adapters/ToolNames.swift` | Remote, State, `Describe`. `Need`'s raw values are on the wire, in `RemoteEvent`'s `reason`. `ToolNames.detail(name:input:)` reads a `HookPayload`, so it stays in Agents as an extension |
| `Describe` | `Describe.swift` | LocalAgent, Scene, State |
| `TaskSemantics` | `LocalAgent/TaskLLM.swift` | LocalAgent makes it, `TaskStore` applies it |
| `DayLog`, `DayMark`, `DayMoment` | `DayLog.swift` (`DayLogFile` stays in State) | State writes them, `SceneState` reads them |
| `Mood.wantsAttention` (today `AlertPolicy.attentionMoods`) | `Policy.swift` | `SessionStore`, Scene, the app |

### Helpers that move down to `AmbientBase`

These are the remaining reasons one module reaches into another. Each one is a utility, not domain logic.

| Helper | Today | Used by |
|---|---|---|
| `URL.isLoopback` (today `TaskLLMConfig.isLoopback`) | LocalAgent | `RemoteEgress` |
| `ProcessProbe.isAlive(pid)` (today `SessionStore.processExists`) | State | Memory's default `isAlive` argument |
| `Trim.plainText` (today `RemoteEventDecoder.plainText`) | Remote | `TaskStore` |
| `TextLimits` (today the internal `Limits`) | Agents | `Need`, as well as the adapters. (`VoiceInbox` has a `Limits` of its own, which the first analysis mistook for this one.) |
| `RGB` | `Policy.swift` | `DayLight`, `Palette`, the app's colors |

### Ports

After those moves, only one module still calls another: `RemotePurge` deletes a machine's sessions, tasks and day
moments from State's files. `AmbientRemote` is public and `AmbientState` is internal, so rule 4 also forbids the
direct call. That becomes a port:

```swift
/// Something that keeps data a remote machine sent, and can forget it.
public protocol MachineDataHolder: Sendable {
    /// Drops the machine's sessions and cursors. `ambient remote remove`.
    func removeSessions(machine id: String) throws
    /// Drops everything the machine left: sessions, tasks, today's moments. `ambient remote purge`.
    func scrub(machine id: String) throws
}
```

`AmbientState` implements it as `StateFiles(paths:)`. `RemotePurge` takes `[any MachineDataHolder]` and still clears
its own voices and tombstones. The CLI's `remote remove` and `remote purge`, and the app's `RemoteCoordinator`, pass
`StateFiles(paths:)`.

New ports follow the same pattern: declare a protocol only when a module has to *call* another. Passing values between
modules doesn't need one.

## Contracts between processes

Three formats cross a process boundary or outlive one. They follow the rule `RemoteEvent` already uses: the format
carries a version, and the reader accepts the current version and the one before it.

| Format | Between | Version today | Change |
|---|---|---|---|
| `RemoteEvent` lines | `ambient-remote` shim ↔ hub | `v`, `supportedVersions = current-1...current` | None; this is the model |
| `StateFile`, `TaskFile` envelopes | app ↔ disk, across upgrades | `version = 1`, exact match | Accept the previous version once a v2 exists |
| `WireMessage` | `ambient` CLI ↔ app socket | none (only `pong(version:)`) | Add `v` before the first release that ships the products |

## Rules, enforced

1. **Dependencies are declared, not discovered.** Public features are declared through one helper in `Package.swift`,
   so adding a feature-to-feature dependency is a visible change to that helper. Internal modules list their
   dependencies explicitly.

   ```swift
   /// A public feature: it depends only on the shared layers.
   func feature(_ name: String, _ outside: [Target.Dependency] = []) -> Target {
       .target(name: name, dependencies: ["AmbientBase", "AmbientContracts"] + outside)
   }
   ```

   `outside` is for other packages only, never another Ambient module.
2. **Undeclared imports fail the build.** CI builds with
   `swift build --explicit-target-dependency-import-check error`, so a module can't import another module it doesn't
   declare, even if that one happens to be built first.
3. **Public APIs change by semantic versioning, and CI checks it.** Renaming or removing something comes after one
   release marked `@available(*, deprecated)`, and bumps the major version. While Ambient is 0.x, it bumps the minor
   version instead (0.9 → 0.10), and adding something bumps the patch. SwiftPM's plain `from: "0.9.0"` would accept
   0.10, so the README tells users to depend with `.upToNextMinor(from:)` until 1.0. CI runs
   `swift package diagnose-api-breaking-changes <last release tag>` on every PR. It compares only modules that are part
   of a library product, so `AmbientState` and `AmbientInstall` stay free to change. A deliberate break in a major
   release goes in the file passed as `--breakage-allowlist-path`, with the PR that explains it.
4. **Every stored or sent type has golden fixtures.** Each module's tests hold one file per format version for the
   formats that module owns, in `Tests/<Module>Tests/Fixtures/`:
   - `AmbientContractsTests`: every `Codable` type in `AmbientContracts` (`AgentKind`, `AgentEvent`, `EventKind`,
     `HostInfo`, `Session`, `Activity`, `Mood`, `AgentTask`, `TaskStatus`, `TaskSummarySource`, `MachineRef`,
     `RemoteOrigin`, `RemoteCursor`, `DayLog`, `DayMark`, `DayMoment`), and `Need`'s raw values, which remote lines
     carry;
   - `AmbientCoreTests`, until their modules exist: `RemoteEvent` lines, which only Remote's decoder reads;
     `WireMessage`; and the `StateFile`, `TaskFile` and `DayLogFile` envelopes.

   A released fixture is never edited. Changing a format adds a new fixture, and every fixture inside the supported
   versions must still decode. Each type's test also encodes a known value and compares the result to the newest
   fixture, so a field rename shows up in review rather than in a user's state file.
5. **One test target per module, with its own fakes.** `Tests/AmbientAgentsTests`, `Tests/AmbientRemoteTests`, …
   Each tests only that module's public API, plus `@testable` for its own internal types. A test that needs a port
   writes its own small fake; there is no shared testing library.

## Migration

Every phase leaves `swift build`, `swift test` and `scripts/build-app.sh` green and changes no behavior. Until the last
phase, `AmbientCore` re-exports every module (`@_exported import`), so the app, the CLI, `Voice/` and existing tests
keep compiling without edits. Each module becomes a product in the phase that creates it.

1. **Base and Contracts.** First, write the golden fixtures from today's code, before anything moves. They are what
   proves the move changed no format. Then create both targets and make the moves in the two tables above. This is
   where hidden links show up: the analysis counted type names, not extension methods or free functions, so the
   compiler may find a few more.

   *Done on `refactor/modular-phase-1`.* The fixtures were recorded from unmodified `main` and still pass after the
   move. Breaking one field in a fixture by hand fails both its encode and decode checks. No hidden links turned up
   beyond one test reaching `UnixSocketServer.serve`, now `package`. `IslandPolicy`, `Palette` and `GlowStyle` stay in
   `Policy.swift` until phase 3, since moving them within Core changes nothing. `Version.swift` moved to
   `AmbientBase`, so the release scripts and workflows read the version from there.
2. **The independent modules.** Extract `AmbientSpeech`, `AmbientAgents`, `AmbientMemory` and `AmbientLocalAgent` as
   public features, and `AmbientInstall` as an internal module, each with its own tests. Point `Voice/Package.swift`
   at `AmbientSpeech` alone: the voice helper uses only `VoiceWire`, so it becomes the first real outside user of a
   single module.
3. **The port, then Remote, State and Scene.** Add `MachineDataHolder` and `StateFiles`. Change `RemotePurge`, the CLI
   and `RemoteCoordinator` to use them. Extract `AmbientRemote` and `AmbientScene` as public features, and
   `AmbientState` as internal. `IslandPolicy`, `Palette`, `GlowStyle` and `AlertPolicy` move out of `Policy.swift`
   into `AmbientScene`.
4. **Finish.** Add `v` to `WireMessage`. Remove the re-exports; the app and the CLI import the modules they use. Turn on
   the import check. Document each product in the README. Ship the release, then turn on the API-breakage check with
   that release's tag as the first baseline. It starts here because, until then, moving a type out of `AmbientCore`
   would show up as a removal and the check would only be noise.

## Decisions (2026-11-14)

- **Public set:** all modules are products except `AmbientState` and `AmbientInstall`.
- **Installer:** split out of `AmbientAgents` into the internal `AmbientInstall`, together with `HookHealth`.
- **`AmbientState`:** internal.
- **Names:** keep the `Ambient` prefix.
- **Phases:** keep four.
- **Contract rules:** add the API-breakage check in CI; golden fixtures for every stored or sent type, not only the
  cross-process formats; no shared fakes library.

## Open question

- When do the libraries reach 1.0? Until then, every breaking change bumps the minor version, and users have to pin
  with `.upToNextMinor(from:)`. Shipping the first modular release as 1.0 would let them use plain `from:`, but it
  would also commit Ambient to the deprecation rule from day one.
