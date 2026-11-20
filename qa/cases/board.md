# Task board

Id prefix: `BRD-`

The local task board: how sessions become tasks, the columns and search, opening a card's chat, expiry,
the `ambient tasks` / `ambient task …` commands, local LLM summaries and the board's model, the `ambient mcp`
model tools, and feature requests.

Where a case says "the board", both Settings › Board and the Task Board window show it unless the case says
otherwise. Unless a case says otherwise, `ambient` means `~/.ambient/bin/ambient`.

## Grouping sessions into tasks

### BRD-001 · A new agent session becomes an In progress task

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientContracts/Task.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `TaskStoreTests.needsYouBecomesBlocked`, `TaskStoreTests.tasksStaySortedAsTheyChange`
- **Needs:** Claude Code connected; summaries off

**Steps**

1. Open Settings › Board.
2. In a new folder `qa-board-a`, start Claude Code and ask it to list the files (it runs a tool).
3. Watch the board.

**Expected**

- Within a second of the first tool, an *In progress* column appears with one card.
- The card's title is the session's chat title if Claude Code has one yet, otherwise the project name `qa-board-a`
  (titles are cut at 80 characters).
- Under the title the card shows the project `qa-board-a`; its footer shows a coral dot and *Claude*, a small coloured
  mood dot, and how long the session has been working.
- The column header reads *In progress* with the count `1`.

### BRD-002 · Sessions in the same project with the same title on the same day share one task

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** `TaskStoreTests.sameProjectSameDayGroups`
- **Needs:** Claude Code and Codex connected

**Steps**

1. In folder `qa-board-a`, run a Claude Code session with no chat title yet (so the task is titled `qa-board-a`).
2. In the same folder, the same day, start a Codex session and let it run a tool.

**Expected**

- The board still shows one card for `qa-board-a`, not two.
- Its footer lists both agents: a coral and a green dot, and *Claude · Codex*.
- `ambient tasks` lists one task for the project with agents `claude,codex`.

### BRD-003 · A different project, machine or day starts a new task

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** none
- **Needs:** Claude Code connected

**Steps**

1. Run a Claude Code session in `qa-board-a`, then one in `qa-board-b`.
2. The next calendar day, run another session in `qa-board-a` with the same title as yesterday's.

**Expected**

- After step 1 there are two cards, one per project.
- After step 2 there is a third card for `qa-board-a`: grouping only joins a task that was created or updated today.
- Matching ignores case and surrounding spaces, and a title that is a prefix of the other also joins
  (*Fix login* and *Fix login page* are one task).

### BRD-004 · A session that needs you moves its task to Blocked, the first column

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientContracts/Task.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `TaskStoreTests.needsYouBecomesBlocked`, `TaskStoreTests.columnsFollowBoardOrderAndSkipEmptyOnes`
- **Needs:** Claude Code connected

**Steps**

1. With a task *In progress* for a Claude Code session, ask Claude to run `rm -rf build` so it asks permission.
2. Approve the prompt in the terminal.

**Expected**

- Within a second of the prompt, the card moves to a *Blocked* column, which is the leftmost column; its mood dot is amber.
- Columns always appear in the order *Blocked*, *In progress*, *Backlog*, *Done*, *Cancelled*, and an empty column is
  not shown.
- After approving, the card moves back to *In progress*.

### BRD-005 · A failed turn also blocks the task

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient emit start --session qa-err --agent Build --cwd /tmp/qa-err`
2. `ambient emit working --session qa-err --tool make --detail "make all"`
3. `ambient emit error --session qa-err --message "make failed"`

**Expected**

- After step 2 the task `qa-err` is *In progress*; after step 3 it is in *Blocked* with a red mood dot.

### BRD-006 · A task you added still turns Blocked when its session needs you

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient task upsert --title "Hand-made" --status backlog --session custom:qa-manual`
2. `ambient emit waiting --session qa-manual --message "Pick a branch"` (with `--agent` left at its default, the
   session id is `custom:qa-manual`).

**Expected**

- *Hand-made* moves from *Backlog* to *Blocked*.
- Its title stays *Hand-made*: heuristics never rename a task you wrote.

### BRD-007 · A task whose session ends moves to Done and stays on the board

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** `TaskStoreTests.pruneUnlinksSessionsThatAreGoneAndSettlesOrphans`
- **Needs:** Claude Code connected

**Steps**

1. With a Claude Code task *In progress*, exit Claude Code (`/exit`).
2. Wait for the session to leave the island.

**Expected**

- The card moves to *Done*. It keeps its title, project and agents.
- The card no longer shows a mood dot or a clock, since no live session is linked.

### BRD-008 · Demo sessions never reach the board

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientCore/Demo.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Note the board's cards.
2. Click **Play Demo** in the menu bar and wait for the tour to finish (about 36 seconds).

**Expected**

- No *api-server*, *web* or *docs* card appears at any point; the board is unchanged. (Demo session ids start with
  `demo-`.)

## Columns, cards and search

