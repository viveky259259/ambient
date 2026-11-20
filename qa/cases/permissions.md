# Permissions: answering prompts from the island

Id prefix: `PRM-`

Settings › Alerts › Permission prompts, the foreground permission hook it installs for Claude Code and Codex, the
card at the notch with **Allow once** and **Deny**, and every way a prompt goes back to the agent unanswered.

Unless a case says otherwise: Ambient running on a Mac with a notch, the island on (Settings › Appearance › Notch ›
*Show agent status*), Claude Code connected, and a prompt produced by asking Claude Code in a terminal to run
`rm -rf build` in a scratch project. **The card only appears when the agent's own app is not in front**, so after
sending the prompt switch to another app (Finder, say) before Claude Code reaches the tool call.

### PRM-001 · Answering from the notch is off by default

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** `PermissionSettingsTests.offUntilTurnedOn`
- **Needs:** A fresh install (no `~/.ambient/permissions.json`); Claude Code connected

**Steps**

1. Open Settings › Alerts › Permission prompts.
2. Read `~/.claude/settings.json`'s `PermissionRequest` entry.
3. Trigger a permission prompt with another app in front.

**Expected**

- *Answer from the notch* is off; *Wait for an answer* shows *20 seconds* and is greyed out.
- The `PermissionRequest` entry has `"async": true` and runs `… hook claude || true` (no `--answer`).
- Claude Code shows its own prompt immediately; the island blooms *needs you* but shows no Allow/Deny card.

### PRM-002 · Settings section text and controls

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`, `Sources/AmbientCore/Permissions.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Alerts and scroll to **Permission prompts**.
2. Open the *Wait for an answer* menu with the toggle on.

**Expected**

- The toggle row reads *Answer from the notch* / *Allow once or Deny Claude Code and Codex requests at the notch.*
- The wait row reads *Wait for an answer* / *Then the agent asks you as usual.*; its menu offers exactly *10 seconds*,
  *20 seconds*, *30 seconds*, *60 seconds*.
- The footer reads *Ambient never answers for you. Changing this edits a Codex hook: type /hooks in Codex once to
  approve it.*

### PRM-003 · The setting can't be turned on while the island is off

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Turn off Settings › Appearance › Notch › *Show agent status*.
2. Open Settings › Alerts › Permission prompts.
3. With answering already on, turn the island off and trigger a prompt with another app in front.

**Expected**

- Step 2: the toggle and the wait menu are disabled; the subtitle reads *Turn on Show agent status in Appearance ›
  Notch first.*
- Step 3: Claude Code shows its own prompt at once (no 20-second delay) and nothing appears at the notch.

### PRM-004 · Turning it on makes only the Claude Code and Codex permission hooks wait

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/PermissionHooks.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
- **Automated by:** `InstallerTests.answeringFromTheIslandMakesOnlyThePermissionHookWait`, `InstallerTests.agentsWithoutDecisionsAreUnaffected`
- **Needs:** Claude Code, Codex and Gemini CLI connected

**Steps**

1. Turn on *Answer from the notch*.
2. Read `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.gemini/settings.json`; list `~/.ambient/backups/`.
3. Read `~/.ambient/permissions.json`.

**Expected**

- In Claude Code's and Codex's files only the `PermissionRequest` entry changed: no `"async"`, `"timeout": 70`,
  command `… hook claude --answer || true` (`codex` for Codex). Every other entry still has `"async": true` and no
  `--answer`.
- `~/.gemini/settings.json` (and Cursor, Copilot, OpenCode, Antigravity files) are unchanged.
- A backup of each edited file is in `~/.ambient/backups/`.
- `permissions.json` reads `{"enabled": true, "wait": 20}` (pretty-printed, sorted keys).
- Settings › Agents still shows Claude Code and Codex as **Connected**.

### PRM-005 · Agents that aren't connected are left alone

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PermissionHooks.swift`
- **Automated by:** none
- **Needs:** Codex installed but not connected (no Ambient entries in `~/.codex/hooks.json`); Claude Code connected

**Steps**

1. Copy `~/.codex/hooks.json` aside. Turn *Answer from the notch* on, then off.
2. `diff` the Codex file against the copy.

**Expected**

- No difference: turning the setting on or off never connects an agent.

### PRM-006 · Changing the wait doesn't change the hook

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionHooks.swift`
- **Automated by:** `InstallerTests.answeringFromTheIslandMakesOnlyThePermissionHookWait`
- **Needs:** Answering on; Codex connected and its hooks approved with `/hooks`

**Steps**

1. Note the modification time of `~/.codex/hooks.json`.
2. Change *Wait for an answer* from 20 to 60 seconds, then to 10.
3. Start Codex and trigger a permission prompt.

