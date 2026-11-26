# Alerts

Id prefix: `ALR-`

Notifications and chimes for the moments that need you, the menu bar orb and its session list, Quiet
alerts, and click to return: a notification, an island row or a menu row bringing back the exact place the
agent runs. Settings live in Settings › Alerts.

Steps use `ambient emit` from a Terminal tab where an agent isn't needed. A session started that way
belongs to Terminal, so **switch to another app (Finder) before the event** whenever the step expects an
alert: Ambient stays quiet while the agent's app is in front. Defaults: notifications on, chimes on at
volume 0.6, finished turns longer than 20 seconds.

### ALR-001 · A needs-you notification says what the agent needs

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.waitingAlwaysAlertsRegardlessOfDuration`, `DescribeTests.everyWaitHasAOneLineReason`
- **Needs:** notifications allowed for Ambient

**Steps**

1. In a Terminal tab inside a folder named `api-server`, run `sleep 3; ambient emit waiting --session qa-n1 --agent Build --reason command --message "rm -rf build"` and switch to Finder at once.
2. Repeat with `--reason edit` and no `--message`.

**Expected**

- Step 1: a banner from Ambient titled `api-server needs you to approve a command`, subtitle `Build · Terminal`, body `rm -rf build`, with the needs-you chime.
- Step 2: the title reads `api-server needs you to review a change` and the body `Build is waiting for you.`

### ALR-002 · Finished turns notify only when longer than the threshold

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.longTurnFinishingAlerts`, `AlertPolicyTests.quickTurnFinishingStaysQuiet`
- **Needs:** notifications allowed for Ambient

**Steps**

1. In `api-server`, run `ambient emit working --session qa-n2 --agent Build; sleep 5; ambient emit done --session qa-n2 --agent Build` and switch to Finder.
2. Run `ambient emit working --session qa-n3 --agent Build; sleep 25; ambient emit done --session qa-n3 --agent Build` and switch to Finder.
3. Repeat step 2 with `--message "Release built"` on the `done`.

**Expected**

- Step 1: no banner and no chime (a 5-second turn is under the 20-second default).
- Step 2: a banner `api-server is done`, body `Build finished in 25s.`, and the rising done chime.
- Step 3: the body is `Release built`.

### ALR-003 · An error notifies whatever the turn's length

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.errorsAlert`
- **Needs:** notifications allowed for Ambient

**Steps**

1. In `api-server`, run `ambient emit working --session qa-n4 --agent Build; sleep 3; ambient emit error --session qa-n4 --agent Build` and switch to Finder.
2. Repeat with `--message "make failed"` on the `error`.

**Expected**

- Step 1: a banner `api-server stopped with an error`, body `Build couldn't finish the turn.`, with the falling error chime.
- Step 2: the body is `make failed`.

### ALR-004 · No banner or chime while you're in the agent's app, and it counts as seen

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Notifier.swift`, `Sources/AmbientApp/HostActivator.swift`
- **Automated by:** `AlertPolicyTests.noAlertWhenTheUserIsAlreadyThere`
- **Needs:** Mac with a notch; Claude Code in Terminal.app

**Steps**

1. Keep Terminal in front and ask Claude Code to run `rm -rf build` so it asks permission.
2. Watch the screen and listen for 5 seconds without touching anything.

**Expected**

- No banner and no chime.
- The island still blooms amber with `Approve a command · rm -rf build`.
- About 4 seconds after the prompt, still with Terminal in front, it counts as seen: the wings turn back to Claude's coral.

### ALR-005 · The banner withdraws itself once the prompt is answered

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** none
- **Needs:** Claude Code in Terminal.app; notifications allowed; Notification Center open-able

**Steps**

1. Ask Claude Code to run `ls` so it asks permission, and switch to Finder before the prompt shows.
2. After the banner appears, go back to Terminal by clicking its Dock icon (not the banner), approve the prompt in Claude Code, and let it run.
3. Open Notification Center.

**Expected**

- Once the agent runs again (it reports its next tool or finishes), the `needs you to approve a command` notification is gone from Notification Center.

### ALR-006 · Looking at the session withdraws its done or error banner

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** none
- **Needs:** notifications allowed

**Steps**

1. Produce a done banner as in ALR-002 step 2 and leave it unclicked.
2. Click the Terminal window (or the session's row in the menu bar).
3. Open Notification Center.

**Expected**

- The `api-server is done` notification is no longer listed.

### ALR-007 · One notification per session: a newer state replaces the older

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** none
- **Needs:** notifications allowed

**Steps**

1. In Finder's foreground, from a background Terminal tab run `sleep 3; ambient emit working --session qa-n5 --agent Build; ambient emit waiting --session qa-n5 --agent Build --reason question; sleep 2; ambient emit error --session qa-n5 --agent Build --message boom`, then switch to Finder.
2. Open Notification Center.

**Expected**

- Two banners appear in turn (needs you, then error), and Notification Center keeps only the latest: `api-server stopped with an error` · `boom`, grouped under that session.

### ALR-008 · Working never alerts, and a repeat of the same state doesn't alert twice

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.workingNeverAlerts`, `AlertPolicyTests.repeatedWaitingDoesNotAlertTwice`, `AlertPolicyTests.endedSessionsDoNotAlert`
- **Needs:** notifications allowed