### BRD-009 · Settings › Board shows each column's latest eight cards and links to the rest

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/BoardPane.swift`, `Sources/AmbientContracts/Task.swift`
- **Automated by:** `TaskStoreTests.limitKeepsTheFirstTasksAndCountsTheRest`
- **Needs:** nothing special

**Steps**

1. Create 11 backlog tasks: `for i in $(seq 1 11); do ambient task upsert --title "Backlog $i"; done`
2. Open Settings › Board.
3. Click the line under the *Backlog* column.

**Expected**

- The *Backlog* header shows `11`; the column shows 8 cards, newest first (*Backlog 11* at the top).
- Under the cards: *3 more in the Task Board*, with the tooltip *Open the Task Board window*.
- Clicking it opens the Task Board window, which shows all 11.

### BRD-010 · The Task Board window shows every card, its status and the wallpaper cue switch

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/BoardPane.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** a board with a few tasks

**Steps**

1. Choose **Task Board…** from the menu bar (or Settings › Board › **Open Board**).
2. Resize the window as small as it goes.
3. With the living wallpaper off, look at the switch at top right; then turn the wallpaper on in Settings › Appearance › Wallpaper.

**Expected**

- A window titled *Task Board* opens, about 980 × 620, centred, with the heading *Task Board* and the summaries status
  under it (*Local LLM off — using metadata heuristics* when summaries are off).
- Columns are wider than in Settings and show every card; the window scrolls both ways and can't be made smaller than
  880 × 520.
- *Wallpaper cues* is greyed out while the wallpaper is off (tooltip *Soft task titles on the living wallpaper. Off by
  default.*) and becomes usable once it's on. It is off by default.
- While the window is open Ambient shows in the Dock; closing it (with Settings closed) removes it from the Dock again.

### BRD-011 · The menu bar counts tasks that are blocked or in progress

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientContracts/Task.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. With no blocked or in-progress tasks, open the menu bar menu.
2. `ambient task upsert --title "Count me" --status inProgress`, then open the menu again.

**Expected**

- Step 1 shows *Task Board…*; step 2 shows *Task Board (1)…*. Backlog, done and cancelled tasks are not counted.

### BRD-012 · An empty board says how tasks appear

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `TaskStoreTests.noTasksNoColumns`
- **Needs:** a fresh `~/.ambient` (or `AMBIENT_HOME` pointing at an empty folder)

**Steps**

1. Open Settings › Board, then the Task Board window.

**Expected**

- Settings › Board shows *No tasks yet* with the footer *Tasks appear as your agents work, grouped by project and
  title. Or add one with `ambient task upsert --title "…"`.* No search field is shown.
- The Task Board window shows *No tasks yet — they appear as your agents work.* in the middle.

### BRD-013 · Search finds tasks by every word, in any order, ignoring case and accents

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientContracts/Task.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `TaskStoreTests.searchFindsTasksByWhatsWrittenOnThem`
- **Needs:** nothing special

**Steps**

1. `ambient task upsert --title "Fix the login" --project api` and `ambient task upsert --title "Café menu" --project site`
2. In the board's *Search tasks* field type `API fix`.
3. Replace it with `cafe`.
4. Replace it with `nothing-like-this`.
5. Press Esc.

**Expected**

- Step 2 shows only *Fix the login*; step 3 only *Café menu*.
- Step 4 shows *No tasks match “nothing-like-this”* in place of the columns.
- Column counts count only the matching tasks while a search is typed.
- Esc (or the ⓧ button, tooltip *Clear search*) empties the field and every card returns.

### BRD-014 · Search also matches folder, agent, status and machine

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientContracts/Task.swift`
- **Automated by:** `TaskStoreTests.searchFindsTasksByWhatsWrittenOnThem`
- **Needs:** a Codex task; optionally a paired remote machine

**Steps**

1. Search for a word that appears only in a task's folder path (its `cwd`), e.g. `Projects`.
2. Search `codex`.
3. Search `blocked`.
4. With a remote machine paired, search for its label.

**Expected**

- Each search keeps exactly the tasks whose folder, agent name (*Codex*), status name (*Blocked*) or machine label
  contain the words.

## Opening a card's chat

### BRD-015 · Clicking a card opens its live session

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/BoardPane.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** none
- **Needs:** Claude Code running in Terminal or iTerm2 (Automation allowed)

**Steps**

1. Switch to another app.
2. Hover the card of the running session, then click it.

**Expected**

- The tooltip reads *Open Claude*.
- The terminal tab running that session comes to the front, the same as clicking it on the island.
- A *Done* session opened this way is marked as seen.

### BRD-016 · A task's chat still opens after its session ended

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientContracts/Task.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `TaskStoreTests.anEndedTasksChatStillOpens`, `TaskStoreTests.aBoardSavedBeforeChatsWereKeptStillLoads`
- **Needs:** Claude's desktop app with a Claude Code chat (or the Codex app)

**Steps**

1. Run a chat in Claude's desktop app until its task shows on the board, then end the session and wait for its card to
   reach *Done*.
2. Quit and reopen Ambient.
3. Click the card.

**Expected**

- The card is still clickable (tooltip *Open the chat*).
- Claude's desktop app opens that exact chat.
- `ambient task open <id>` does the same and exits 0.