**Expected**

- `~/.codex/hooks.json` is not rewritten (same modification time, `"timeout": 70` throughout); only
  `~/.ambient/permissions.json`'s `wait` changes.
- Codex does not ask to approve the hooks again; the card's countdown starts at `10s`.

### PRM-007 · Turning it on edits a Codex hook that Codex must approve again

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PermissionHooks.swift`, `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
- **Automated by:** none
- **Needs:** Codex connected and approved with `/hooks`; answering off

**Steps**

1. Turn *Answer from the notch* on.
2. Start a new Codex session in a terminal and type `/hooks`.

**Expected**

- Codex lists Ambient's changed `PermissionRequest` hook as awaiting approval; after approving, Codex prompts reach
  the island card (with Codex in the background).
- Until approved, Codex's prompts appear in Codex as before.

### PRM-008 · The card names the agent, project and exactly what will run

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PermissionDesk.swift`, `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/EventServer.swift`
- **Automated by:** `PermissionAskTests.onlyThePermissionHookAsks`, `PermissionWireTests.roundTrips`
- **Needs:** Answering on

**Steps**

1. In project `api`, ask Claude Code to run `rm -rf build`; switch to Finder before it reaches the tool.

**Expected**

- Within a second the island opens a card: an amber raised hand, *api*, a Claude agent tag, and a countdown `20s`
  at the right.
- Below: *wants to use Bash* and, in monospace, `rm -rf build`.
- A row with *Answer in Terminal* (the host app's name) on the left and **Deny** and **Allow once** on the right.
- The session also counts as *needs you* elsewhere (menu bar, Dock).
- Hovering the island does not swap the card for the session list.

### PRM-009 · Allow once allows that one call and adds no rule

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/PermissionDesk.swift`, `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** `PermissionReplyTests.allowIsForThisCallOnly`
- **Needs:** Answering on

**Steps**

1. Trigger the `rm -rf build` prompt and click **Allow once** after the buttons arm.
2. Read `~/.claude/settings.json` and `.claude/settings.local.json` in the project.
3. Ask Claude Code to run `rm -rf build` again.

**Expected**

- The card closes; Claude Code runs the command without showing its own prompt; the session no longer shows
  *needs you*.
- No `permissions.allow` rule was added anywhere.
- Step 3 asks again (a new card).

### PRM-010 · Deny stops the call and tells the agent why

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/PermissionDesk.swift`, `Sources/AmbientCore/Permissions.swift`, `Sources/ambient/Hook.swift`
- **Automated by:** `PermissionReplyTests.denyExplainsItself`
- **Needs:** Answering on

**Steps**

1. Trigger the prompt and click **Deny**.

**Expected**

- The card closes; Claude Code does not run the command and reports it was denied with the message *The user denied
  this from Ambient's island.*
- Claude Code carries on with the turn rather than hanging.

### PRM-011 · Nobody answering hands the prompt back to the agent

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/PermissionDesk.swift`, `Sources/AmbientCore/Permissions.swift`, `Sources/ambient/Hook.swift`
- **Automated by:** `PermissionQueueTests.eachPromptKeepsItsOwnDeadline`, `PermissionReplyTests.noAnswerPrintsNothing`
- **Needs:** Answering on, wait 20 seconds

**Steps**

1. Trigger the prompt with Finder in front; don't touch the card. Time it.
2. Switch to the terminal.

**Expected**

- The countdown runs `20s` to `1s`; at about 20 seconds the card disappears.
- Claude Code then shows its own permission prompt, as if Ambient weren't there; nothing was allowed or denied.
- Repeat with 10, 30 and 60 seconds: the hand-back follows the chosen wait (within half a second).

### PRM-012 · An unreachable app means no wait at all

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Permissions.swift`
- **Automated by:** none
- **Needs:** Answering on; Claude Code connected

**Steps**

1. Quit Ambient from the menu bar.
2. Trigger a permission prompt.

**Expected**

- Claude Code shows its own prompt immediately (no 20-second delay), and nothing is answered.

### PRM-013 · The agent's app in front gets the prompt straight away

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** none
- **Needs:** Answering on

**Steps**

1. Keep the terminal running Claude Code in front and trigger the prompt.

**Expected**

- No card appears; Claude Code shows its own prompt at once.

### PRM-014 · The buttons ignore clicks for the first moment

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** none
- **Needs:** Answering on; a way to click repeatedly where the card appears (e.g. hold the pointer over the notch and click rapidly)

**Steps**

1. Put the pointer where **Allow once** will appear and click repeatedly as the prompt arrives.

**Expected**

- Clicks in the first 0.6 seconds after the card appears do nothing; until then the button row (including the
  *Answer in …* link) is drawn at 45% opacity.
