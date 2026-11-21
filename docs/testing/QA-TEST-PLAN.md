# Ambient QA Test Plan

Last updated 2026-11-21. This plan covers every target in `Sources/`, in dependency order:

| Package (SwiftPM target) | What it is | Test target | Swift mode |
|---|---|---|---|
| `AmbientBase` | utilities: paths, JSON, Unix socket, Trim, RGB, loopback, process probe, perf log, Keychain | `Tests/AmbientBaseTests` | 6 |
| `AmbientContracts` | the shared vocabulary on disk and on the wire: Session, Event, Need, Task, DayLog, Describe, ToolNames, remote events | `Tests/AmbientContractsTests` | 6 |
| `AmbientCore` | everything else in the libraries: session store, policies, installers, remote, memory, local LLM, speech, voice sync | `Tests/AmbientCoreTests` | 6 |
| `ambient` | the CLI: `install`, `status`, `task`, `memory`, `remote`, `emit`, `hook`, `mcp`… | `Tests/AmbientCLITests` | 6 |
| `AmbientApp` | the AppKit/SwiftUI menu-bar app | `Tests/AmbientAppTests` (new) | 5 |

## How to run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AmbientContractsTests
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --enable-code-coverage
```

- `DEVELOPER_DIR` is required on a Mac whose `xcode-select` points at the Command Line Tools. They lack the Swift Testing and SwiftUI macro plugins, and the build fails with errors that look like broken code.
- `AMBIENT_TEST_SSHD=1` makes the real-ssh remote test (`overARealSSHServer`) actually run.
- `AMBIENT_TEST_CRASHES=1` runs the eight exit tests that crash a child process (Describe durations, `Trim.truncate`, JSON nesting depth, and the socket starvation repro). They're off by default: each crash makes macOS write a crash report, and on CI's small runner that froze every test process for about 20 s, long enough for socket timeouts to fail.

Per-file coverage after a coverage run (each test target is its own bundle):

```bash
D=.build/out/Products/Debug; xcrun llvm-cov report $D/AmbientBaseTests.xctest/Contents/MacOS/AmbientBaseTests -object $D/AmbientContractsTests.xctest/Contents/MacOS/AmbientContractsTests -object $D/AmbientCoreTests.xctest/Contents/MacOS/AmbientCoreTests -object $D/AmbientCLITests.xctest/Contents/MacOS/AmbientCLITests -object $D/AmbientAppTests.xctest/Contents/MacOS/AmbientAppTests -instr-profile=$D/codecov/default.profdata -ignore-filename-regex='(Tests|\.build)/'
```

## Principles

1. **Hermetic.**
   - Every test gets its own temp home: a short `/tmp` path, because macOS caps Unix socket paths at 104 bytes.
   - Every test gets its own `UserDefaults(suiteName:)`.
   - Dates and calendars are fixed (UTC and named zones), never the machine's clock or zone.
   - Nothing touches the real `~/.ambient`, `UserDefaults.standard`, the login Keychain, or the network.
   - Tests run in parallel. Suites that share a socket are `.serialized`.
2. **Fakes at the boundary, real code inside.**
   - The CLI talks to a real Unix-socket server (`FakeAppSocket`) that replies like Ambient.app and records each request.
   - The HTTP clients (local-agent gateway, Anthropic bootstrap) talk to an in-process `URLProtocol` stub (`QAStubGateway`).
   - Installers write real files in a temp `~/.claude`.
3. **Contracts, not internals.**
   - The CLI's exit codes: 0 ok, 1 runtime failure, 64 usage error.
   - The exact request sent to the app.
   - Files written and their permissions.
   - Which JSON keys are required.
   - The view-model state that SwiftUI renders.
4. **Bugs stay visible.**
   - A test that exposes a product bug is kept and wrapped in `withKnownIssue`.
   - A bug that crashes the process is checked in an exit test (`#expect(processExitsWith:)`), so the crash can't take down the run.
   - The suite stays green, and every run reports each bug until it is fixed. Then the wrapper reports the issue is gone, and gets removed.