### BRD-017 · A card with no chat to open can't be clicked

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient task upsert --title "No chat"`
2. Hover and click its card.
3. `ambient task open <its id>`

**Expected**

- The card is dimmed as disabled, its tooltip reads *No chat to open*, and clicking does nothing.
- The command prints *No chat to open for task '<id>'.* and exits 1.

### BRD-018 · Another machine's task opens on that machine, and the card says how it went

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppModel.swift`, `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** `TaskStoreTests.aRemoteTasksChatIsntOpenedHere`
- **Needs:** a second Mac with Ambient, paired with `ambient remote add`

**Steps**

1. Run a Claude Code session on the paired Mac until its card shows here, with the machine's label and a network icon.
2. Hover the card, then click it.
3. Unpair the machine (`ambient remote remove NAME`) on a board that still holds a card from it, and click the card if one remains.

**Expected**

- The tooltip reads *Opens on <label>*.
- Clicking shows *Opening on <label>…* on the card, and the chat comes forward on the other Mac with a notification
  naming this Mac. The card's note then changes to the outcome and clears after 5 seconds.
- Nothing opens on this Mac.
- A card whose machine is no longer paired shows *<label> isn't paired with this Mac* for 5 seconds.

## Expiry and persistence

### BRD-019 · A task the agents made leaves the board three days after its last session ends

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `TaskStoreTests.finishedTasksAgeOffTheBoard`
- **Needs:** a way to set the clock forward, or a seeded `~/.ambient/tasks.json`

**Steps**

1. Quit Ambient. In `~/.ambient/tasks.json`, give one agent-made task (`"manual":false`, no `sessionIds`) an
   `updatedAt` 3 days and 1 hour ago, and another 2 days ago.
2. Open Ambient and look at the board.

**Expected**

- The 3-day-old task is gone; the 2-day-old one is still there.
- With Ambient running, the same check repeats every 10 minutes, so a task crossing the 3-day mark leaves within 10
  minutes.

### BRD-020 · Tasks you add yourself never expire

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** `TaskStoreTests.finishedTasksAgeOffTheBoard`, `TaskStoreTests.thisMacsTasksHaveALimitToo`
- **Needs:** a seeded `~/.ambient/tasks.json`

**Steps**

1. Quit Ambient. In `tasks.json`, set a task's `"manual":true` and its `updatedAt` 30 days ago.
2. Open Ambient.

**Expected**

- The task is still on the board.
- When this Mac's board reaches 5,000 tasks, the oldest agent-made tasks make room; tasks you wrote are never dropped
  for room.

### BRD-021 · Sessions that ended while Ambient was closed are unlinked on launch

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `TaskStoreTests.pruneUnlinksSessionsThatAreGoneAndSettlesOrphans`
- **Needs:** Claude Code connected

**Steps**

1. With a task *In progress* for a Claude Code session, quit Ambient.
2. Exit Claude Code, then open Ambient.

**Expected**

- The task is in *Done*, not left *In progress* or *Blocked*.

### BRD-022 · The board survives a quit and relaunch

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskFile.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `TaskStoreTests.persistRoundTrip`
- **Needs:** a board with tasks in several columns

**Steps**

1. Note each card's title, column and summary.
2. Quit Ambient from the menu bar (**Quit Ambient**, ⌘Q), then open it again.

**Expected**

- Every task is back in the same column with the same title, summary and agents.
- A change on the board reaches `~/.ambient/tasks.json` about a second later; quitting writes it at once.
- A `tasks.json` that isn't valid JSON or has a `version` other than `1` loads as an empty board without an error.

### BRD-023 · The board file is readable only by you

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientCore/TaskFile.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Make any board change (e.g. `ambient task upsert --title "Mode check"`) and wait 2 seconds.
2. `ls -l ~/.ambient/tasks.json` and `stat -f %Lp ~/.ambient`

**Expected**

- `tasks.json` is `-rw-------` (`0600`), owned by you, and `~/.ambient` is `700`.
- It holds titles, summaries, projects and folders only, never prompts or tool output.

## Command line

### BRD-024 · `ambient tasks` lists the board

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** a board with a few tasks

**Steps**

1. `ambient tasks`
2. `ambient tasks --json`
3. Quit Ambient, then `ambient tasks`.

**Expected**

- Step 1 prints *Board · N tasks* (or *Board · 1 task*, or *Board · no tasks*), then one line per task in board order:
  status, project (or *—*), title cut to 40 characters, agents and the task id.
- Step 2 prints a pretty, key-sorted JSON array of the tasks with ISO 8601 dates.
- Step 3 prints *Ambient isn't running. Open Ambient.app, then try again.* and exits 1.

### BRD-025 · `ambient task upsert` adds a task you wrote

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** `TaskStoreTests.manualUpsertWinsTitle`
- **Needs:** nothing special

**Steps**

1. `ambient task upsert --title "Write release notes" --status inProgress --project site`
2. `ambient task upsert --title "Bad" --status started`
3. `ambient task upsert --status done`

**Expected**

- Step 1 prints *✓ Task task-xxxxxxxx: inProgress — Write release notes* (an 8-character hex id) and the card appears in
  *In progress* at once.
- Step 2 prints *Unknown status 'started'. Use backlog, inProgress, blocked, done or cancelled.* and exits 64.
- Step 3 prints the usage line *Usage: ambient task upsert --title TEXT [--id ID] [--status STATUS] [--project NAME]
  [--session SID]* and exits 64.
- Without `--status` the task goes to *Backlog*.

### BRD-026 · Upserting an existing id replaces that task

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `TaskStoreTests.manualUpsertWinsTitle`
- **Needs:** nothing special

**Steps**

1. `ambient task upsert --id task-qa000001 --title "First" --project api --status blocked`
2. `ambient task upsert --id task-qa000001 --title "Second"`
3. `ambient tasks --json`

**Expected**

- One task `task-qa000001`, titled *Second*, in *Backlog*, with no project: an upsert replaces every field it is given
  a default for, so pass every field you want to keep.
- Its `createdAt` is that of step 1; `updatedAt` is step 2's; `manual` is `true` and `summarySource` is `manual`.

### BRD-027 · `ambient task` without a known subcommand says what it takes

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient task`
2. `ambient task frobnicate`
3. `ambient task open`