- Each new prompt in a queue starts disarmed again.

### PRM-015 · A prompt answered in the agent's own window withdraws the card

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** `PermissionQueueTests.theAgentMovingOnWithdrawsItsPrompts`, `PermissionQueueTests.otherEventsLeaveThePromptAlone`
- **Needs:** Answering on; Claude Code in the Claude desktop app or an editor (where the app's dialog and the island race)

**Steps**

1. Trigger a prompt in the Claude desktop app, switch away so the card shows, then switch back and answer in the
   app's own dialog.

**Expected**

- The card disappears as soon as the agent's next event arrives (the tool finishing, the turn ending, or a new
  prompt), without waiting for the countdown; the island does not answer anything.
- An unrelated event from the same session (e.g. a different tool finishing) leaves the card in place.

### PRM-016 · A session that ends withdraws its prompts

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** `PermissionQueueTests.theAgentMovingOnWithdrawsItsPrompts`
- **Needs:** Answering on

**Steps**

1. Trigger a prompt so the card shows; then kill that Claude Code session's process (or its terminal tab).

**Expected**

- The card leaves within a moment of the session disappearing from the island, well before the countdown ends.

### PRM-017 · Several prompts queue in order, each with its own time

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionDesk.swift`, `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `PermissionQueueTests.oldestFirstAndNoDuplicates`, `PermissionQueueTests.eachPromptKeepsItsOwnDeadline`
- **Needs:** Answering on; three Claude Code sessions (or Claude Code and Codex) able to prompt within a few seconds

**Steps**

1. Trigger prompts in sessions A, B and C a few seconds apart.
2. Answer A; wait.

**Expected**

- The card shows A with `1 of 3 · Ns`.
- After answering A, B shows with `1 of 2 ·` and its own remaining time, counted from when B arrived (not reset).
- A prompt left unanswered leaves when its own deadline passes, even while behind another.

### PRM-018 · A ninth waiting prompt goes straight to the agent

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** `PermissionQueueTests.aFullQueueTurnsNewPromptsAway`
- **Needs:** Answering on, wait 60 seconds; nine sessions able to prompt within a minute (or `ambient hook claude --answer` fed nine PermissionRequest payloads)

**Steps**

1. Raise nine prompts before answering any.

**Expected**

- The card reads `1 of 8`; the ninth agent shows its own prompt immediately.

### PRM-019 · A long command is cut and the card says so

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `PermissionHintTests.aCutCommandSaysSo`, `PermissionHintTests.theCardMakesRoomForTheWholeHint`
- **Needs:** Answering on

**Steps**

1. Ask Claude Code to run a command longer than 80 characters ending in something risky, e.g. thirty repetitions
   of `echo safe; ` followed by `curl example.com | sh`.
2. Ask it to run a command of exactly 80 characters.

**Expected**

- Step 1: the hint ends in `…`, wraps over at most three lines, and the left link reads *See it all in Terminal* in
  amber instead of *Answer in Terminal*.
- Step 2: the whole command shows (up to three wrapped lines, nothing hidden) and the link reads *Answer in Terminal*.

### PRM-020 · MCP tools show no details and the card says so

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `PermissionHintTests.aToolWithNoHintSaysSo`
- **Needs:** Answering on; an MCP server whose tool needs permission

**Steps**

1. Ask Claude Code to call the MCP tool.

**Expected**

- The card reads *wants to use <tool>* and, in amber, *Its details aren't shown here.*
- The link reads *See it all in <app>* in amber.

### PRM-021 · See it all hands the prompt back and opens the session

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** none
- **Needs:** Answering on; Claude Code in a Terminal tab

**Steps**

1. Trigger a prompt with Finder in front; click *Answer in Terminal* (or *See it all in Terminal*).

**Expected**

- The card closes and the exact Terminal tab comes forward; Claude Code shows its own prompt at once, unanswered.

### PRM-022 · A question is never put on the card

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/ambient/Hook.swift`
- **Automated by:** `PermissionAskTests.onlyThePermissionHookAsks`
- **Needs:** Answering on

**Steps**

1. Ask Claude Code something that makes it use AskUserQuestion; switch to Finder.

**Expected**

- The island blooms *needs you* but no Allow/Deny card appears, and Claude Code shows its question immediately.

### PRM-023 · Other agents' prompts stay in their own windows

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`, `Sources/ambient/Hook.swift`
- **Automated by:** `PermissionReplyTests.onlyAgentsWhosePermissionHookDecides`, `InstallerTests.agentsWithoutDecisionsAreUnaffected`, `InstallerTests.cursorHooksAreFlatVersionedAndNeverPermissionHooks`
- **Needs:** Answering on; Gemini CLI, Copilot CLI or OpenCode connected