**Steps**

1. With Finder in front, run from a background tab `sleep 3; ambient emit working --session qa-n6 --agent Build; ambient emit waiting --session qa-n6 --agent Build --reason question; sleep 3; ambient emit waiting --session qa-n6 --agent Build --reason question --message again`.
2. Then run `ambient emit end --session qa-n6`.

**Expected**

- `working` brings no banner and no chime.
- Only the first `waiting` brings a banner and chime; the second is silent.
- `end` brings nothing and the notification is withdrawn.

### ALR-009 · Tell me about finished turns sets the threshold for banners and chimes

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`, `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.quickTurnFinishingStaysQuiet`
- **Needs:** notifications allowed

**Steps**

1. Open Settings › Alerts and open the *Tell me about finished turns* menu.
2. Choose `All of them` and repeat ALR-002 step 1 (a 5-second turn).
3. Choose `Longer than 1 minute` and repeat ALR-002 step 2 (a 25-second turn).

**Expected**

- The menu offers `All of them`, `Longer than 10 seconds`, `Longer than 20 seconds` (selected on a fresh install), `Longer than 1 minute`, `Longer than 5 minutes`; the row's subtitle is `For banners and chimes.`
- Step 2: the 5-second turn brings a banner and chime.
- Step 3: the 25-second turn brings neither. Needs-you prompts alert either way.

### ALR-010 · Notifications and chimes switch independently

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`, `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.channelsFollowSettings`
- **Needs:** notifications allowed

**Steps**

1. In Settings › Alerts turn off *Show notifications*, keep *Play chimes* on, and trigger a needs-you as in ALR-001.
2. Turn notifications on and chimes off; trigger again with a new session id.
3. Turn both off; trigger again.

**Expected**

- Step 1: the needs-you chime plays with no banner.
- Step 2: a silent banner.
- Step 3: nothing at all; the island still blooms.
- With chimes off the Volume row is dimmed and can't be changed.

### ALR-011 · Notification permission control shows where macOS stands

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
- **Automated by:** none
- **Needs:** a Mac where Ambient's notification permission can be reset (`tccutil` does not reset it; remove Ambient in System Settings › Notifications or use a fresh user)

**Steps**

1. With notifications never asked for, open Settings › Alerts.
2. Click `Allow…` and choose Don't Allow in the macOS prompt.
3. Click `Open Privacy Settings…`, allow Ambient there, and return.

**Expected**

- Step 1: the *Show notifications* row (subtitle `When an agent needs you, finishes, or fails.`) shows an `Allow…` button beside its switch; the section footer reads `Ambient stays quiet while you're already in the app running the agent.`
- Step 2: the button becomes `Open Privacy Settings…`.
- Step 3: a green `Allowed` badge replaces it.

### ALR-012 · Each state has its own two-note chime

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Chimes.swift`
- **Automated by:** none
- **Needs:** speakers or headphones

**Steps**

1. In Settings › Alerts, select `Needs you`, `Done` and `Error` in the preview in turn and click `Play Chime` for each.

**Expected**

- Needs you: a double tap on the same high note (A5, 880 Hz), the second about 0.17 s after the first.
- Done: a rising pair, E5 then B5 about 0.11 s later, ringing out softly.
- Error: a falling pair, D5 then A4 about 0.14 s later, warmer in tone.
- All three are soft synthesized tones with a quick attack and a decay of well under two seconds; none is a macOS system sound.

### ALR-013 · Volume slider sets the chime level and previews on release

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`, `Sources/AmbientApp/Chimes.swift`
- **Automated by:** none
- **Needs:** speakers or headphones

**Steps**

1. In Settings › Alerts › Chimes, drag the Volume slider to about a quarter and let go.
2. Drag it to the far left and let go; trigger a needs-you as in ALR-001.