**Expected**

- Step 1: *Usage: ambient task upsert … | ambient task open ID | ambient task model [PATH] | ambient task skill-bootstrap*, exit 64.
- Step 2: *Unknown task command 'frobnicate'. Use upsert, open, model, skill-bootstrap or skill-status.*, exit 64.
- Step 3: *Usage: ambient task open ID*, exit 64.

## Local LLM summaries

### BRD-028 · Summaries are off by default and nothing is called while they are

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `LocalModelTests.disabledResolvesToDisabled`
- **Needs:** a fresh install; a listener on `127.0.0.1:5051` (e.g. `nc -lk 5051`) to watch for connections

**Steps**

1. Open Settings › Board.
2. Run a few agent sessions for a minute.

**Expected**

- *Summarize tasks on this Mac* is off and its subtitle reads *Local LLM off — using metadata heuristics* in neutral grey.
- *Read your agent chats* is off and greyed out.
- The listener receives no connection, no model process (`python3`, `llama-completion`) starts, and cards show no brain
  icon.

### BRD-029 · With summaries on, cards get a short local summary

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientCore/LocalAgent/LocalAgentMCP.swift`, `Sources/AmbientCore/LocalAgent/TaskSkillPack.swift`, `Sources/AmbientContracts/TaskSemantics.swift`, `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `TaskLLMTests.localLLMUpdatesSummaryAndTitle`, `TaskLLMTests.parsesFencedJSON`, `TaskLLMTests.dropsReasoningBeforeTheAnswer`, `TaskLLMTests.parsesEventStreamDataLine`, `TaskLLMTests.bundledSeedInjectsExamplesIntoPrompt`
- **Needs:** local-agent running at `http://127.0.0.1:5051/mcp` (LaunchAgent `com.local-agent.mcp`) with `hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit` available

**Steps**

1. Turn on *Summarize tasks on this Mac*.
2. Run a Claude Code session that edits a file.
3. Keep it working for two minutes.

**Expected**

- The subtitle turns green: *Local LLM ready*, and *Summarizing…* while a summary runs.
- Within a couple of minutes the card shows a one-line summary (cut to 60 characters on the card), the project in
  the footer, and a small brain icon with the tooltip *Summarized by local LLM*.
- A task is summarized at most once every 45 seconds, however many events its session sends.

### BRD-030 · A model's reply never clears Blocked while you're needed

- **Priority:** P1
- **Type:** automated
- **Covers:** `Sources/AmbientCore/TaskStore.swift`, `Sources/AmbientContracts/TaskSemantics.swift`
- **Automated by:** `TaskLLMTests.waitingStillForcesBlocked`, `TaskLLMTests.staleWaitingSessionDoesNotReblockAfterLiveUnblock`, `TaskLLMTests.llmCannotClearBlockedWithoutWaitingSession`, `TaskStoreTests.aLateSummaryDoesntReopenAFinishedTask`
- **Needs:** nothing special

**Steps**

1. Run the tests named above.

**Expected**