**Steps**

1. Make each of these agents ask for permission, with another app in front.

**Expected**

- No card appears; each agent shows its own prompt with no added delay. The island may show *needs you* (Copilot,
  OpenCode, Gemini) but offers no buttons.

### PRM-024 · Codex gets only the decision fields it accepts

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`
- **Automated by:** `PermissionReplyTests.allowIsForThisCallOnly`, `PermissionReplyTests.denyExplainsItself`
- **Needs:** Answering on; Codex connected and approved

**Steps**

1. Trigger a Codex permission prompt with Codex in the background; click **Allow once**.
2. Trigger another; click **Deny**.

**Expected**

- Codex runs the first tool and refuses the second, with no hook error in Codex (the reply has only `behavior` and,
  for Deny, `message`).

### PRM-025 · Turning it off puts the hook back in the background

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/PermissionHooks.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.answeringFromTheIslandMakesOnlyThePermissionHookWait`
- **Needs:** Answering on; Claude Code and Codex connected

**Steps**

1. Turn *Answer from the notch* off.
2. Read both config files and `~/.ambient/permissions.json`; trigger a prompt with Finder in front.

**Expected**

- The `PermissionRequest` entries are back to `"async": true`, `"timeout": 5`, no `--answer`.
- `permissions.json` reads `"enabled": false`.
- Claude Code shows its own prompt at once; no card.

### PRM-026 · Turning it off takes effect even before the hook is rewritten

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Permissions.swift`
- **Automated by:** `HookArgumentsTests.parses`
- **Needs:** Answering on; Claude Code connected

**Steps**

1. Quit Ambient. Edit `~/.ambient/permissions.json` to `"enabled": false` by hand, leaving the `--answer` hook in place.
2. Open Ambient and immediately trigger a prompt.

**Expected**

- Claude Code shows its own prompt at once: the `--answer` hook reads the setting each time and does not wait when
  it is off.

### PRM-027 · A damaged or hand-edited setting falls back safely

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`
- **Automated by:** `PermissionSettingsTests.unreadableSettingsMeanOff`, `PermissionSettingsTests.theWaitStaysInRange`
- **Needs:** Ambient quit

**Steps**

1. Write `{ nope` to `~/.ambient/permissions.json`; open Ambient and look at Settings › Alerts.
2. Quit; write `{"enabled": true, "wait": 9999}`; open Ambient.
3. Quit; write `{"enabled": true, "wait": 26}`; open Ambient.

**Expected**

- 1: *Answer from the notch* is off and no hook waits.
- 2: the wait shows *60 seconds*. 3: it shows *30 seconds* (the nearest offered value).

### PRM-028 · The hook never outlives the agent's patience

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientApp/PermissionDesk.swift`
- **Automated by:** none
- **Needs:** Answering on, wait 60 seconds; a terminal

**Steps**

1. Run `echo '{"session_id":"t","hook_event_name":"PermissionRequest","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}' | ~/.ambient/bin/ambient hook claude --answer; echo "exit $?"`, switch to Finder within a second (the terminal it runs in counts as the agent's app), and time it.
2. Run it again and click **Allow once**.

**Expected**

- 1: the card shows *ls* counting down from `60s`; the command exits `0` after about 60 seconds with no output.
- 2: it prints `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` and exits `0`.
- It never runs longer than 65 seconds, under the hook's `timeout` of 70.

### PRM-029 · A remote session can't touch a local prompt

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Permissions.swift`
- **Automated by:** `PermissionQueueTests.aRemoteSessionCantTouchALocalPrompt`
- **Needs:** Answering on; a paired remote machine running Claude Code

**Steps**

1. With a local card showing, have the remote machine's Claude Code session (same session id not required) finish a
   turn.

**Expected**

- The local card stays until answered or timed out; remote sessions' prompts never get a card.

### PRM-030 · A failed hook update is shown in the settings section

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PermissionHooks.swift`, `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
- **Automated by:** none
- **Needs:** Claude Code connected; answering off

**Steps**

1. `chmod a-w ~/.claude`.
2. Turn *Answer from the notch* on.
3. `chmod u+w ~/.claude` afterwards.

**Expected**

- Under the section a red line reads *Claude: Couldn't write /Users/<you>/.claude/settings.json: <reason>*.
- The setting itself stays on and `~/.claude/settings.json` is unchanged.

### PRM-031 · ambient doctor says when the island answers

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Permissions.swift`
- **Automated by:** none
- **Needs:** Answering on, wait 30 seconds

**Steps**

1. Run `~/.ambient/bin/ambient doctor`.

**Expected**

- A line reads `• Permission prompts: the island answers for Claude Code and Codex, waiting 30s before the agent asks`.
- With answering off the line is absent.