**Expected**

- Step 1: on release the done chime plays, noticeably quieter than at the default.
- Step 2: no sound on release, and the needs-you alert is silent (a banner still shows).

### ALR-014 · The notification preview shows a banner per moment

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/NotificationPreview.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Alerts and click `Needs you`, `Done` and `Error` in the segmented control.
2. Turn off *Show notifications*; then turn off *Play chimes* and change the selection again.

**Expected**

- A mock banner with Ambient's icon slides in from the right in the top-right of the preview for each choice: `api-server is done` / `All 42 tests pass. Ready for review.`; `api-server stopped with an error` / `Rate limited — retry in 2 minutes`; each with `Claude · Terminal` and `now`.
- With chimes on, each change of selection plays that state's chime; with chimes off it doesn't, but `Play Chime` still plays it.
- With notifications off the preview greys out with an `Off` badge.

**Known gap:** the code says the preview uses "the same words `Notifier` posts", but its needs-you banner reads `api-server needs your permission` / `Bash: rm -rf build`, while a real banner reads `api-server needs you to approve a command` / `rm -rf build`.

### ALR-015 · The menu bar orb takes the colour of the most urgent session

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`
- **Needs:** nothing special

**Steps**

1. With no sessions, look at Ambient's status item in a light and a dark menu bar.
2. Run `ambient emit working --session qa-m1 --agent Build`, then `ambient emit waiting` on it, then `done`, then `error` (each on a new session id, the previous ones ended).

**Expected**

- No sessions: a hollow ring that follows the menu bar's colour (black on light, white on dark).
- Otherwise a filled orb with a faint halo, in grey-blue (`#B4BCC6`, the custom agent's working colour), amber `#F5A524`, green `#3FB950` and red `#F85149` respectively.
- Hovering it shows the tooltip `Ambient`.

### ALR-016 · The menu bar counts waiting sessions and marks broken hooks

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** none
- **Needs:** Claude Code connected (for the hook problem)

**Steps**

1. Put three sessions into waiting with `ambient emit waiting --session qa-w$i --agent Build` for `i` in 1–3.
2. End them, then remove Ambient's hooks from `~/.claude/settings.json` by hand (keep a copy) and wait for the next hook check (or restart Ambient).
3. Open the menu, then restore the file.

**Expected**

- Step 1: the amber orb is followed by ` 3`; with one waiting session there is no number.
- Step 2: the item gains ` !`, and its tooltip reads `Ambient: ` followed by the problem.
- Step 3: the menu's first row is the problem, with a warning-triangle icon, ending `— Reconnect`.

### ALR-017 · The menu lists sessions with where, how long and what they're doing

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** `DescribeTests.clockSaysWhatTheTimeMeansForEachState`
- **Needs:** nothing special

**Steps**

1. With no sessions, click the menu bar orb.
2. Start three sessions with `ambient emit` (working, waiting, done) and click it again.
3. Start 14 sessions in all and click it again.

**Expected**

- Step 1: the first row reads `No agent sessions`.
- Step 2: the first row reads `3 sessions · needs you`; each session row has a coloured dot (working grey-blue, waiting amber, done green), the title, then smaller grey `Build · <clock>` (and `took …` for the finished one), and on a second line the status, such as `Answer a question`. Hovering a row shows `Open Terminal`.
- Long titles are cut at 48 characters and statuses at 60.
- Step 3: only the first 12 sessions are listed.

### ALR-018 · Mark All as Seen appears only when something finished or failed

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. With only working and waiting sessions, open the menu.
2. Add a done session and open it again; choose `Mark All as Seen`.

**Expected**

- Step 1: no `Mark All as Seen` item.
- Step 2: the item is there; after choosing it the done session's green dot is dimmed to a faint green (seen, now idle), the item is gone from the next menu, and the orb no longer shows green.

### ALR-019 · Quiet alerts silences banners, chimes and blooms for the time chosen

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`, `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `AlertPolicyTests.quietModeSilencesEverything`
- **Needs:** Mac with a notch; notifications allowed

**Steps**

1. Open the menu bar orb's `Quiet Alerts` submenu.
2. Choose `For 3 Hours`; trigger a needs-you, a long done and an error as in ALR-001 to ALR-003.
3. Open the menu again and choose `Resume Alerts (quiet until …)`; trigger a needs-you again.

**Expected**