- A summary that says *inProgress* leaves a blocked task blocked; a live waiting session always forces *Blocked*.
- A summary that arrives after the session ended doesn't reopen the task, and a summary of a task you wrote changes
  neither its status nor (unless it's empty or generic) its title.

### BRD-031 · Reading agent chats is a separate opt-in

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientApp/AppModel.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `TaskLLMTests.includesAgentAndMood`
- **Needs:** summaries on with a working model; `fs_usage` (or a gateway log that records prompts)

**Steps**

1. With *Read your agent chats* off, run a Claude Code session and watch `sudo fs_usage -w -f filesys Ambient | grep .claude/projects`.
2. Turn *Read your agent chats* on and repeat.

**Expected**

- The toggle's subtitle reads *Better titles from your Claude Code and Codex chats on this Mac. They can hold secrets;
  nothing leaves this Mac.*
- In step 1 Ambient never opens a transcript under `~/.claude/projects` for summaries, and the prompt carries only the
  agent, session id, project, folder, title, mood and activity.
- In step 2 the prompt gains a `transcript_excerpt:` of at most 2,500 characters, sent only to the loopback gateway or
  a model process on this Mac.

### BRD-032 · Cloud-tagged models are refused

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** `TaskLLMTests.blocksCloudTaggedModels`, `LocalModelTests.modelPathSkipsCloudCheckOnModelID`
- **Needs:** local-agent running

**Steps**

1. Turn summaries on. Under *Model and gateway*, set *Model id* to `gpt-oss:120b-cloud` and click **Check Status**.
2. Set it to `ollama:cloud/llama3`.
3. Run an agent session.

**Expected**

- The subtitle turns amber: *Model gpt-oss:120b-cloud looks cloud-hosted. Choose a local hf:/ollama: model.* (any id
  containing `:cloud` or `cloud/`).
- No `submit_inference` reaches the gateway, and no card gets a summary.

### BRD-033 · Only a loopback gateway address is used

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientCore/LocalAgent/LocalAgentMCP.swift`
- **Automated by:** `TaskLLMTests.acceptsOnlyLoopbackMCPHosts`
- **Needs:** a second machine or address listening on port 5051, to confirm nothing arrives

**Steps**

1. Turn summaries on. Set *MCP URL (loopback only)* to `http://192.168.1.20:5051/mcp` and click **Check Status**.
2. Set it to `http://localhost:5051/mcp`, then `http://127.0.0.1:5051/mcp`.

**Expected**

- Step 1: *MCP URL must be loopback (127.0.0.1 / localhost). Session text stays on this Mac.* in amber, and no request
  reaches the other address.
- Step 2: both loopback forms are accepted.

### BRD-034 · A missing gateway keeps the board working with a calm status

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientCore/LocalAgent/LocalAgentMCP.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** none
- **Needs:** summaries on with the model id; local-agent stopped (`launchctl bootout gui/$(id -u)/com.local-agent.mcp`)

**Steps**

1. Open Settings › Board and click **Check Status**.
2. Run an agent session.
3. Start local-agent again and wait up to 30 seconds.

**Expected**

- The subtitle reads, in amber, *Couldn't reach local-agent at 127.0.0.1: …* with the system's reason. No alert or
  dialog appears.
- Cards still appear and move between columns from session metadata.
- Within 30 seconds of the gateway coming back the subtitle returns to *Local LLM ready* without a click.

### BRD-035 · An unmounted models disk shows how to mount it

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** none
- **Needs:** local-agent running; models on an external SSD mounted at `/Volumes/Models`

**Steps**

1. Eject the models SSD, then click **Check Status**.
2. Point *Model path* at a folder under `/Volumes/Models` while it is ejected.

**Expected**

- Step 1: *Models disk unmounted.* followed by local-agent's own mount hint, or *Run models-on if /Volumes/Models is
  missing.* when it gives none.
- Step 2: *Models disk unmounted. Run models-on if /Volumes/Models is missing.*
- After `models-on`, **Check Status** returns *Local LLM ready*.

### BRD-036 · A model id the gateway lacks, or one that can't write text, says so

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** `LocalModelTests.onlyTextKindsCanSummarize`, `LocalModelTests.entriesWithoutAKindAreChatUnlessNamedForMedia`
- **Needs:** local-agent running

**Steps**

1. Set *Model id* to `hf:nobody/missing-model` and click **Check Status**.
2. Set it to a speech model the gateway lists (e.g. a Whisper id).

**Expected**

- Step 1: *Model hf:nobody/missing-model isn't available. Call list_models / run models-on.*
- Step 2: *<id> isn't a chat or vision model (local-agent kind: <kind>).*

## The board's model on disk

### BRD-037 · A model path the gateway already serves runs through the gateway

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `LocalModelTests.matchesInventoryPathThroughSymlinks`
- **Needs:** local-agent serving a model whose `list_models` entry has a `path`

**Steps**

1. Turn summaries on. Open *Model and gateway*, click **Choose…** and pick that model's folder (or a symlink to it).

**Expected**

- The caption under *Model path* reads *MLX text model · runs via local-agent (<gateway id>)*.
- *Model id* is relabelled *Model id (unused while a model path is set)* and greyed out.
- **Clear** appears next to **Choose…**; clicking it empties the path and the caption returns to *Empty: local-agent
  runs the model id below. Or choose an MLX or Hugging Face folder, or a .gguf file.*

### BRD-038 · An MLX folder runs directly with mlx-lm

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`, `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** `LocalModelTests.mlxTextAndVisionFolders`, `LocalModelTests.mlxFolderRunsDirectlyWithAPythonThatHasMLX`, `LocalModelTests.mlxRouteReadsTheMarkedLineAndIgnoresNoise`
- **Needs:** a Python with `mlx-lm`; an MLX text model folder (`config.json` + `*.safetensors`) the gateway doesn't list

**Steps**

1. Turn summaries on and choose the folder with **Choose…**.
2. Run an agent session.

**Expected**

- The caption reads *MLX text model · runs with mlx-lm on this Mac* and the subtitle *Local LLM ready*.
- A summary appears on the card within 2 minutes (the reply timeout is 120 seconds).
- Typing a path by hand updates the caption about 0.3 seconds after you stop typing, without pressing Return.

### BRD-039 · A folder with a vision config runs with mlx-vlm, text only

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`
- **Automated by:** `LocalModelTests.mlxTextAndVisionFolders`, `LocalModelTests.nullVisionConfigIsATextModel`
- **Needs:** a Python with `mlx-vlm`; a Qwen-VL style MLX folder

**Steps**

1. Choose the folder and run an agent session.

**Expected**

- The caption reads *MLX vision model · runs with mlx-vlm on this Mac*; summaries arrive as for a text model.
- A folder whose `vision_config` is `null` is treated as a text model.

### BRD-040 · A Hugging Face cache folder loads its pinned snapshot

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `LocalModelTests.huggingFaceCacheRepoLoadsPinnedSnapshot`
- **Needs:** a cached repo under `~/.cache/huggingface/hub/models--mlx-community--…`

**Steps**

1. Click **Choose…**; confirm hidden folders such as `.cache` are visible, and pick the `models--…` folder.
2. `ambient task model`

**Expected**

- The path is accepted and the caption names the MLX format.
- `ambient task model` shows `format` and a `loads` line with the `snapshots/<hash>` folder that `refs/main` points at.

### BRD-041 · A .gguf file runs with llama.cpp, one chat turn

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`, `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** `LocalModelTests.ggufFileAndFolderSkipProjector`, `LocalModelTests.ggufRepoWithAConfigFileStaysGGUF`, `LocalModelTests.llamaCppRunsOneChatTurn`, `LocalModelTests.llamaCppGetsThePromptFile`
- **Needs:** a text `.gguf` model; `brew install llama.cpp`

**Steps**

1. Uninstall llama.cpp, choose the `.gguf` file and click **Check Status**.
2. Install llama.cpp (`brew install llama.cpp`) and click **Check Status** again.
3. Choose a folder holding the model and an `mmproj-*.gguf`; then choose the `mmproj` file itself.
4. Run an agent session.

**Expected**

- Step 1: *GGUF models need llama.cpp: brew install llama.cpp.*
- Step 2: the caption reads *GGUF model · runs with llama.cpp on this Mac* and the status *Local LLM ready*.
- Step 3: the folder loads its first non-projector `.gguf`; choosing the projector file shows the alert *Ambient
  can't use this model* with *A vision projector, not a model. Choose the main .gguf file.* and leaves the path as it was.
- Step 4: `ps` shows `llama-completion` (or `llama-cli`) with `-m <model> -f <prompt file> … -st`, and a summary arrives.

### BRD-042 · Speech, image and video weights are refused

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientApp/Settings/Panes/BoardPane.swift`
- **Automated by:** `LocalModelTests.speechModelsAreMedia`, `LocalModelTests.problemsWithAChosenPath`, `LocalModelTests.missingAndMediaPathsAreUnavailable`
- **Needs:** a Whisper, Kokoro or Flux model folder

**Steps**

1. With a working model path set, click **Choose…** and pick the Whisper folder.
2. Type the Whisper folder's path into *Model path* by hand.

**Expected**

- Step 1: an alert *Ambient can't use this model* reading *<name>: Speech, image or video model can't write summaries.
  Nothing changed.*; the previous path stays.
- Step 2: the caption reads *Speech, image or video model · can't write summaries* and the status *<name> is a speech,
  image or video model. Choose a text model.*

### BRD-043 · Model folders that bring their own Python code are never run

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`
- **Automated by:** `LocalModelTests.foldersThatBringTheirOwnCodeAreRefused`, `LocalModelTests.modelFolderCodeNeverLoads`
- **Needs:** an MLX folder copy whose `config.json` you can edit; a Python with `mlx-lm`

**Steps**

1. Add `"model_file": "evil.py"` to the folder's `config.json` and choose it.
2. Remove it, instead add an `auto_map` entry pointing at a `.py` file in the folder that writes `/tmp/qa-pwned`, choose
   it and run an agent session.

**Expected**

- Step 1: the alert reads *<name>: It runs its own Python code (model_file in config.json), which Ambient won't load.
  Nothing changed.*
- Step 2: the run stops with *This model runs its own Python code, which Ambient won't load.* as the board status, and
  `/tmp/qa-pwned` is never created.

### BRD-044 · A chosen Python without the runtime is reported, not replaced

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModel.swift`, `Sources/AmbientCore/LocalAgent/TaskLLM.swift`
- **Automated by:** `LocalModelTests.chosenPythonWithoutMLXSaysSo`, `LocalModelTests.usrBinPythonNeedsTheDeveloperTools`, `LocalModelTests.failedProbesWaitUntilACheckAsksAgain`
- **Needs:** an MLX folder as the model path; a Python without `mlx-lm`

**Steps**

1. Set *Python for MLX (optional)* to that Python and press Return.
2. `pip install mlx-lm` into it and click **Check Status**.
3. Empty the field on a Mac without the developer tools.

**Expected**

- Step 1: *<python> can't import mlx_lm. Install it with pip install mlx-lm, set Python for MLX, or register the model
  with local-agent.* No other Python is tried.
- Step 2: *Local LLM ready* at once (a check you ask for retries failed probes).
- Step 3: Ambient never runs `/usr/bin/python3`, so macOS never offers to install the developer tools.

### BRD-045 · Direct runs stay offline and keep session text out of `ps`

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`
- **Automated by:** `LocalModelTests.mlxRouteReadsTheMarkedLineAndIgnoresNoise`
- **Needs:** an MLX model path in use; Little Snitch or `nettop` to watch connections

**Steps**

1. Run an agent session so a summary runs.
2. While it runs: `ps -Eww -o pid,command | grep -i mlx`, and watch network connections from the Python process.

**Expected**

- The Python runs `-c <script>` only: no prompt, title or project text appears in its arguments.
- Its environment has `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1` and `HF_DATASETS_OFFLINE=1`.
- It opens no network connection, even for a model whose weights are missing (it fails instead).
- Its working directory is `/`.

### BRD-046 · llama.cpp's prompt file is private and deleted after the run

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`
- **Automated by:** `LocalModelTests.llamaCppGetsThePromptFile`, `LocalModelTests.leftoverPromptFilesAreRemoved`
- **Needs:** a `.gguf` model path with llama.cpp installed

**Steps**

1. Run an agent session. While llama.cpp runs, `ls -l "$(getconf DARWIN_USER_TEMP_DIR)" | grep ambient-prompt-`.
2. After the summary lands, list again.
3. Force quit Ambient mid-run (Activity Monitor › Force Quit), reopen it, wait more than 10 minutes and let another
   llama.cpp summary run.

**Expected**

- Step 1: one `ambient-prompt-<UUID>.txt`, mode `-rw-------`.
- Step 2: it is gone.
- Step 3: the file left by the force quit stays until a later llama.cpp run finds it older than 10 minutes, which
  deletes it. Files younger than 10 minutes are left for whichever Ambient is using them.

### BRD-047 · An MLX model stays loaded for two minutes, then lets go

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`
- **Automated by:** `LocalModelTests.theLoadedModelAnswersAgainUntilAnotherIsAskedFor`
- **Needs:** an MLX model path in use

**Steps**

1. Let one summary run, then keep agents quiet.
2. Watch the Python process in Activity Monitor.
3. Choose a different model folder while one is loaded.

**Expected**

- The Python process stays for 120 seconds after the summary, then exits and its memory is freed.
- Summaries within those two minutes reuse it (no second Python appears).
- Choosing another model stops the loaded one; only one model process runs at a time.

### BRD-048 · Quitting Ambient stops the board's model

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/LocalModelRunner.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** `LocalModelTests.cancellingARunStopsItsRuntime`, `LocalModelTests.cancelledRunsStillWaitingNeverStart`
- **Needs:** an MLX or `.gguf` model path in use

**Steps**

1. Start a summary, and while the model process runs choose **Quit Ambient**.
2. Check Activity Monitor 5 seconds later.

**Expected**

- The model process (Python or llama.cpp) is gone within about 3 seconds of the quit, killed if it ignored the first
  signal; no new one starts.

### BRD-049 · `ambient task model` shows how the board runs its model

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/LocalAgent/TaskLLM.swift`, `Sources/ambient/MCPServer.swift`
- **Automated by:** `LocalModelTests.reportSaysHowItRuns`, `LocalModelTests.reportRoundTrips`, `MCPServerTests.readsEachOption`
- **Needs:** nothing special

**Steps**

1. With summaries off and no model path: `ambient task model`
2. With an MLX folder set: `ambient task model --json`
3. Quit Ambient, then `ambient task model`.

**Expected**

- Step 1 prints *Board model* then aligned lines: `summaries off`, `model_id hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit`,
  how it would run (resolved as if summaries were on) and `status`.
- Step 2 prints one JSON object with `summaries`, `model_path`, `format`, `runs` (*directly with mlx-lm*), `runtime`
  (the app's Python, not the shell's) and `status`.
- Step 3 prints *Ambient isn't running. Open Ambient.app, then try again.* and exits 1.

### BRD-050 · `ambient task model PATH` points the board at a model

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** `MCPServerTests.readsEachOption`, `LocalModelTests.setAndReplyRoundTrip`
- **Needs:** an MLX folder; Settings › Board open

**Steps**

1. `ambient task model ~/models/Qwen2.5-0.5B-Instruct-4bit --enable`
2. `ambient task model --python ~/venvs/mlx/bin/python`
3. `ambient task model --clear --disable`

**Expected**

- Step 1: Settings › Board shows the path and summaries turn on; the command prints the report with the new path.
- Step 2: *Python for MLX* shows the absolute path (relative paths are made absolute against the current folder).
- Step 3: the path empties, summaries turn off, and the model id is used again.

### BRD-051 · `ambient task model` refuses what can't work, and changes nothing

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/LocalAgent/LocalModel.swift`
- **Automated by:** `MCPServerTests.refusesWhatItCantRead`, `MCPServerTests.pythonMustBeAnExecutableFile`, `LocalModelTests.problemsWithAChosenPath`
- **Needs:** nothing special

**Steps**

1. `ambient task model models/qwen` (relative)
2. `ambient task model /nowhere/model`
3. `ambient task model --python /tmp`
4. `ambient task model a b` and `ambient task model --bogus`

**Expected**

- Step 1: *Use an absolute path.*, exit 1. Step 2: *Nothing at /nowhere/model.*, exit 1.
- Step 3: *No executable Python at /tmp. Nothing changed.*, exit 1.
- Step 4: *Usage: ambient task model [PATH|--clear] [--python PATH] [--enable|--disable] [--json]*, exit 64.
- In every case Settings › Board is unchanged.

### BRD-052 · Agents read and set the board's model through `ambient mcp`

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/MCPServer.swift`
- **Automated by:** `MCPServerTests.getAsksTheApp`, `MCPServerTests.setSendsThePathAndShowsHowTheAppRunsIt`, `MCPServerTests.setTaskModelPathTakesNoPython`, `MCPServerTests.saysWhenTheAppIsntThereOrSlow`, `MCPServerTests.aReportTheCLIMadeSaysSo`
- **Needs:** `claude mcp add ambient -- ~/.ambient/bin/ambient mcp`

**Steps**

1. In Claude Code, ask it to call `get_task_model`.
2. Ask it to call `set_task_model_path` with an MLX folder's absolute path and `enable: true`.
3. Ask it to set the Python for MLX through the tool.
4. Quit Ambient and ask for `get_task_model` again.

**Expected**

- Step 1 returns JSON with the same keys as `ambient task model --json`.
- Step 2 changes Settings › Board (path set, summaries on) and returns the new report.
- Step 3: the tool has only `path` and `enable`; there's no way to set a Python through MCP.
- Step 4 returns an error result *Ambient isn't running. Open Ambient.app, then try again.*

### BRD-053 · `set_task_model_path` refuses a bad path before it reaches the app

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/MCPServer.swift`, `Sources/AmbientCore/LocalAgent/LocalModel.swift`
- **Automated by:** `MCPServerTests.aPathThatCantWorkNeverReachesTheApp`
- **Needs:** `ambient mcp` added to an agent; a Kokoro or Whisper folder

**Steps**

1. Ask the agent to call `set_task_model_path` with the speech model's folder.

**Expected**

- The tool returns an error: *<name>: Speech, image or video model can't write summaries. Nothing changed.*
- Settings › Board still shows the previous model.

### BRD-054 · Teaching the summarizer with Anthropic happens only when you run it

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/LocalAgent/TaskSkillBootstrap.swift`, `Sources/AmbientCore/LocalAgent/TaskSkillPack.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `TaskLLMTests.bootstrapParserAcceptsLabeledJSON`, `TaskLLMTests.saveAndLoadRoundTrip`
- **Needs:** an Anthropic key you may use; a network monitor (Little Snitch or `nettop`)

**Steps**

1. With no key in the Keychain or `ANTHROPIC_API_KEY`, run `ambient task skill-bootstrap`.
2. Store a key (`security add-generic-password -s <service> -a anthropic -w`) and run it again.
3. `ls -l ~/.ambient/task-skill.json` and read it.
4. Turn summaries on and run agent sessions for 10 minutes while watching the network.

**Expected**

- Step 1: *No Anthropic key in Keychain or ANTHROPIC_API_KEY. Stash it first, then re-run.* with the `security` command
  to run, exit 1.
- Step 2: *Bootstrapping local task skill pack (Anthropic once)…* then *✓ Wrote ~/.ambient/task-skill.json · N
  examples · source anthropic-bootstrap*, after one request to `api.anthropic.com`.
- Step 3: mode `-rw-------`; the file holds hints and examples, never the key.
- Step 4: no connection to `api.anthropic.com` or any address but loopback.
- Settings › Board › *Model and gateway* reads *Skill pack: anthropic-bootstrap · N examples (~/.ambient/task-skill.json)*.

**Known gap:** the success note says *Enable Settings › Board › Summarize tasks with local LLM. Runtime stays on
local-agent MCP.*, but the toggle is labelled *Summarize tasks on this Mac*, and summaries can also run directly with
MLX or llama.cpp.

### BRD-055 · `ambient task skill-status` says which skill pack is in use

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/LocalAgent/TaskSkillPack.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. With no `~/.ambient/task-skill.json`: `ambient task skill-status`
2. After a bootstrap, run it again.

**Expected**

- Step 1: *! No ~/.ambient/task-skill.json yet — using bundled seed. Run ambient task skill-bootstrap once.*, exit 0;
  Settings › Board says the skill pack is *the one that comes with Ambient*.
- Step 2: *✓ Skill pack: ~/.ambient/task-skill.json* and *source=anthropic-bootstrap examples=8 hints=N*.
- A `task-skill.json` with no examples falls back to the bundled seed.

### BRD-056 · Remote sessions are summarized only with their own opt-in

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppModel.swift`, `Sources/AmbientCore/TaskStore.swift`
- **Automated by:** none
- **Needs:** a paired remote machine with an agent running; summaries on with a working model

**Steps**

1. With the remote-summaries setting in Settings › Agents › Other Machines off, run a session on the remote machine.
2. Turn it on and run another.

**Expected**

- In step 1 the remote task gets no summary and no prompt about it reaches the gateway or a model process.
- In step 2 its card gains a summary; a summary of remote text is reduced to plain text before it is shown or printed
  by `ambient tasks`.

## Feature requests

### BRD-057 · Suggest a Feature opens the public request board and sends nothing

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/FeatureRequests.swift`
- **Automated by:** `FeatureRequestsTests.opensTheBoardTaggedWithTheAppAndVersion`, `FeatureRequestsTests.defaultsToTheRunningVersion`, `FeatureRequestsTests.websiteIsTheHomepage`
- **Needs:** a default browser

**Steps**

1. Choose **Suggest a Feature…** in the menu bar.
2. In Settings › General, click *Suggest or vote* next to *Feature requests*, then *yaml.cafe* next to *Website*.

**Expected**

- Steps 1 and 2 open `https://yaml.cafe/requests/?from=app&v=0.10.0` (the running version) in the default browser.
- *yaml.cafe* opens `https://yaml.cafe/`.
- Ambient itself makes no network request: the browser is the only thing that goes online.
