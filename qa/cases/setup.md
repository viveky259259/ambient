# Setup: connecting agents

Id prefix: `SET-`

First run, the Welcome pane, connecting and disconnecting each agent from Settings › Agents › This Mac and from
`ambient install` / `ambient uninstall`, `ambient doctor` and `ambient status`, and keeping hooks working (the
menu bar's hook-health items).

Many cases edit real agent config files. Run them in a spare macOS user account, or back up `~/.claude`,
`~/.codex`, `~/.gemini`, `~/.cursor`, `~/.copilot`, `~/.config/opencode` and `~/.ambient` first. CLI-only cases can
run against a scratch home: `HOME=/tmp/qa-home ~/.ambient/bin/ambient …` (the CLI resolves every path from
`$HOME`, and `~/.ambient` from `AMBIENT_HOME` when set).

### SET-001 · First launch opens Settings on Welcome

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`
- **Automated by:** none
- **Needs:** A Mac where Ambient has never run (or `defaults delete com.viveky259259.Ambient setupCompleted`)

**Steps**

1. Open Ambient.app.

**Expected**

- The Settings window opens by itself on **Welcome**, and Ambient shows in the Dock and app switcher while it is open.
- The hero reads *Welcome to Ambient* with *Your desktop quietly shows what your coding agents are doing — and lights
  up when they need you.* under the app icon.
- A **Get set up** section lists three rows: *Connect your agents*, *Allow notifications*, *Watch the demo*, each
  with an empty circle until done.
- A large **Get Started** button sits at the bottom right and is the default button (Return presses it).

### SET-002 · Get Started finishes first run and closes the window

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
- **Automated by:** none
- **Needs:** First run (as SET-001)

**Steps**

1. On the first-run Welcome pane, press Return (or click **Get Started**).
2. Quit and reopen Ambient.
3. Open Settings again from the menu bar and select **Welcome**.

**Expected**

- Step 1 closes the window and Ambient leaves the Dock (menu-bar app again).
- Step 2 does not open Settings by itself.
- In step 3 the hero reads just *Ambient* and there is no **Get Started** button; the checklist is still shown.
- Closing the first-run window with its red close button instead of **Get Started** also counts as finishing first
  run: the next launch does not reopen it.

### SET-003 · Welcome counts the agents it found and connected

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.skipsAgentsThatAreNotInstalled`
- **Needs:** Claude Code and Codex installed (`~/.claude` and `~/.codex` exist), no Ambient hooks yet, no other agent directories

**Steps**

1. Open Settings › Welcome.
2. Connect only Claude Code from Settings › Agents, then go back to Welcome.

**Expected**

- Step 1: *Connect your agents* reads *0 of 2 connected* with a **Connect All** button.
- Step 2: it reads *1 of 2 connected*; the button is still there.
- On a Mac with no agent directory at all the row reads *No agents found yet. Install Claude Code, Codex or Gemini
  CLI.* and shows no button.

### SET-004 · Connect All connects every agent found

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.installsIntoMissingFileWhenAgentExists`, `InstallerTests.preservesForeignHooksAndKeyOrder`
- **Needs:** At least two agents installed (e.g. Claude Code and Codex), not connected

**Steps**

1. On Settings › Welcome, click **Connect All**.
2. Open Settings › Agents › This Mac.
3. Start a new Claude Code session in a terminal and send a prompt.

**Expected**

- Within a second the row's circle fills green, it reads *N of N connected*, and **Connect All** disappears.
- Every found agent shows a green **Connected** badge in Agents; agents not installed show **Not found** and were
  not touched (no config file created for them).
- `~/.ambient/agents.json` lists the connected agents.
- In step 3 the island shows the session working.

### SET-005 · Connect All skips an agent whose config can't be read, silently

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Setup/SetupModel.swift`, `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
- **Automated by:** none
- **Needs:** Claude Code and Codex installed; `~/.codex/hooks.json` containing `{ nope`

**Steps**

1. On Settings › Welcome, click **Connect All**.

**Expected**

- Claude Code is connected; `~/.codex/hooks.json` is unchanged byte-for-byte.
- The row reads *1 of 2 connected* and **Connect All** stays; clicking it again does nothing visible.
- Settings › Agents shows Codex CLI with a red **Config unreadable** badge and no button.

**Known gap:** the Welcome pane gives no reason why Connect All left an agent out; nothing on Welcome mentions the
unreadable file (README: *click **Connect All** to hook up every agent it found*).

### SET-006 · Allow notifications row asks once, then opens System Settings

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Setup/SetupModel.swift`, `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
- **Automated by:** none
- **Needs:** Notification permission for Ambient not yet decided (`tccutil reset All com.viveky259259.Ambient` or a fresh user)

**Steps**

1. On Welcome, use the control on *Allow notifications* and choose **Allow** in the macOS prompt.
2. In System Settings › Notifications, set Ambient to off (denied), then return to Ambient's Settings.
3. Use the control on the row again.

**Expected**

- After step 1 the row's circle fills green and the control disappears.
- After step 2 the row is not done again (refreshed when the window becomes active).
- Step 3 opens System Settings › Notifications rather than showing the macOS prompt again.

### SET-007 · Play Demo plays every state and ticks the row

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. On Welcome, click **Play Demo**.

**Expected**

- The demo starts on the island, the Dock and the menu bar.
- *Watch the demo* shows a filled green check for as long as the window stays open (it resets when Settings is
  reopened).

### SET-008 · Agents pane lists every agent with its state and config path

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** none
- **Needs:** Some agents installed, some not

**Steps**

1. Open Settings › Agents › This Mac.
2. Hover each agent's name; right-click a row.

**Expected**

- Seven rows in this order: Claude Code, Codex CLI, Gemini CLI, Antigravity, Cursor, Copilot CLI (with a grey
  **Beta** badge), OpenCode.
- Badges: **Connected** (green, button **Remove**), **Needs update** (amber, button **Update**), **Not connected**
  (grey, button **Connect**), **Not found** (grey, no button), **Config unreadable** (red, no button).
- Notes under the names: Antigravity *Prompts, tools and finished or failed turns. It never shows as needing you:
  Antigravity has no permission hook.*; Cursor *… It never shows as needing you: Ambient uses no hook that could block
  Cursor.*; Copilot CLI *Prompts, tools, permission prompts, questions, subagents and errors.*; OpenCode *OpenCode 1.4
  or later. OpenCode 2 runs plugins in its background service, so a click can't bring back its terminal.*
- The tooltip on a name is the config path with `~`, e.g. `~/.claude/settings.json`.
- The context menu offers **Copy Config File Path** (copies the `~` path) and **Show Config File in Finder**.
- The footer reads *Ambient adds background hooks that never slow your agent down, keeps a backup of every file it
  edits, and removes only its own entries.*

### SET-009 · Connect Claude Code adds one background hook per event

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- **Automated by:** `InstallerTests.hookCommandUsesHomeRelativeGuardedPath`, `InstallerTests.installsIntoMissingFileWhenAgentExists`
- **Needs:** Claude Code installed, not connected; a `~/.claude/settings.json` with some of your own settings and hooks

**Steps**

1. Settings › Agents › This Mac › Claude Code › **Connect**.
2. Open `~/.claude/settings.json`.
3. Start a new Claude Code session and run a tool.

**Expected**

- The badge turns **Connected** and the button **Remove**.
- `hooks` gains one group per event: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `PostToolUseFailure`, `PermissionRequest`, `Notification`, `PreCompact`, `PostCompact`, `SubagentStart`,
  `SubagentStop`, `Stop`, `StopFailure`, `SessionEnd`, each appended after your own groups.
- Each entry is `{"type": "command", "command": "[ -x \"$HOME/.ambient/bin/ambient\" ] && \"$HOME/.ambient/bin/ambient\" hook claude || true", "async": true, "timeout": 5}`;
  `SessionEnd` has no `async`.
- Your other settings and hooks are unchanged, in the same order, with the file's own indentation.
- The session shows on the island.

### SET-010 · Connect Codex shows the /hooks approval step

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- **Automated by:** `InstallerTests.codexSessionEndIsSynchronous`
- **Needs:** Codex CLI installed, not connected

**Steps**

1. Settings › Agents › This Mac › Codex CLI › **Connect**.
2. Start Codex in a terminal and send a prompt without approving anything.
3. Type `/hooks` in Codex and approve Ambient's hooks; restart Codex and send a prompt.

**Expected**

- After step 1 the row shows **Connected** and an amber note *Codex runs new hooks only after you approve them: type
  /hooks in Codex once.*
- `~/.codex/hooks.json` holds the Codex events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `PermissionRequest`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop`, `SessionEnd`), all
  `async: true` except `SessionEnd`, timeout 5.
- Step 2: nothing reaches the island until the hooks are approved.
- Step 3: the Codex session shows on the island.

### SET-011 · Connect Gemini CLI adds hooks named ambient, timed in milliseconds

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.geminiHooksAreNamedWithMillisecondTimeout`
- **Needs:** Gemini CLI installed (`~/.gemini` exists)

**Steps**

1. Connect Gemini CLI from Settings › Agents.
2. Open `~/.gemini/settings.json`; run a Gemini CLI session.

**Expected**

- `hooks` gains `SessionStart`, `BeforeAgent`, `BeforeTool`, `AfterTool`, `Notification`, `PreCompress`,
  `AfterAgent`, `SessionEnd`, each entry `{"name": "ambient", "type": "command", "command": "… hook gemini || true", "timeout": 1500}`.
- Gemini runs normally (no JSON parse error from a hook) and its session shows on the island.

### SET-012 · Connect Antigravity writes a hook set of its own

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.antigravityGetsAHookSetNamedAmbientWithTheEventInEachCommand`, `InstallerTests.antigravityIsFoundByAnyOfItsDataDirectories`
- **Needs:** Antigravity installed (any of `~/.gemini/antigravity`, `~/.gemini/antigravity-ide`, `~/.gemini/antigravity-cli`); the `agy` CLI

**Steps**

1. Connect Antigravity from Settings › Agents.
2. Open `~/.gemini/config/hooks.json`; run `agy` with a prompt that uses a tool.

**Expected**

- The file has a top-level `ambient` object with `SessionStart`, `PreInvocation`, `PreToolUse`, `PostToolUse`,
  `Stop`; each command ends `hook antigravity <Event> || true`; `PreToolUse` and `PostToolUse` are wrapped in
  `{"matcher": "*", "hooks": [...]}`; timeout 5.
- Any other hook set in the file is untouched.
- The session shows working and finishes on the island; it never shows *needs you*.

### SET-013 · Antigravity alone also makes Gemini CLI look installed

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`
- **Automated by:** none
- **Needs:** A Mac with Antigravity but without Gemini CLI (`~/.gemini/antigravity` exists, no `gemini` executable)

**Steps**

1. Open Settings › Agents and look at Gemini CLI.
2. Click **Connect All** on Welcome.

**Expected**

- Gemini CLI shows **Not connected** (not **Not found**), because `~/.gemini` exists.
- Connect All creates `~/.gemini/settings.json` with Gemini CLI hooks.

**Known gap:** Gemini CLI is detected by `~/.gemini` alone, which Antigravity also creates, so Connect All writes
hooks for an agent that isn't installed (README: *hook up every agent it found*).

### SET-014 · Connect Cursor uses only hooks that can't block it

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.cursorHooksAreFlatVersionedAndNeverPermissionHooks`, `InstallerTests.cursorKeepsTheUsersOwnHooks`
- **Needs:** Cursor installed (`~/.cursor` exists); optionally a `~/.cursor/hooks.json` with your own entries

**Steps**

1. Connect Cursor from Settings › Agents.
2. Open `~/.cursor/hooks.json`; in Cursor's agent run a shell command that needs approval.

**Expected**

- Entries are listed directly under each event (no groups): `sessionStart`, `beforeSubmitPrompt`, `postToolUse`,
  `postToolUseFailure`, `afterShellExecution`, `afterFileEdit`, `afterMCPExecution`, `preCompact`, `stop`,
  `sessionEnd`, each `{"command": "… hook cursor || true", "timeout": 5}`.
- There is no `preToolUse`, `beforeShellExecution`, `beforeMCPExecution` or `beforeReadFile` entry of Ambient's.
- A new file starts with `"version": 1`; an existing file keeps your entries next to Ambient's.
- Cursor's own approval prompt appears and works exactly as before; Ambient never approves or blocks it.

### SET-015 · Connect Copilot CLI writes a hook file of Ambient's own

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.copilotGetsAHookFileOfItsOwn`, `InstallerTests.anOwnedFileThatChangedNeedsUpdateAndUninstallRemovesIt`
- **Needs:** Copilot CLI installed (`~/.copilot` exists)

**Steps**

1. Connect Copilot CLI from Settings › Agents.
2. Open `~/.copilot/hooks/ambient.json`.
3. Click **Remove**.

**Expected**

- Step 1 creates the file (and `~/.copilot/hooks/` if missing) with `"version": 1` and one entry per event
  (`sessionStart`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `notification`,
  `preCompact`, `subagentStart`, `subagentStop`, `agentStop`, `errorOccurred`, `sessionEnd`), each
  `{"type": "command", "bash": "… hook copilot <event> || true", "timeoutSec": 5}`.
- No other file under `~/.copilot` changes.
- Step 3 deletes `ambient.json` and leaves a copy in `~/.ambient/backups/`; the badge returns to **Not connected**.

### SET-016 · Connect OpenCode writes the plugin, and edits to it are put back

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/OpenCodePlugin.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/HookDoctor.swift`
- **Automated by:** `InstallerTests.openCodeGetsAPluginThatExportsOneFunction`, `InstallerTests.openCodeOutsideHomeUsesTheAbsolutePath`, `OpenCodePluginTests.opencodeOne`, `OpenCodePluginTests.opencodeTwo`
- **Needs:** OpenCode 1.4 or later (`~/.config/opencode` or `~/.local/share/opencode` exists); Node to read the file

**Steps**

1. Connect OpenCode from Settings › Agents.
2. Open `~/.config/opencode/plugins/ambient.js`; start OpenCode and send a prompt.
3. Add a comment line to `ambient.js` with Ambient running and wait up to two minutes.

**Expected**

- The plugin's header says `ambient install opencode` wrote it and *Edits are overwritten*; it resolves the CLI as
  `join(homedir(), ".ambient/bin/ambient")` and has one default export `{ id: "ambient", server, setup }`.
- The OpenCode session shows working, then done, on the island.
- After step 3 Settings › Agents briefly shows **Needs update**, then the file is rewritten to Ambient's version
  (within about a minute, at the next hook check) with the edited copy in `~/.ambient/backups/`.

### SET-017 · Remove takes out only Ambient's entries

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`
- **Automated by:** `InstallerTests.uninstallRestoresTheOriginal`, `InstallerTests.uninstallPrunesHooksItCreated`, `InstallerTests.antigravityStaleHookSetNeedsUpdateAndUninstallRestoresTheFile`
- **Needs:** Claude Code connected; your own hook in the same event (e.g. a `PreToolUse` group running `echo mine`) and other settings

**Steps**

1. Copy `~/.claude/settings.json` aside before connecting; connect; then click **Remove** in Settings › Agents.
2. `diff` the file against the copy.

**Expected**

- The badge reads **Not connected**.
- `diff` shows no difference: your `echo mine` group, other settings, key order and indentation are as before;
  events and groups that only held Ambient's entries are gone.
- `~/.ambient/agents.json` no longer lists `claude`, so no *hooks were removed* problem appears in the menu bar.

### SET-018 · An empty hooks object survives connect then remove

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** none
- **Needs:** `~/.claude/settings.json` containing, on four lines with two-space indent, `{`, `  "model": "opus",`, `  "hooks": {}`, `}`

**Steps**

1. Copy the file aside; `ambient install claude`, then `ambient uninstall claude`.
2. `diff` the file against the copy.

**Expected**

- No difference: `"hooks": {}` is still there.

**Known gap:** uninstall drops a `hooks` object it empties, so the user's own empty `"hooks": {}` is removed (README:
*Every edit keeps your other hooks and settings byte-for-byte*).

### SET-019 · Removing Cursor deletes a hooks file that held only a version

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** none
- **Needs:** Cursor installed; `~/.cursor/hooks.json` containing only `{"version": 1}`, written by you before connecting

**Steps**

1. `ambient install cursor`, then `ambient uninstall cursor`.

**Expected**

- `~/.cursor/hooks.json` is back to `{"version": 1}`.
- When Ambient created the file itself (no file before connecting), uninstall deletes it, with a backup in
  `~/.ambient/backups/`.

**Known gap:** the code deletes any Cursor file left holding only `"version": 1`, including one the user wrote, so
the user's file is gone after uninstall (a backup remains).

### SET-020 · Every edit keeps a timestamped backup first

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.backsUpBeforeWriting`
- **Needs:** Claude Code with an existing `~/.claude/settings.json`

**Steps**

1. Note the file's contents; run `~/.ambient/bin/ambient install claude`.
2. List `~/.ambient/backups/`.

**Expected**

- The CLI prints `✓ Claude: hooks installed in ~/.claude/settings.json (backup: ~/.ambient/backups/claude-settings-YYYYMMDD-HHMMSS-mmm.json)`.
- That backup's contents equal the file before the install, byte-for-byte.
- A config file that didn't exist before gets no backup.

### SET-021 · A symlinked config stays a symlink and keeps its permissions

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.symlinkedConfigStaysASymlink`, `InstallerTests.filePermissionsArePreserved`
- **Needs:** `~/.claude/settings.json` a symlink into a dotfiles folder, mode `600`

**Steps**

1. Connect Claude Code; then `ls -l ~/.claude/settings.json` and the dotfiles target.

**Expected**

- `~/.claude/settings.json` is still a symlink to the same target; the target holds Ambient's hooks.
- The target's mode is still `-rw-------`.

### SET-022 · Copilot and OpenCode files don't follow symlinks or keep modes

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** none
- **Needs:** OpenCode installed; `~/.config/opencode/plugins/ambient.js` a symlink to a dotfiles copy of an older plugin, mode `600`

**Steps**

1. Click **Update** for OpenCode in Settings › Agents.
2. `ls -l ~/.config/opencode/plugins/ambient.js`.

**Expected**

- The link still points at the dotfiles copy, which holds the new plugin, with mode `600`.

**Known gap:** files Ambient owns (`~/.copilot/hooks/ambient.json`, the OpenCode plugin) are written atomically at
the link's own path, replacing the symlink with a plain file and default permissions (README: *follows symlinked
dotfiles, preserves file permissions*).

### SET-023 · Reconnecting is a no-op that writes nothing

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `InstallerTests.reinstallIsByteIdentical`
- **Needs:** Claude Code connected

**Steps**

1. Note the modification time of `~/.claude/settings.json` and the count of files in `~/.ambient/backups/`.
2. Run `~/.ambient/bin/ambient install claude`.

**Expected**

- It prints `✓ Claude: already set up in ~/.claude/settings.json` with no backup note.
- The file's modification time and the backup count are unchanged.

### SET-024 · Reinstall replaces stale or old-shape entries without duplicating

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- **Automated by:** `InstallerTests.reinstallReplacesStaleCommands`, `InstallerTests.entriesWithAnOldShapeNeedAnUpdate`
- **Needs:** Claude Code connected; Ambient not running (so the hook check doesn't repair first)

**Steps**

1. In `~/.claude/settings.json`, change one Ambient entry's command to `/old/place/.ambient/bin/ambient hook claude` and delete `"async"` from another.
2. Run `~/.ambient/bin/ambient doctor`, then `~/.ambient/bin/ambient install claude`.

**Expected**

- Doctor prints `! Claude: hooks are incomplete or outdated — run \`ambient install claude\`` and counts it as a
  problem; the Agents pane would show **Needs update** with an **Update** button.
- After install each event holds exactly one Ambient entry in the current shape; your own entries are untouched.

### SET-025 · A malformed settings file is never overwritten

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/ambient/Commands.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- **Automated by:** `InstallerTests.unparsableConfigIsNeverOverwritten`
- **Needs:** Claude Code installed; `~/.claude/settings.json` containing `{ "model": "opus",` (invalid JSON)

**Steps**

1. Open Settings › Agents.
2. Run `~/.ambient/bin/ambient install claude; echo $?`.

**Expected**

- Claude Code shows a red **Config unreadable** badge and no Connect button.
- The CLI prints `✗ Claude: Couldn't parse /Users/<you>/.claude/settings.json: <reason>. It was left untouched.`
  on stderr and exits `1`.
- The file is byte-for-byte unchanged and no backup is written.

### SET-026 · Valid JSON of the wrong shape is refused with a reason

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`, `Sources/AmbientApp/Setup/SetupModel.swift`, `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- **Automated by:** none
- **Needs:** Claude Code installed

**Steps**

1. Set `~/.claude/settings.json` to `[]` and click **Connect** in Settings › Agents.
2. Set it to `{"hooks": []}` and click **Connect**.
3. Set it to `{"hooks": {"Stop": "x"}}` and click **Connect**.

**Expected**

- Each time the row keeps **Not connected** and shows a red message under the name:
  1. `… /.claude/settings.json has an unexpected shape (the top level isn't an object). It was left untouched.`
  2. `… has an unexpected shape ("hooks" isn't an object). It was left untouched.`
  3. `… has an unexpected shape (hooks.Stop isn't a list). It was left untouched.`
- The file is unchanged each time. An empty or whitespace-only file is treated as `{}` and connects normally.

### SET-027 · ambient install with no arguments connects what it finds

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** none
- **Needs:** Ambient run once (so `~/.ambient/bin/ambient` exists); Claude Code and Codex installed, Gemini not

**Steps**

1. Quit Ambient. Run `~/.ambient/bin/ambient install; echo $?`.

**Expected**

- One line per agent: `✓ Claude: hooks installed in ~/.claude/settings.json …`, `✓ Codex: hooks installed in
  ~/.codex/hooks.json …` followed by the note *Codex asks you to trust new hooks: run /hooks in Codex once and approve
  Ambient's.*, and `– Gemini: not found, skipped` (dim) for each missing agent.
- A final note *Open Ambient.app to see sessions light up.* because the app isn't listening.
- Exit status `0`. `~/.ambient/bin/ambient` is a symlink to the bundled CLI.

### SET-028 · ambient install for a named agent that isn't installed fails

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.skipsAgentsThatAreNotInstalled`, `InstallerTests.customAgentsHaveNothingToInstall`
- **Needs:** Gemini CLI not installed (no `~/.gemini`)

**Steps**

1. `~/.ambient/bin/ambient install gemini; echo $?`
2. `~/.ambient/bin/ambient install foo; echo $?`
3. `~/.ambient/bin/ambient install custom; echo $?`

**Expected**

- 1: `✗ Gemini: Gemini doesn't appear to be installed (no ~/.gemini).`, exit `1`; no file created.
- 2 and 3: `✗ Unknown agent 'foo'.` (or `'custom'`) `Use claude, codex, gemini, antigravity, cursor, copilot, opencode.`,
  exit `64`.

### SET-029 · Dry runs show the change and write nothing

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.dryRunWritesNothing`
- **Needs:** Claude Code installed, not connected

**Steps**

1. `~/.ambient/bin/ambient install claude --dry-run`
2. Connect it for real, then `~/.ambient/bin/ambient uninstall claude --dry-run`.

**Expected**

- 1 prints `• Claude: would update ~/.claude/settings.json` followed by the whole new file; the file, the backups
  folder and `~/.ambient/agents.json` are unchanged.
- 2 prints `✓ Claude: would remove hooks from ~/.claude/settings.json` and the file as it would be; nothing changes.
- On an up-to-date agent the install dry run prints `✓ Claude: already up to date ~/.claude/settings.json`.

### SET-030 · ambient uninstall removes only Ambient's hooks, from every agent

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.uninstallRestoresTheOriginal`, `InstallerTests.cursorKeepsTheUsersOwnHooks`, `InstallerTests.anOwnedFileThatChangedNeedsUpdateAndUninstallRemovesIt`
- **Needs:** Every installed agent connected; your own hooks added beforehand to Claude Code, Codex, Gemini CLI, Cursor and a second hook set in `~/.gemini/config/hooks.json`

**Steps**

1. Save copies of every config file listed in README's *What Ambient changes on your system* table.
2. `~/.ambient/bin/ambient uninstall; echo $?`
3. `grep -rl 'bin/ambient' ~/.claude ~/.codex ~/.gemini ~/.cursor ~/.copilot ~/.config/opencode`

**Expected**

- One `✓ <Agent>: hooks removed from <file>` line per connected agent, `– <Agent>: not found, skipped` for missing
  ones, exit `0`.
- Step 3 finds nothing. `~/.copilot/hooks/ambient.json` and `~/.config/opencode/plugins/ambient.js` are gone; the
  `ambient` hook set is gone from `~/.gemini/config/hooks.json` and the other set remains.
- Every other file diffs clean against the copies from before connecting (your hooks, settings and order intact).
- `~/.ambient/agents.json` lists no agents. Running `ambient uninstall` again prints `– <Agent>: nothing to remove`.

### SET-031 · A removed Ambient never breaks the agent

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Install/HookInstaller.swift`
- **Automated by:** `InstallerTests.hookCommandUsesHomeRelativeGuardedPath`
- **Needs:** Claude Code connected

**Steps**

1. Quit Ambient and move `~/.ambient/bin/ambient` aside (or delete Ambient.app so the link dangles).
2. Run a Claude Code session with several tools and let it finish.

**Expected**

- Claude Code runs and finishes without a hook error or delay: each command is guarded
  `[ -x "$HOME/.ambient/bin/ambient" ] && … || true`.
- With the link back but the app quit, the session also runs normally (events are dropped).

### SET-032 · ambient doctor reports a healthy setup

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** Ambient running; Claude Code and Codex connected

**Steps**

1. `~/.ambient/bin/ambient doctor; echo $?`

**Expected**

- Output starts `Ambient doctor`, then `✓ App is running (<version>)`, `✓ Hook command: ~/.ambient/bin/ambient →
  /Applications/Ambient.app/…/ambient`, `✓ Claude: hooks installed`, `✓ Codex: hooks installed` with the note *Codex
  runs new hooks only after you approve them with /hooks.*, and `– <Agent>: not found` for missing agents.
- An agent that is installed but not connected (and never was) prints `! <Agent>: hooks not installed — run \`ambient install <agent>\`` without counting as a problem.
- It ends `Everything looks good.` and exits `0`.

### SET-033 · ambient doctor names each problem and exits 1

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/HookHealth.swift`
- **Automated by:** none
- **Needs:** Claude Code connected through Ambient

**Steps**

1. Quit Ambient; run `ambient doctor`.
2. Delete Ambient's entries by hand from `~/.claude/settings.json`; run `ambient doctor`.
3. Make `~/.codex/hooks.json` invalid JSON; run `ambient doctor`.
4. Run `AMBIENT_HOME=/tmp/$(printf 'x%.0s' {1..100}) ambient doctor`.

**Expected**

- 1: `✗ App isn't running — open Ambient.app` (stderr).
- 2: `✗ Claude: its hooks were removed since you connected it — run \`ambient install claude\``; when no agent has
  Ambient's hooks at all, also `✗ No agent is connected — run \`ambient install\``.
- 3: `✗ Codex: can't read ~/.codex/hooks.json: <reason>`.
- 4: `✗ Socket path is too long for macOS: … Set AMBIENT_HOME to a shorter path.`, plus a missing hook command:
  `✗ Hook command missing at … — open Ambient.app or run \`ambient install\``.
- Each run ends `N problem(s) found.` (`1 problem found.` for one) and exits `1`.

### SET-034 · ambient status lists sessions or says the app isn't running

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** Claude Code connected

**Steps**

1. With Ambient quit, run `ambient status; echo $?`.
2. Open Ambient, start two Claude Code sessions, run `ambient status`, then `ambient status --json`.

**Expected**

- 1: `✗ Ambient isn't running. Open Ambient.app, then try again.`, exit `1`.
- 2: a header `Ambient · 2 sessions · <mood>` then one line per session with a coloured `●`, the agent (`claude`),
  the title (at most 28 characters) and its status and clock; `--json` prints the sessions as pretty, key-sorted JSON
  with ISO 8601 dates. Piped or with `NO_COLOR=1`, no colour codes appear.

### SET-035 · Out-of-date hooks are repaired quietly at launch

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/HookDoctor.swift`, `Sources/AmbientCore/HookHealth.swift`
- **Automated by:** `HookHealthTests.outOfDateHooksAreRepairedNotReported`
- **Needs:** Claude Code connected; Ambient quit

**Steps**

1. Remove `"async": true` from one of Ambient's Claude Code entries (making it partial).
2. Open Ambient; check the menu bar and `~/.claude/settings.json`.

**Expected**

- Within a second of launch the entry is back to Ambient's shape, with the edited file in `~/.ambient/backups/`.
- The menu bar icon shows no **!** and the menu lists no hook problem.

### SET-036 · Hooks removed by an update show Reconnect in the menu bar

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/HookDoctor.swift`, `Sources/AmbientCore/HookHealth.swift`, `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** `HookHealthTests.onlyConnectedAgentsHaveProblems`, `AgentRecordTests.installingAndRemovingIsRemembered`, `HookHealthTests.everyProblemSaysWhatFixesIt`
- **Needs:** Claude Code connected; Ambient running

**Steps**

1. Remove every Ambient entry from `~/.claude/settings.json` by hand (simulating an agent update) and save.
2. Wait up to 70 seconds.
3. Open the menu bar menu and click the problem item.

**Expected**

- The menu bar title gains ` !`; its tooltip reads *Ambient: Claude's hooks were removed*.
- The menu shows a warning-triangle item *Claude's hooks were removed — Reconnect* above a separator.
- Clicking it reinstalls the hooks with no dialog; the **!** and the item disappear.

**Known gap:** README says hooks are re-checked *as soon as* a settings file changes; the app polls modification
dates on a 60-second timer (10 s tolerance), so it takes up to about 70 seconds.

### SET-037 · An unreadable settings file shows Show File and is never rewritten

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/HookDoctor.swift`, `Sources/AmbientCore/HookHealth.swift`, `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** `InstallerTests.unparsableConfigIsNeverOverwritten`
- **Needs:** Codex connected; Ambient running

**Steps**

1. Add a stray `,` to `~/.codex/hooks.json` so it isn't valid JSON; wait up to 70 seconds.
2. Click the problem item in the menu bar menu.
3. Fix the file; wait up to 70 seconds.

**Expected**

- The menu reads *Can't read Codex's settings — Show File* and the title shows **!**.
- Step 2 reveals `~/.codex/hooks.json` selected in Finder; the file is not modified.
- After step 3 the problem clears.

### SET-038 · Disconnected and never-connected agents raise no problem

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/HookHealth.swift`, `Sources/AmbientApp/HookDoctor.swift`
- **Automated by:** `HookHealthTests.onlyConnectedAgentsHaveProblems`, `AgentRecordTests.theFirstRecordCountsAgentsConnectedBeforeIt`, `HookHealthTests.aMacWithoutARecordCountsWhatsInstalled`
- **Needs:** Claude Code connected; Gemini CLI installed, never connected

**Steps**

1. Click **Remove** for Claude Code in Settings › Agents.
2. Make `~/.gemini/settings.json` invalid JSON.
3. Wait two minutes and open the menu bar menu.

**Expected**

- No hook problem item and no **!**: Claude Code was disconnected on purpose and Gemini CLI was never connected.
- Settings › Agents still shows Gemini CLI as **Config unreadable**.

### SET-039 · A busy terminal session whose hooks never fire is reported

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/HookHealth.swift`, `Sources/AmbientApp/HookDoctor.swift`, `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** `SilenceDetectorTests.aBusySessionThatNeverReportedIsSilent`, `SilenceDetectorTests.aSessionThatReportedIsFine`, `SilenceDetectorTests.cautiousAboutEverythingElse`
- **Needs:** Codex connected but its hooks not yet approved with `/hooks`; Ambient running

**Steps**

1. After Ambient has started, start Codex in Terminal and give it a long task (at least two minutes and ten CPU seconds of work).
2. Within a minute after that, open the menu bar menu and click *Codex's hooks stopped firing — Fix…*.

**Expected**

- The item appears only after the session is at least 120 seconds old and has used 10 s of CPU; an idle Codex, a
  session started before Ambient launched, or one started before the hooks were written never triggers it.
- Clicking it opens an alert titled *Codex's hooks stopped firing* reading *Codex runs new hooks only after you approve
  them: type /hooks in Codex. Ambient also rewrote its hooks, in case they'd been changed. \`ambient doctor\` checks the
  whole chain.*
- For Claude Code the advice is *Restart the session; agents read their hooks when they start.*
- `ambient doctor` never reports this problem (only the running app can see it).

### SET-040 · Hook-silence scan records nothing about processes but pid, path, start and CPU

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientCore/HookHealth.swift`
- **Automated by:** `AgentExecutableTests.executablesBelongToAgentsByPath`, `AgentExecutableTests.listingTerminalSessionsWorks`
- **Needs:** Claude Code connected; a code reader

**Steps**

1. Read `ProcessTree.interactiveAgents()` and `AgentExecutable.fingerprint` in `Sources/AmbientCore/HookHealth.swift`.
2. With Ambient running a while, list `~/.ambient/` and read `~/.ambient/agents.json`.

**Expected**

- The scan reads only each terminal-attached process's pid, executable path, start time, CPU time and parent pid;
  never arguments, environment or output. Fingerprints hold only path, size and modification time, in memory.
- `~/.ambient/agents.json` contains only `{"connected": [<agent names>]}`; no file under `~/.ambient` holds process
  lists or fingerprints.

### SET-041 · An agent update triggers a hook re-check

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/HookDoctor.swift`, `Sources/AmbientCore/HookHealth.swift`
- **Automated by:** `AgentExecutableTests.anUpdateChangesTheFingerprint`
- **Needs:** Claude Code connected via a `claude` in `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`; Ambient running

**Steps**

1. Make Ambient's Claude Code hooks partial by hand without changing the file's modification time (`touch -r` the
   original afterwards).
2. Update Claude Code (or `touch` its resolved executable).
3. Wait up to 70 seconds.

**Expected**

- The hooks are rewritten to Ambient's shape within about a minute of the executable changing, without waiting for
  the ten-minute re-check.

### SET-042 · Hooks are re-checked every ten minutes

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/HookDoctor.swift`
- **Automated by:** none
- **Needs:** Claude Code connected; Ambient running; a way to change the file without changing its modification time

**Steps**

1. Make Ambient's Claude Code hooks partial, then restore the file's modification time with `touch -r`.
2. Wait 11 minutes.

**Expected**

- Within ten to eleven minutes the hooks are back in Ambient's shape, with a backup of the edited file.