- The submenu offers `For 1 Hour`, `For 3 Hours` and `Until Tomorrow`.
- After choosing, the orb has a diagonal slash, and the menu shows `Resume Alerts (quiet until <now + 3 h, short time>)` in place of the submenu.
- While quiet: no banners, no chimes, no island bloom; the island wings and the orb's colour still change.
- `Until Tomorrow` sets the time to 8:00 the next morning.
- After resuming, the slash goes and the needs-you alerts as usual.

### ALR-020 · Quiet alerts end on their own

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** none
- **Needs:** notifications allowed; a way to wait an hour, or a dev build where `quietUntil` can be set with `defaults write com.viveky259259.Ambient quietUntil -date "<a minute from now>"` before launch

**Steps**

1. Start quiet alerts so that they end in a minute.
2. Wait until the time has passed, then wait 5 seconds more.
3. Trigger a needs-you.

**Expected**

- Within about 5 seconds of the end time the slash leaves the orb, and the menu offers `Quiet Alerts` again.
- The needs-you brings a banner and chime.

### ALR-021 · Chimes play during a macOS Focus; banners follow the Focus

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Chimes.swift`, `Sources/AmbientApp/Notifier.swift`
- **Automated by:** none
- **Needs:** notifications allowed

**Steps**

1. Turn on Do Not Disturb in Control Center.
2. Trigger a needs-you as in ALR-001.

**Expected**

- macOS holds the banner (it appears in Notification Center, not on screen), as for any app without a Focus exception.
- The needs-you chime still plays: Ambient's chimes are its own sounds and don't read Focus. Use Quiet alerts to silence them.

### ALR-022 · Click to return opens the exact chat in Claude's desktop app

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`
- **Automated by:** `FocusPlannerTests.claudeDesktopOpensTheExactChat`, `FocusPlannerTests.malformedHostSessionIdsAreNotLinked`
- **Needs:** Claude desktop app with Claude Code sessions connected; two chats

**Steps**

1. In Claude's desktop app start Code sessions in two chats; in chat A ask for something long, then open chat B.
2. Switch to Finder. When chat A finishes, click its banner (or its island row, or its menu row).

**Expected**

- Claude's desktop app comes forward showing chat A (opened by `claude://code/continue?session=local_…&source=ambient` in Claude itself, not in a browser), not chat B.
- No project window is raised by title instead.

### ALR-023 · Click to return opens the exact thread in Codex's app

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`
- **Automated by:** `FocusPlannerTests.codexAppOpensTheThread`, `FocusPlannerTests.codexInATerminalGoesToTheTerminalNotTheApp`
- **Needs:** Codex desktop app and Codex CLI connected

**Steps**

1. In Codex's app, run a task in thread A, then open thread B.
2. Switch to Finder and click thread A's row on the island when it finishes.
3. Run Codex CLI in a Terminal tab with the Codex app also open; click that session's row.

**Expected**

- Step 2: Codex's app comes forward on thread A.
- Step 3: Terminal comes forward on the CLI's tab; the Codex app is not opened.

### ALR-024 · Click to return selects the exact Terminal tab

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`
- **Automated by:** `FocusPlannerTests.terminalIsRecognizedByTermProgramToo`
- **Needs:** Terminal.app with two windows, several tabs each

**Steps**

1. Start a Claude Code session in the second tab of a window, then minimise that window.
2. In Finder, click the session's row in the menu bar.
3. If macOS asks whether Ambient may control Terminal, click Allow, and click the row again.

**Expected**

- First time only: the macOS Automation prompt for Terminal.
- Terminal comes forward with that window restored from the Dock, in front of the other window, on the session's tab.
- If Automation is denied, Terminal still comes forward, on whichever tab it was showing.

### ALR-025 · Click to return selects the exact iTerm2 session

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`
- **Automated by:** `FocusPlannerTests.itermSelectsTheSession`
- **Needs:** iTerm2 with split panes in several tabs

**Steps**

1. Start an agent in the right split of the third tab; select another tab.
2. From Finder, click the session's banner.

**Expected**

- iTerm2 comes forward on the third tab with the right split selected (after the one-time Automation prompt).

### ALR-026 · Click to return selects the tmux pane, then its terminal tab

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`, `Sources/AmbientCore/Host.swift`
- **Automated by:** `FocusPlannerTests.tmuxSelectsThePaneThenTheClientTab`, `HostTests.capturesReturnAddressesFromTheEnvironment`
- **Needs:** tmux installed (Homebrew or `/usr/bin`); Terminal.app or iTerm2

**Steps**