5. **Gaps come from coverage, not guesswork.** Areas were picked from the `llvm-cov` per-file report.

## Coverage

Line coverage, before → after this pass:

| Package | Before | After |
|---|---|---|
| AmbientBase | 52.8% | 94.4% (SecretStore's Keychain paths deliberately untested) |
| AmbientContracts | ~14% from its own tests | 100% on every file |
| AmbientCore + CLI (measured on the pre-split layout) | 81.6% | 93.6% |
| `ambient/Commands.swift` | 2.8% | 86.7% |
| `ambient/MemoryClient.swift` | 29.6% | 98.2% |
| AmbientApp | no tests | logic files 32–100%; whole target about 6% (mostly SwiftUI views and AppKit, see below) |

---

## AmbientBase

**Strategy.**
- Pure functions (JSON, Trim, RGB, Loopback, Paths, PerfLog) are tested from tables with `arguments:`: boundaries, malformed input, exact error offsets.
- JSON round trips are checked for stability (parse → serialize → parse) and against `JSONSerialization`.
- Socket tests use short unique `/tmp/qab-*.sock` paths and `socketpair`. The suite is `.serialized`, and concurrent clients run on plain threads.
- Anything that crashes or starves the process runs in an exit test, opt-in with `AMBIENT_TEST_CRASHES=1`.
- The Keychain is never read, written or deleted. The env-var fallback tests run only when an attributes-only query finds no stored item.

| Area | Cases | Type | File |
|---|---|---|---|
| AmbientPaths | `HOME`/`AMBIENT_HOME` set, empty, missing, relative; every derived path; `ensureHome` makes dirs 0700, is idempotent, tightens a loose home, errors when a path is a file | unit, temp files | `QAPathsTests.swift` |
| Loopback | 127.0.0.1, localhost, ::1, case, ports, user info; other hosts, look-alikes, ws/file/ftp/unix schemes, malformed URLs | unit, parameterized | `QASmallTypesTests.swift` |
| RGB, Version, TextLimits, ProcessProbe | hex variants and invalid input; mix clamping, NaN, ±∞; version format and the build script's extraction; limits; self, parent and launchd alive (EPERM), pid ≤ 0, impossible pid, reaped child | unit | `QASmallTypesTests.swift` |
| JSON parser | literals, numbers, escapes, `\u`, surrogate pairs, lone surrogates, invalid UTF-8, BOM, duplicate keys, depth 512/513, 20 message and offset pairs | unit, parameterized, exit tests | `QAJSONTests.swift` |
| JSON writer, JSONValue | escaping of every control character, indent variants, empty containers, round-trip stability, Foundation validity; key and index subscripts (get, set, remove, out of range, wrong type, duplicates); `detectIndent` | unit | `QAJSONTests.swift` |
| Trim | `truncate` at 0, 1, exact length, grapheme clusters and flags; `clean`; `plainText` (control, format, bidi, private-use, unassigned; scalar cap; ZWJ/ZWNJ/CR) | unit, exit test | `QATrimTests.swift` |
| PerfLog | minute buckets, out-of-order and future minutes, window rounding, pause cutoff, late threshold, scene vs effect, hook sample cap and percentiles, 24 h retention, report format | unit | `QAPerfLogTests.swift` |
| SecretStore | identifiers, every `errorDescription`, 200-character HTTP body cap, env fallback (gated) | unit | `QASecretStoreTests.swift` |
| UnixSocket | reply, fire-and-forget, first line only, empty and binary payloads, 50 KB split message, 2 MB reply, size limit ±1, flood, client timeout, ENOENT/ECONNREFUSED, 103/104-byte paths, 0600 mode, `isListening`, stale or regular file at the path, already running, rebinding, double stop, early hang-up (no SIGPIPE), 32 concurrent clients, silent clients, `serve()` over a socketpair | integration (local socket), exit test | `QAUnixSocketTests.swift` |
| Already existing | Trim, JSON, PerfLog | unit | `TrimTests`, `JSONTests`, `PerfLogTests` |

**Not unit-testable, and why:**
- **SecretStore's Keychain paths.** They need the real login Keychain, which tests must not change and whose reads can show a prompt. Testing them needs an injectable Keychain seam or a dedicated test service name.
- **`UnixSocket` system-call failures** (`socket`/`listen` failing, `EINTR`). These need fault injection.
- **The JSON parser's release-build stack depth.** Test bundles are Debug builds; this was checked once by hand with `swiftc -O`.

---

## AmbientContracts

**Strategy.**
- Every Codable type is treated as a wire and disk contract:
  - every enum case and every optional field, set and unset, round-trips;
  - older shapes (missing optional keys), newer shapes (extra keys) and hostile ones (wrong types, out-of-range Int32/Int64, unknown cases) are decoded;
  - the required keys are pinned exactly.
- Behaviour tables use `arguments:`: mood rules, Need per tool for every agent, every ToolNames alias, every remote event kind, durations and clocks at each boundary.
- Calendars are explicit: UTC, Kolkata, Kiritimati, Honolulu, and New York on a daylight-saving changeover day.

| Area | Cases | Type | File |
|---|---|---|---|
| Activity, Mood | `isBusy`, Codable shapes, malformed input; ordering, raw values, `wantsAttention` | unit, parameterized, negative | `QASessionTests.swift` |
| Session | local and remote ids, project, agent label, 22 mood rules, turn duration; required, optional and unknown keys or cases; stored id kept; `SessionChange` | unit, compatibility | `QASessionTests.swift` |
| Agents and events | AgentKind, EventKind, AgentEvent, HostInfo Codable: current, older and hostile shapes | unit, compatibility | `QAEventTests.swift` |
| Need | `init(reason:)`, headlines, `forTool` for 57 tools, `named`, `fromText`, cutting long text | unit, parameterized | `QANeedTests.swift` |
| Tasks | TaskStatus, TaskSummarySource, TaskSemantics; `AgentTask.makeID` format and uniqueness, older shapes; TaskChat host stripping; board column order and limits; search folding | unit, compatibility | `QATaskTests.swift` |
| DayLog | midnight and time zones, DST, rollover, counting, demo and sweep skipped, caps, remote privacy, `removeMoments(machine:)`, agent time, Codable | unit, boundary | `QADayLogTests.swift` |
| Describe | activity and short text, title, place, machine, remote status, durations, clock, took, mood; crash on non-finite or huge durations | unit, boundary, exit tests | `QADescribeTests.swift` |
| ToolNames | every alias, MCP name splitting, pass-through, no cutting | unit, parameterized | `QAToolNamesTests.swift` |
| Remote | event versions and kinds, `eventKind` mapping, `needsInput`, hostile text; RemoteDelivery, RemoteCursor, RemoteOrigin, MachineRef defaults, older shapes, malformed JSON, Int64 limits | unit, compatibility, hostile | `QARemoteTests.swift` |
| Already existing | golden JSON fixtures, events | compatibility | `ContractFixtureTests`, `EventTests` |

**Pinned as the current contract** (not bugs, but worth knowing):
- **Decoding is strict.** An unknown case of `Activity`, `AgentKind`, `TaskStatus`, `EventKind` or `Mood`, or a missing required key, fails the whole `Session`, `AgentTask` or `DayLog`. A new enum case is therefore a breaking format change for older readers. Unknown extra keys are ignored.
- **Some matching is case-sensitive.** `Need(reason:)` and `ToolNames.display` both depend on case.
- **Only part of remote text is cleaned here.** `RemoteEvent.eventKind` cleans only the permission path. Question and turn text are left to AmbientCore's `RemoteEventDecoder`, which is covered by Core's remote tests.

**Not unit-testable, and why:** defaults that read `Calendar.current` or `Date()` are not exercised, to keep the tests hermetic. `makeID` uniqueness can only be checked statistically, over 500 ids.

---

## AmbientCore

**Strategy.**
- The tests that already existed cover adapters for 7 agents, installers, the session store, remote ingest and quarantine, permissions, memory, the pet, the wallpaper, speech and voice sync.
- The new `QA*` files close the gaps the coverage report showed.
- HTTP clients run against `QAStubGateway`, with one port per test and a fixed port 443 standing in for Anthropic.

| Area | Cases | Type | File |
|---|---|---|---|
| Local-agent gateway client | handshake once and `Mcp-Session-Id` reuse; headers and arguments; increasing request ids; tool results (one JSON text, plain text, many texts, none, non-object); `isError`; RPC error; missing result; HTTP 400–503; empty or unreadable body; raw JSON; transport error; non-loopback refused before any request; streamed-reply parsing | integration (stubbed HTTP) | `QALocalAgentMCPTests.swift` |
| Board summarizer `resolve()` | disabled; cloud model blocked; bad or non-loopback URL; chat and vision ready; kind missing or not text; unknown model with the models volume mounted or missing; file-system fallback; HTTP or tool error → gateway down | integration (stubbed HTTP) | `QATaskSummarizerGatewayTests.swift` |
| Board summarizer `summarize()` | job completed; polls until done; failed (error, then message, then state); completed without text; no job id; cloud route and non-loopback refused | integration (stubbed HTTP) | `QATaskSummarizerGatewayTests.swift` |
| Status and model report | `TaskLLMStatus` labels and JSON round trip; `TaskModelResolution`; `TaskModelReport.fields` for the gateway, mlx and llama.cpp routes | unit | `QATaskSummarizerGatewayTests.swift` |
| Session titles and excerpts | Claude transcript (order, last four of at most six, length cap, malformed lines); Codex thread name; remote sessions never read local files; unsafe ids; desktop-title fallbacks; `lastValue` | unit (temp files) | `QASessionTitlesExcerptTests.swift` |
| Skill-pack bootstrap | `generate` and `generateSync` against the stub; HTTP 401/429/500; missing content; transport error; `run` writes the pack; key override; fenced JSON; invalid examples; field caps; blank hints | integration (stubbed HTTP) | `QATaskSkillBootstrapTests.swift` |
| Display strings | scene names, shortcut problems, voice-provider defaults, pet species and expressions, `SecretStoreError` | unit | `QADisplayStringsTests.swift` |
| Edge cases | model formats and runtimes; llama.cpp on `PATH`; pairing failure text; control characters stripped from remote text; machines file (sort, 0600, invalid and duplicate entries, versions); shared-file refusals (missing, folder, `/dev/null`, `.env`, token in content, symlink to a secret); same file shared twice becomes one blob; secret detection | unit (temp files) | `QAEdgeCaseTests.swift` |

**Not unit-testable, and why:**
- **The Python runtime probe and running mlx or llama.cpp directly.** These need a real Python with mlx, and model weights.
- **`RemotePairing.pair` and `uninstall`.** They need real ssh. Covered by the opt-in test (`AMBIENT_TEST_SSHD=1`).
- **`RemoteShim.bundledURL`.** It depends on the installed app bundle's layout.

---

## ambient CLI

**Strategy.**
- `Commands(paths:).run(args)` runs against a throwaway home under `/tmp/amb-cli-XXXXXXXX`.
- **App absent:** with no socket, every command that needs the app must exit 1.
- **App present:** `FakeAppSocket` listens on `~/.ambient/ambient.sock`, replies like Ambient.app, and records each request so tests assert exactly what was sent.

| Area | Cases | Type | File |
|---|---|---|---|
| Dispatch | `version`/`help` and their aliases; no args; unknown command (64); `voice-files`; `link` (creates, repeats, replaces a stale file) | unit | `CommandsTests.swift` |
| install / uninstall | unknown or `custom` agent (64); `--dry-run` writes nothing; `all` skips missing agents; a named missing agent fails; install → idempotent re-run → dry-run uninstall → uninstall; other hooks kept, backup made; malformed JSON left untouched | integration (fs) | `CommandsTests.swift` |
| App requests | `status`/`open`/`ack`/`tasks`/`task open`/`upsert`/`model` exit 1 with no app; an unexpected reply is treated as "not running"; text and `--json`; empty lists; no match → 1 | integration (socket) | `CommandsTests.swift` |
| task upsert / model / skill-status | usage errors (64); the draft the app receives; defaults; model path and Python checks; report as text and `--json`; timeout; `parseTaskModel`, `absolute`, `problem` | unit + integration | `CommandsTests.swift` |
| doctor | no app and no agents (1); healthy (0); hooks wiped after connecting (1); socket path too long (1); `--remote` usage and unknown machine | integration | `CommandsTests.swift` |
| remote | 12 usage errors (machines file untouched); `add` stops before ssh when there's no shim; `list`; `remove` unknown, existing, `--uninstall` (audited); `purge` (audited) | integration (fs) | `CommandsTests.swift` |
| emit / hook | usage errors; no app; events reach the app with the right agent; `--session` custom events; `hook` with invalid arguments returns without reading stdin | integration (socket) | `CommandsTests.swift` |
| MemoryClient and `ambient memory` | scope parsing; `age()`; list/read/forget address the project root; write fields; secrets and bad keys refused before anything is sent; file share copied into the blob store; refused file types; `fields()`; `digest()`; 11 usage errors; set/get/ls/rm round trips through the fake app, text and `--json` | unit + integration | `MemoryClientTests.swift` |
| `ambient mcp` | JSON-RPC, batches, tools, task model (already existing) | unit | `MCPServerTests.swift` |

**Not unit-testable, and why:**
- **`ambient hook <agent>`** reads its payload from stdin.
- **`ambient demo`** sleeps for 18 seconds.
- **`remote add`** and **`remove --uninstall`** need real ssh.
- **`task skill-bootstrap`** needs an Anthropic key.
- **`memory set KEY`** with no value reads stdin.
- **`mcp`'s stdio loop** reads stdin. Its request handling is covered through `handle(_:)`.

---

## AmbientApp

**Strategy.**
- AmbientApp is an executable target with a `main.swift`, imported with `@testable import AmbientApp`. Linking it into a test bundle works.
- Tests cover the logic under the views: view models, preferences, `AppModel`, and controllers that run headless.
- `AppSandbox` gives each test a temp home and a throwaway defaults suite, both removed afterwards.
- `AppModel` is built with `stateURL: nil` and `start()` is never called: no timers, observers or files, and the board model stays off.
- `PermissionDesk.answer(for:)` is only called from a detached task. It blocks until the main thread settles the prompt, so calling it on the main actor would deadlock.

| Area | Cases | Type | File |
|---|---|---|---|
| Preferences | fresh-install defaults; every value type survives a relaunch; `petOrigin` pair, clear and malformed; unknown values fall back; past quiet time; `alertSettings` and `taskLLMConfig`; permission settings go to `~/.ambient/permissions.json`; a hand-edited wait snaps to an offered one | unit | `PreferencesTests.swift` |
| AppModel | starts empty and idle; events publish sessions and mood; transitions; ended sessions leave; acknowledge one or all; upsert task; board picks up sessions; unknown task opens nothing; remote cursor, `keepMachines`, remote health, purge, unpaired batches dropped; `setQuiet`; shared memory round trip; secrets refused | unit (MainActor) | `AppModelTests.swift` |
| Island | sizes for all 8 presentations; wide notch; permission card hint lines; 5 or 10 rows; `hasMore`; `bloomSession`; `primary`; panel frame and screen rect, including offset displays | unit | `IslandTests.swift` |
| Pet view model | no content without sessions; bubble opens up or down; primary held steady; expanded list grows; tap toggles peek and reacts; bursts; open session; speaking bubble; tail clamped | unit, parameterized | `PetViewModelTests.swift` |
| PermissionDesk | unknown id; prompt handed back when answering or the island is off; enqueue → Allow → `.allow`; the agent moving on withdraws the prompt with `.ask` | concurrency | `PermissionDeskTests.swift` |
| Speech | `ResumeOnce` races (50 rounds); `PCM.mono`; `SpeechFailure`; `EngineSection.ready` per engine; voice-pack paths; `SpeechState` | unit, concurrency | `SpeechTests.swift` |
| Settings, theme, wallpaper | `VoiceFormat.clock`; pane order; only Board and Alerts have their own subtitle; every tab has a title and a unique subtitle; Performance windows; `rawMood`; tints; `Theme.Status` colours; wallpaper previews for every scene, light and dark | unit, parameterized | `SettingsAndThemeTests.swift` |
| HookDoctor | empty home is clean; hooks removed after connecting are reported, then fixed; partial hooks quietly rewritten (temp home only) | integration (fs) | `HookDoctorTests.swift` |

**Not unit-testable, and why:** about two-thirds of the app's lines are code a unit test can't run. These need a window server, granted TCC permissions, audio hardware or a second Mac, so they're on the manual checklist below:
- SwiftUI view bodies.
- NSPanel and window layering: island, pet, desktop and lock layers, Dock glow, menu bar.
- Audio: chimes, speech engines and player, Now Playing.
- Accessibility and input: selection reader, hot keys, Focuser AppleScript, HostActivator.
- User notifications.
- Voice sync, speaker and microphone, and the CoreAudio loopback driver.
- Runtime networking: `EventServer`, `RemoteCoordinator`, voice-pack download.

Ways to raise the number:
- Move decisions out of views into view models or Core.
- Add snapshot tests for the views.
- Add XCUITest for the windows.

---

## Manual and release checklist

Run these on the notarized build:

- [ ] **Fresh install.** Go through Welcome, run `ambient install`; `ambient doctor` should say "Everything looks good."
- [ ] **`ambient demo`.** Check the notch bloom, the hover list, the menu bar mood, the Dock glow, the pet, and the wallpaper and lock screen.
- [ ] **Hook path.** Pipe a real Claude payload into `~/.ambient/bin/ambient hook claude` with `AMBIENT_DEBUG=1`, then check `~/.ambient/logs/hook.log` and the island.
- [ ] **Permission prompts from the island.** Allow and Deny reach Claude Code and Codex. When the agent's app is in front, the prompt is handed back.
- [ ] **Focus.** Clicking a session focuses Terminal, iTerm, Ghostty, VS Code, Cursor, and Claude's and Codex's apps.
- [ ] **Read aloud.** The shortcut works with the Mac, Kokoro and online engines; pause, resume and stop work; a failure offers the Mac voice.
- [ ] **Notifications.** Done, waiting and error banners appear; clicking one opens the session; quiet mode silences them.
- [ ] **Every Settings pane and tab** in light and dark mode, with Reduce Motion and VoiceOver on, on a notched display and on a virtual notch (`debugVirtualNotch`).
- [ ] **Voice sync, speaker and microphone** between two Macs.
- [ ] **Remote.** `ambient remote add` to a real host, then `remote remove --uninstall`.
- [ ] **Board model.** Against a live gateway: ready, volume unmounted, unknown model. `ambient task skill-bootstrap` writes a 0600 file.
- [ ] **Real-ssh test.** `AMBIENT_TEST_SSHD=1 swift test --filter overARealSSHServer`.

## Bugs found by this pass

Each is pinned by a `withKnownIssue` test. A crash bug runs in an exit test.

| # | Severity | Where | Bug |
|---|---|---|---|
| 1 | High (privacy) | `AmbientCore/LocalAgent/TaskLLM.swift` `isCloudModel` | Only `:cloud` and `cloud/` are blocked. Ollama's hosted models end in `-cloud` (`gpt-oss:120b-cloud`), so they pass as local and session text could leave the Mac. |
| 2 | Medium (crash) | `AmbientContracts/Describe.swift` `duration`, `compactDuration` | `Int(seconds)` traps on NaN, ±∞ or values too large for an `Int`. `Describe.clock` feeds it timestamps read from disk and the socket, so one corrupt `turnStartedAt` crashes every surface that draws that session. Fix: clamp before converting. |
| 3 | Medium (data) | `AmbientBase/JSON/JSONParser.swift` (lone surrogates) | A lone high surrogate followed by an ordinary `\u` escape swallows the second escape: `"\uD800A"` becomes `"\u{FFFD}"` instead of `"\u{FFFD}A"`. This loses a character when Ambient rewrites other tools' config files. |
| 4 | Low (crash) | `AmbientBase/Trim.swift` `truncate` | A negative `max` reaches `prefix(-1)` and traps. |
| 5 | Low | `AmbientBase/Trim.swift` `plainText` | Strips the zero-width joiner (👩‍💻 → 👩💻) and the zero-width non-joiner (breaks Persian and Indic text), and deletes a lone `\r` instead of turning it into a space. |
| 6 | Low | `AmbientBase/UnixSocket.swift` server | Clients are served on a shared concurrent dispatch queue. When about as many threads as there are CPUs in the same process are blocked in `UnixSocket.send`, the server stalls until they time out. CLI clients are separate processes, so in the product this only matters if the app blocks its own threads. Reproduced in a child process. |
| 7 | Low (diagnostics) | `AmbientBase/JSON/JSONParser.swift` | Error offsets are 3 bytes short after a byte order mark. |
| 8 | Low (Debug only) | `AmbientBase/JSON/JSONParser.swift` depth limit | The limit is 512, but a Debug build overflows a 512 KiB thread stack between 384 and 448 levels. Release builds are fine. |
| 9 | Low | `AmbientCore/LocalAgent/TaskSkillBootstrap.swift` `parsePayload` | `Trim.clean(...) ?? $0` puts a whitespace-only hint back into the skill pack. |
| 10 | Cosmetic | `AmbientCore/SessionTitles.swift` `excerpt` | `"\n---\n"` separators are folded to `" --- "` by the final truncate. |

## Stale code removed with this pass

These were used by nothing in the product. Assertions that needed them now use test-side helpers or observable behaviour:
- `JSONValue.objectKeys` and `arrayCount`, now test helpers in each test target that needs them.
- `PerfLog.minuteCount`.
- `Session.elapsed(now:)`.
- `SessionStore.busyCount`.
- `VoiceInbox.inFlight`.
- `TaskLLMConfig.refusesNonLoopback`, now a test helper.
- `TaskLLMStatus.isUsable`.
- `LocalModelRunner.unload`.
- `PetArt.bodySize`.

The deprecated shims in `AmbientCore/Deprecated.swift` are left alone: Phase 4 of the modular-packages plan removes them, with its own version bump.

## Last run

2026-11-21, `swift test --enable-code-coverage` on `main` plus this change. The full suite was run twice back to back, with the same result both times.

| Test target | Tests | Result | Line coverage of its package |
|---|---|---|---|
| `AmbientBaseTests` | 209 | passed, 7–8 known issues (bug 6 reproduces intermittently and is marked so) | 94.4% |
| `AmbientContractsTests` | 184 | passed, 5 known issues (bug 2, one per input) | 100% |
| `AmbientCoreTests` | 840 | passed, 3 known issues (bugs 1 and 9) | 95.2% |
| `AmbientCLITests` | 96 | passed | 82.5% |
| `AmbientAppTests` | 85 | passed | 5.0% (see AmbientApp above) |
| **Total** | **1,414** | **0 failures** | |
