# Ambient QA test cases

The checks a person (or an automated test) runs to know Ambient works, by feature, each mapped to
the code it exercises. Unit and integration tests live in `Tests/`; this folder is the level above
them: what a user does and what they should see.

Because every case names the code it covers, a change can pick its own cases:

```bash
node scripts/qa-cases.ts select --base origin/main      # cases for this branch's changes
node scripts/qa-cases.ts select --files Sources/AmbientApp/Island/IslandView.swift
node scripts/qa-cases.ts check                          # format, unique ids, every source file covered
```

`select` prints the cases to run, why each was picked, and the changed files no case covers
("changed, no QA case"). That last list is as important as the first: it is where a release is
least checked.

## Areas

One file per feature area in `qa/cases/`, each with its own id prefix.

| File | Prefix | Feature |
|---|---|---|
| [setup.md](cases/setup.md) | `SET-` | First run, connecting each agent, `ambient install` / `doctor` / `uninstall`, hook health |
| [events.md](cases/events.md) | `EVT-` | From an agent's hook to a session's state, per agent; what is stored on disk |
| [permissions.md](cases/permissions.md) | `PRM-` | Answering permission prompts from the notch |
| [island.md](cases/island.md) | `ISL-` | The notch island |
| [alerts.md](cases/alerts.md) | `ALR-` | Notifications, chimes, menu bar, Quiet alerts, click to return |
| [dock.md](cases/dock.md) | `DCK-` | Dock glow |
| [pet.md](cases/pet.md) | `PET-` | Desktop pet |
| [wallpaper.md](cases/wallpaper.md) | `WAL-` | Living wallpaper and today's story |
| [read-aloud.md](cases/read-aloud.md) | `SPK-` | Read aloud, every voice, the offline voice download |
| [speaker-mic.md](cases/speaker-mic.md) | `SPM-` | Ambient speaker, Ambient Microphone, voice sync, the audio driver |
| [remote.md](cases/remote.md) | `RMT-` | Remote machines over ssh |
| [memory.md](cases/memory.md) | `MEM-` | Working memory shared between agents |
| [board.md](cases/board.md) | `BRD-` | Task board, local model summaries, `ambient task` |
| [history.md](cases/history.md) | `HIS-` | Agent history: storing finished chats, what is never stored, `ambient history`, answers, the pull-request link |
| [app.md](cases/app.md) | `APP-` | Install, upgrade, settings window, performance, signing, CLI basics |

**For a release**, run every P0 case plus the cases `select` picks for the changes since the last
release (`--base v0.10.0 --with-p0`). Cases marked *Known gap* describe a difference between what
the README promises and what the code does; they are expected to fail until it is fixed.

## Limits

- **Selection is by file, not by function.** A file that serves many features picks every case
  that names it: `Sources/ambient/Commands.swift` (every CLI command) picks about 40 cases in six
  areas, and `AppDelegate.swift` and `AppModel.swift` about 16 each. A change there is reported
  wider than it is.
- **A case reaches only the files it names.** If a change breaks a feature through a file the
  case does not list, `select` will not pick it. The "changed, no QA case" list catches only files
  no case names at all.
- **The cases were written from the code on 21 November 2026** and say what it did then. When
  behaviour changes on purpose, the case changes in the same pull request.

## Case format

Every case is a level-3 heading with the id, then a fixed list of fields, then steps and expected
results. The selector reads the heading and the field lines; keep their spelling exactly.

```markdown
### ISL-003 · Needs-you bloom names what the agent needs

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/**`, `Sources/AmbientContracts/Need.swift`
- **Automated by:** `NeedTests`
- **Needs:** Mac with a notch; Claude Code connected

**Steps**

1. In a Claude Code session, ask it to run `rm -rf build` so it asks permission.

**Expected**

- The island blooms amber within a second and reads *Approve a command · rm -rf build*.
```

| Field | Values |
|---|---|
| Priority | `P0` the product is broken without it (run for every release); `P1` a main feature (run when its code changes); `P2` an edge case or polish |
| Type | `manual`, `automated` (an existing test fully checks it), or `both` (a test checks part; a person checks the rest) |
| Covers | Repository paths or globs (`*` within a folder, `**` across folders), each in backticks. Name the code the case exercises, not everything it touches on the way: the shared event pipeline belongs to the `events` area, not to every visible feature |
| Automated by | Test types or functions in `Tests/` (or the speaker driver's `Drivers/AmbientSpeaker/Tests.c`) that check part of it, or `none` |
| Needs | What the tester needs: hardware, permissions, agents, a second Mac. `nothing special` if nothing |

Rules for writing a case:

- **Expected results are observable.** What appears, where, its text and colour, how long it takes. Not "works correctly".
- **One behaviour per case.** If the steps check two things that can fail separately, split them.
- **Write what the code does today.** Read the source before writing a case. A case that describes intended behaviour the code does not have is marked `**Known gap:**` with what differs.
- **Privacy and safety promises get P0 cases.** Ambient never answers a permission prompt by itself, never stores prompts or tool output, goes online only when asked. Each promise has a case that would catch it breaking.