1. In a Terminal tab, start tmux with two windows; in window 2 split into two panes and run `ambient emit waiting --session qa-tmux --agent Build --reason question` in the lower pane.
2. Select window 1 in tmux and another Terminal tab; switch to Finder.
3. Click the session's row on the island.

**Expected**

- tmux switches to window 2 with the lower pane active.
- Terminal comes forward on the tab attached to that tmux client.

### ALR-027 · Click to return focuses the cmux pane

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`
- **Automated by:** `FocusPlannerTests.cmuxFocusesTheSurface`
- **Needs:** cmux installed in /Applications or Homebrew

**Steps**

1. Run an agent in one cmux surface of a workspace; focus a different workspace.
2. From Finder, click the session's row in the menu bar.

**Expected**

- cmux comes forward with the agent's workspace and surface focused.

### ALR-028 · Click to return raises the editor window for the project

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientCore/Focus.swift`, `Sources/AmbientApp/HostActivator.swift`
- **Automated by:** `FocusPlannerTests.editorsRaiseTheProjectWindow`, `FocusPlannerTests.hintsStopAtTheHomeDirectory`
- **Needs:** VS Code or Cursor with two project windows (`~/code/api-server`, `~/code/web`); Accessibility access for Ambient, then without it

**Steps**

1. Run an agent in the integrated terminal of the `api-server` window, minimise that window, and bring the `web` window to the front.
2. Switch to Finder and click the session's row.
3. Remove Ambient from Privacy & Security › Accessibility and repeat.

**Expected**

- Step 2: the editor comes forward with the `api-server` window restored and in front (its title contains the folder name, or the parent `code` if the folder isn't in any title).
- Step 3: the editor app comes forward but the window in front is whichever was last; nothing errors.

### ALR-029 · With no precise route, the app comes forward; a closed terminal is never launched

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientApp/HostActivator.swift`
- **Automated by:** `FocusPlannerTests.noHostStillActivatesWhatItCan`
- **Needs:** Ghostty or WezTerm; Terminal.app

**Steps**

1. Run `ambient emit waiting --session qa-ghost --agent Build` in Ghostty, switch to Finder and click the row.
2. In Terminal.app run `ambient emit done --session qa-gone --agent Build`, then quit Terminal (the session remains for a moment), and click its row in the menu bar.

**Expected**

- Step 1: Ghostty comes forward (its frontmost window; Ambient has no tab route for it). The bloom card and row tooltip name it: `Open Ghostty`.
- Step 2: Terminal is not relaunched; nothing comes forward.

### ALR-030 · A notification for a session that has ended still opens its chat

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Notifier.swift`
- **Automated by:** none
- **Needs:** Claude desktop app; Settings › Board in use

**Steps**

1. Let a Claude desktop chat finish while you're in Finder, so a banner arrives.
2. End that Claude Code session (close the chat's session) so it leaves the island.
3. Click the banner in Notification Center.

**Expected**

- Claude's desktop app opens the chat the session belonged to, found through the task board.

### ALR-031 · Remote sessions never run local return routes

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Focus/**`, `Sources/AmbientApp/Notifier.swift`
- **Automated by:** `FocusPlannerTests.noHostStillActivatesWhatItCan`
- **Needs:** another machine connected under Settings › Agents › Other Machines

**Steps**

1. On the other machine, run an agent in tmux and let it finish; click its row on this Mac's island and in the menu.
2. From the other Mac's task board, open a chat that lives on this Mac.

**Expected**

- Step 1: no local app, tab or pane comes forward and no AppleScript or tmux runs; the session is marked seen. The notification subtitle names the machine.
- Step 2: on this Mac the chat comes forward with a silent banner `Opened from <other Mac>`, body the chat's title, subtitle `<agent> · <app>`.

### ALR-032 · Unsafe return addresses are dropped before anything runs

- **Priority:** P1
- **Type:** automated
- **Covers:** `Sources/AmbientCore/Focus.swift`, `Sources/AmbientApp/Focus/**`
- **Automated by:** `FocusPlannerTests.unsafeValuesAreDropped`, `FocusPlannerTests.trailingNewlinesDoNotSlipThrough`, `FocusPlannerTests.malformedHostSessionIdsAreNotLinked`
- **Needs:** nothing special

**Steps**

1. Run `swift test --filter FocusPlannerTests`.

**Expected**

- All pass: a tty, tmux pane, cmux id, socket path or Claude session id that doesn't match its strict pattern (including one ending in a newline) produces no route, and a tty reaches AppleScript only as an argument, never spliced into the script.
