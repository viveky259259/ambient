# Island

Id prefix: `ISL-`

The notch island: what it shows for each state, how it blooms and settles, the hover list, where it sits on
Macs with and without a notch, and its settings pane (Settings › Appearance › Notch).

Most steps drive a session with `ambient emit` from a Terminal tab, so they need no agent and give exact
timings. Run each `emit` from the same tab; the session lasts while that tab's shell is alive. Colours are
from `Palette` in `Sources/AmbientCore/Policy.swift`: Claude coral `#D97757`, Codex green `#10A37F`, custom
agents grey-blue `#B4BCC6`, needs-you amber `#F5A524`, done green `#3FB950`, error red `#F85149`, idle grey
`#8B949E`.

### ISL-001 · Collapsed island shows a working session as a breathing orb in the agent's colour

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/StateGlyph.swift`, `Sources/AmbientApp/Island/IslandViewModel.swift`, `Sources/AmbientApp/Colors.swift`
- **Automated by:** `IslandPolicyTests.workingIsShownOnlyWhenWanted`, `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`
- **Needs:** Mac with a notch; Claude Code connected; Settings › Appearance › Notch › *Show while agents are working* on (the default)

**Steps**

1. With no other sessions, give Claude Code a prompt that takes at least a minute (for example, "read every file in this repo and summarise it").
2. Watch the notch for 70 seconds.

**Expected**

- Within a second a black pill grows out of the notch: the notch's width plus a 42-point wing on each side, the same height as the notch.
- The left wing has a coral (`#D97757`) orb that slowly swells and shrinks (one breath about every 3.2 s) with a glow that brightens and dims with it, and a short coral arc (about a quarter of a circle) spinning around it, one turn about every 1.4 s.
- The right wing shows how long the turn has run, in coral, ticking every second: `5s`, `59s`, then `1m`.
- The island never opens into a card while the agent only works.

### ISL-002 · Working colour follows the agent

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Colors.swift`, `Sources/AmbientApp/Island/StateGlyph.swift`
- **Automated by:** `GlowStyleTests.stylesPerMood`, `GlowStyleTests.hexColorsParse`
- **Needs:** Mac with a notch; Codex CLI connected

**Steps**

1. Start a long Codex turn with no other session active; look at the island.
2. End it, then in a Terminal tab run `ambient emit working --session qa-color --agent Build --tool make --detail "make release"`.
3. Run `ambient emit end --session qa-color`.

**Expected**

- Step 1: the orb, its arc and the right-wing timer are Codex green `#10A37F`.
- Step 2: they are grey-blue `#B4BCC6`, the colour for custom agents.
- Step 3: the island hides (shrinks back into the notch) within a second.

### ISL-003 · Needs-you bloom names what the agent needs, in amber, for 8 seconds

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/StateGlyph.swift`
- **Automated by:** `IslandPolicyTests.bloomsOnAttentionTransitions`, `DescribeTests.everyWaitHasAOneLineReason`, `NeedTests.toolsDecideTheNeed`
- **Needs:** Mac with a notch; Quiet alerts off

**Steps**

1. In a Terminal tab inside a folder named `api-server`, run `ambient emit working --session qa-wait --agent Build --tool make`.
2. Run `ambient emit waiting --session qa-wait --agent Build --reason command --message "rm -rf build"` and start a stopwatch.
3. Keep the pointer away from the top of the screen.

**Expected**

- Within a second the island opens into a frosted dark card hanging from the notch, at least 400 points wide and 74 points taller than the notch.
- The card shows an amber (`#F5A524`) orb pulsing quickly (about every 1.2 s) with a ring rippling outward and fading once per pulse; the title `api-server` in white; a grey-blue capsule reading `BUILD`; and below them `Approve a command · rm -rf build`.
- On the right: the time it has waited (`0s`, `1s`…) and `Open Terminal` in amber.
- At 8 seconds the card closes back to the wings: an amber pulsing orb on the left and an amber raised-hand symbol on the right.

### ISL-004 · Each kind of need reads as its own one-line headline

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `DescribeTests.everyWaitHasAOneLineReason`, `DescribeTests.activities`, `NeedTests.oldReasonsStillRead`
- **Needs:** Mac with a notch

**Steps**

1. For each reason below, run `ambient emit working --session qa-need --agent Build` then `ambient emit waiting --session qa-need --agent Build --reason <reason> --message detail` and read the bloom's second line.
2. Repeat once with `--reason banana`.

**Expected**

- `command` → `Approve a command · detail`; `edit` → `Review a change · detail`; `web` → `Allow web access · detail`; `access` → `Allow access outside the project · detail`; `plan` → `Review a plan · detail`; `question` → `Answer a question · detail`; `permission` → `Approve a tool · detail`.
- `banana` (unknown) reads as `Answer a question · detail`.
- Without `--message`, the line is the headline alone, with no trailing `·`.

### ISL-005 · Done bloom is green for 5 seconds and says how long the turn took

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/StateGlyph.swift`
- **Automated by:** `IslandPolicyTests.bloomsOnAttentionTransitions`, `DescribeTests.clockSaysWhatTheTimeMeansForEachState`
- **Needs:** Mac with a notch; Quiet alerts off

**Steps**

1. In a folder named `api-server`, run `ambient emit start --session qa-done --agent Build`, then `ambient emit working --session qa-done --agent Build --tool make`.
2. Wait about 25 seconds, then run `ambient emit done --session qa-done --agent Build --message "Release built"` and start a stopwatch.

**Expected**

- The island opens into a card with a green (`#3FB950`) filled circle carrying a dark checkmark, the title `api-server`, `BUILD`, and `Done · Release built`.
- The right side reads `just now · took 25s` (give or take a second) and `Open Terminal` in green.
- At 5 seconds the card closes to the wings: a green check badge on the left and, on the right, how long ago it finished in green (`just now` for the first 10 seconds, then `12s ago`…).

### ISL-006 · Error bloom is red for 5 seconds

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/StateGlyph.swift`
- **Automated by:** `IslandPolicyTests.bloomsOnAttentionTransitions`
- **Needs:** Mac with a notch; Quiet alerts off

**Steps**

1. Run `ambient emit working --session qa-err --agent Build --tool make`.
2. Run `ambient emit error --session qa-err --agent Build --message "make failed"` and start a stopwatch.

**Expected**

- The card shows a red (`#F85149`) filled circle with a dark exclamation mark and `Failed · make failed`.
- It closes after 5 seconds to wings with the red badge on the left and a red warning-triangle symbol on the right.

### ISL-007 · Starting or continuing work never blooms

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** `IslandPolicyTests.bloomsOnAttentionTransitions`
- **Needs:** Mac with a notch

**Steps**

1. Run `ambient emit start --session qa-calm --agent Build`.
2. Run `ambient emit working --session qa-calm --agent Build --tool make` three times, a few seconds apart.
3. Run `ambient emit waiting --session qa-calm --agent Build --reason question` twice, 2 seconds apart.

**Expected**

- Steps 1 and 2: the island stays collapsed (wings only); no card opens.
- Step 3: the first `waiting` blooms; the second, arriving while the session already needs you, does not restart the bloom or extend its 8 seconds.

### ISL-008 · A bloom closes as soon as what it announced is resolved

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. Run `ambient emit waiting --session qa-resolve --agent Build --reason command --message "ls"`.
2. Two seconds later, before the 8 seconds are up, run `ambient emit working --session qa-resolve --agent Build --tool ls`.

**Expected**

- The card closes at step 2 rather than staying for the full 8 seconds, and the wings turn back to the working colour (grey-blue orb with a spinning arc).

### ISL-009 · Quiet alerts keep the island collapsed but still show state

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** `IslandPolicyTests.bloomsOnAttentionTransitions`
- **Needs:** Mac with a notch

**Steps**

1. From the menu bar orb choose Quiet Alerts › For 1 Hour.
2. Run `ambient emit waiting --session qa-quiet --agent Build --reason command --message "rm -rf build"`.
3. Choose Resume Alerts from the menu bar.

**Expected**

- Step 2: no card opens; the wings show the amber pulsing orb and the raised hand.
- Hovering still opens the list, whose footer reads `Resume alerts` with a bell symbol.

### ISL-010 · A finished session stays green until seen, then the island settles

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`, `IslandPolicyTests.workingIsShownOnlyWhenWanted`
- **Needs:** Mac with a notch

**Steps**

1. In a Terminal tab, run `ambient emit working --session qa-seen --agent Build`, wait 25 s, then `ambient emit done --session qa-seen --agent Build`.
2. Switch to another app (Finder) and wait a minute.
3. Click the Terminal window.

**Expected**

- Step 2: after the 5-second bloom the wings keep the green check badge and the `…ago` time for the whole minute.
- Step 3: within a second the island shrinks back into the notch (the session is now idle and nothing else is active).

### ISL-011 · Clicking the bloom card takes you to the session and closes it

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; Claude Code in Terminal.app

**Steps**

1. In a Terminal tab, ask Claude Code to run `rm -rf build` so it asks permission.
2. Switch to Safari before the prompt appears.
3. When the amber card opens, click anywhere on it.

**Expected**

- The Terminal window comes forward on the tab running that Claude Code session.
- The card closes at once and does not reopen while the pointer stays over the notch; it can open again only after the pointer leaves and comes back.
- The wings turn from amber to Claude's working coral (the prompt now counts as seen).

### ISL-012 · Show while working off hides the island during work but not for what needs you

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Settings/Panes/IslandPane.swift`
- **Automated by:** `IslandPolicyTests.workingIsShownOnlyWhenWanted`
- **Needs:** Mac with a notch

**Steps**

1. In Settings › Appearance › Notch turn off *Show while agents are working*.
2. Run `ambient emit working --session qa-hide --agent Build --tool make`.
3. Run `ambient emit waiting --session qa-hide --agent Build --reason question`.
4. After the bloom, run `ambient emit working --session qa-hide --agent Build`.

**Expected**

- Step 2: nothing grows out of the notch.
- Step 3: the amber card opens as usual for 8 s, then the wings stay with the amber orb.
- Step 4: the island hides again.

### ISL-013 · Hovering a hidden notch still opens the list when there are sessions

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. With *Show while agents are working* off, run `ambient emit working --session qa-peek --agent Build`.
2. Move the pointer onto the notch and hold it still.
3. Repeat after `ambient emit end --session qa-peek`, with no sessions at all.

**Expected**

- Step 2: about 0.3 s after the pointer arrives, the list opens with the `qa-peek` row.
- Step 3: nothing opens; the notch stays plain hardware, and clicks there reach whatever is under it.

### ISL-014 · Turning the island off hides agent status but still shows voices

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/VoiceCards.swift`, `Sources/AmbientApp/Settings/Panes/IslandPane.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; a second Mac paired for voice sync

**Steps**

1. Turn off Settings › Appearance › Notch › *Show agent status at the notch*.
2. Run `ambient emit waiting --session qa-off --agent Build --reason command --message ls`.
3. Hover the notch.
4. From the menu bar choose *Record Voice for <other Mac>* and speak a few words.

**Expected**

- Step 2 and 3: nothing appears at the notch, and hovering opens nothing.
- Step 4: a card opens under the notch reading `For <other Mac>` with a running clock, then `Listening…` until words arrive, with a cancel (×) button and `Send`.
- *Show while agents are working* is greyed out while the first toggle is off.

### ISL-015 · Hovering the island lists the latest sessions

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandViewModel.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; two or three sessions (any agents)

**Steps**

1. With two or three sessions running, move the pointer onto the collapsed island and hold it.
2. Move the pointer away.

**Expected**

- About 0.12 s after the pointer arrives the island opens into a frosted card at least 440 points wide, one 48-point row per session, most urgent first.
- Each row has the state glyph, the title in white, the agent tag in capitals in the agent's colour, `+N agents` when it has subagents, a second line with the folder (when the title is a chat title) and the status, such as `Bash · npm test`, and the elapsed time on the right.
- A row highlights faintly under the pointer.
- The footer shows `Quiet 1h`, `Mark all seen` and, at the far right, `Settings`.
- About 0.3 s after the pointer leaves the card, the island closes.

### ISL-016 · Several active sessions show a dot each in the right wing

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`
- **Needs:** Mac with a notch

**Steps**

1. Run `ambient emit working` for sessions `qa-a`, `qa-b` (agent Build), then `ambient emit waiting --session qa-c --agent Build --reason question`, then `ambient emit working` for `qa-d`, `qa-e`.
2. After the bloom closes, look at both wings.

**Expected**

- The left wing shows the amber pulsing orb of `qa-c`, the most urgent session.
- The right wing shows four 6-point dots (never more than four), one amber and the others grey-blue, instead of a timer.

### ISL-017 · View all lists every session and starts short next time

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandViewModel.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. Start 12 sessions with `for i in $(seq 1 12); do ambient emit working --session qa-many-$i --agent Build; done`.
2. Hover the island.
3. Click `View all 12`, then scroll the list.
4. Click `Show fewer`; then move away and hover again after clicking `View all 12` once more.

**Expected**

- Step 2: five rows, and a footer button `View all 12` with a list symbol.
- Step 3: the card grows to ten rows tall and the remaining two scroll into view; the button reads `Show fewer` with an up chevron.
- Step 4: `Show fewer` returns to five rows; leaving and hovering again always opens with five rows.
- With five sessions or fewer there is no View all button.

### ISL-018 · Quiet 1h in the island footer silences alerts and flips to Resume alerts

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; one session

**Steps**

1. Hover the island and click `Quiet 1h`.
2. Hover again and read the footer; open the menu bar orb.
3. Click `Resume alerts`.

**Expected**

- After step 1 the footer button reads `Resume alerts` with a bell symbol (it was a slashed bell).
- The menu bar orb gains a diagonal slash, and its menu shows `Resume Alerts (quiet until <time one hour from now>)`.
- Step 3 brings back `Quiet 1h` and removes the slash.

### ISL-019 · Mark all seen settles every finished and failed session

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. Create one done (`qa-d1`), one error (`qa-e1`) and one waiting (`qa-w1`) session with `ambient emit`.
2. Hover the island and click `Mark all seen`.

**Expected**

- The wings no longer show green, red or amber: the done and error sessions now count as idle, and the waiting one as working (a seen prompt), so the left wing shows a grey-blue working orb.
- In the list, rows keep the glyph of what each session last did (check, exclamation, amber orb): rows describe the session, the wings say what wants attention.
- The menu bar orb turns grey-blue to match.

### ISL-020 · Settings in the island footer opens Settings and closes the island

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; one session

**Steps**

1. Hover the island and click `Settings`.

**Expected**

- The Ambient Settings window opens in front.
- The island closes at once and stays closed until the pointer leaves the notch and comes back.

### ISL-021 · Clicking a session row returns to it and the island stays closed

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; sessions in two different Terminal tabs

**Steps**

1. Run `ambient emit working --session qa-tab1 --agent Build` in tab 1 and `ambient emit done --session qa-tab2 --agent Build` in tab 2.
2. Switch to Finder, hover the island and click the `qa-tab2` row.

**Expected**

- Terminal comes forward with tab 2 selected.
- The island collapses at once and does not spring open again while the pointer is still over it.
- `qa-tab2` no longer counts as wanting attention: the wings show `qa-tab1`'s grey-blue working orb, not the green check.

### ISL-022 · The island never takes focus or blocks clicks around it

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/NotchShape.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; a text editor

**Steps**

1. With a session running, type in TextEdit and, while typing, hover the island and click `Quiet 1h`; keep typing.
2. With the island collapsed, click menu bar items just left and right of the wings, and the window title bar under the island's open area.

**Expected**

- TextEdit keeps keyboard focus throughout: the typed characters keep arriving and Ambient never becomes the active app.
- The first click on an island button acts (no extra click to "activate" the panel).
- Clicks outside the island's own shape reach the menu bar and windows below it.

### ISL-023 · Macs without a notch get a virtual island at the top centre of the menu bar

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandGeometry.swift`, `Sources/AmbientApp/Island/IslandController.swift`, `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** none
- **Needs:** Mac without a notch (Mac mini, Mac Studio, or an external display only); or a dev build with `defaults write com.viveky259259.Ambient debugVirtualNotch -bool true`

**Steps**

1. With no sessions, look at the top centre of the menu bar, then hold the pointer there.
2. Run `ambient emit working --session qa-virtual --agent Build`.

**Expected**

- Step 1: nothing is drawn while there are no sessions; holding the pointer at the top centre for about 0.3 s opens the card, reading `No agent sessions`.
- Step 2: a black pill appears centred in the menu bar, as tall as the menu bar, 120 points plus a 42-point wing each side, with the orb on the left and the timer on the right.

### ISL-024 · The island stays on the notched display and moves when displays change

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandGeometry.swift`, `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** MacBook with a notch and an external display

**Steps**

1. Connect the external display and, in System Settings › Displays, put the menu bar on the external display. Start a session.
2. Close the MacBook lid (clamshell), keeping the external display on.
3. Open the lid again.

**Expected**

- Step 1: the island stays around the MacBook's notch; the external display shows no island.
- Step 2: within a few seconds the island moves to the top centre of the external display's menu bar, as the virtual island (ISL-023).
- Step 3: it returns to the notch. There is only ever one island.

### ISL-025 · Reduce Motion stills the orbs

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/StateGlyph.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. Turn on System Settings › Accessibility › Display › Reduce motion.
2. Run `ambient emit working --session qa-rm --agent Build`, then `ambient emit waiting --session qa-rm --agent Build --reason question`.

**Expected**

- Working: a still grey-blue orb with a still quarter arc beside it; nothing breathes or spins.
- Needs you: a still amber orb with no ripple ring.
- The island still opens and closes with its usual spring.

**Known gap:** the orb reads Reduce Motion only when its state or colour changes. A glyph already on screen when the setting is turned on keeps breathing and spinning until the session changes state, and one built while it was on stays still after it's turned off.

### ISL-026 · The island shows over full-screen apps and on every Space

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. Start a session, then make Safari full screen (⌃⌘F).
2. Run `ambient emit waiting --session qa-fs --agent Build --reason question`.
3. Swipe between Spaces.

**Expected**

- The collapsed island stays visible at the notch over the full-screen app, and the needs-you card opens over it.
- It stays in place, without sliding, on every Space.

### ISL-027 · Collapsed the island is solid black; open it is dark glass with the notch kept black

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/NotchShape.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; a bright wallpaper; macOS 26 and an earlier macOS if available

**Steps**

1. With a session running, look closely at the collapsed island against a bright wallpaper.
2. Hover to open it.

**Expected**

- Collapsed: solid black, with small outward flares where it meets the top edge and gently rounded bottom corners, so it reads as the hardware notch grown wider.
- Open: larger flares and rounder (22-point) bottom corners, a soft shadow below, and a dark-tinted frosted glass (Liquid Glass on macOS 26, a blurred dark panel before it) through which the wallpaper shows faintly. The area exactly under the hardware notch stays black, with no glass sliver at its edges.

### ISL-028 · Permission card buttons ignore clicks for the first moment

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; Claude Code; Settings › Alerts › Permission prompts › *Answer from the notch* on

**Steps**

1. Rest the pointer where the `Allow once` button will appear (right side, just under the notch).
2. Ask Claude Code to run `rm -rf build`, and click repeatedly as the card appears.
3. Wait one second and look at the buttons.

**Expected**

- For about 0.6 s the `Deny`, `Allow once` and `See it all in…`/`Answer in…` buttons are dimmed and clicks on them do nothing; the prompt is not answered.
- After that they brighten and work.
- Each new prompt in a queue starts dimmed again.

### ISL-029 · Permission card says how many are waiting and when details are hidden

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`, `Sources/AmbientApp/Island/IslandViewModel.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; Claude Code with an MCP server; *Answer from the notch* on, wait 20 seconds

**Steps**

1. In three Claude Code sessions, trigger a permission prompt at about the same time.
2. Answer them one by one; in another session trigger a prompt for an MCP tool.

**Expected**

- The card header shows the project, the agent tag, and `1 of 3 · 18s` counting down each second; with a single prompt, just `18s`.
- Below: `wants to use Bash` and the command in monospace, wrapped onto more lines rather than cut.
- For the MCP tool: `Its details aren't shown here.` in amber, and the left link reads `See it all in Terminal` in amber instead of `Answer in Terminal` in grey.

### ISL-030 · A permission prompt takes the island even while you hover the list

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandController.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; Claude Code; *Answer from the notch* on

**Steps**

1. Hover the island so the session list is open, and keep the pointer there.
2. Trigger a permission prompt in Claude Code.
3. Answer it with `Deny`.

**Expected**

- The list is replaced by the permission card while the pointer stays over it; moving across it does not swap it back to the list.
- After answering, the island returns to the list (still hovered) and the session shows as working, not needs-you.

### ISL-031 · Notch settings pane: two toggles with their subtitles

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/IslandPane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Appearance › Notch.
2. Turn *Show agent status at the notch* off and on; quit and reopen Ambient.

**Expected**

- The pane shows a preview, then `Show agent status at the notch` (subtitle `Voices you record or receive show there either way.`) and `Show while agents are working` (subtitle `Otherwise it shows only when an agent needs you, finishes, or fails.`).
- With the first off, the second is dimmed and can't be changed.
- Both settings survive a restart; on a fresh install both are on.

### ISL-032 · Notch preview cycles the real island and follows the settings

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/IslandPreview.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Appearance › Notch and watch the preview for 10 seconds.
2. Turn off *Show while agents are working* and watch again.
3. Turn off *Show agent status at the notch*.
4. Turn on Reduce motion in Accessibility settings.

**Expected**

- Step 1: against a soft gradient desktop and a pale menu bar strip, every 3 s the island changes: collapsed with a coral working orb and `2m`; a needs-you card `api-server` · `CLAUDE` · `Approve a command · rm -rf build`; a done card `Done · All 42 tests pass. Ready for review.` with `took 2m`.
- Step 2: only the needs-you and done cards alternate.
- Step 3: the preview greys out (desaturated, faded), the island disappears, and an `Off` badge shows bottom left.
- Step 4 (status on): the preview holds on the needs-you card and stops cycling.

### ISL-033 · Opening the island moves the living wallpaper's notch effect

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/NotchSimulation.swift`, `Sources/AmbientCore/NotchGeometry.swift`
- **Automated by:** `BlackHoleTests`, `SolarSimulationTests`, `NotchSimulationTests`
- **Needs:** Mac with a notch; living wallpaper on; at least eight sessions

**Steps**

1. With the Sky wallpaper, hover the island for 5 seconds, then move away.
2. Switch to Solar System and repeat.
3. Turn on Reduce motion and repeat both.
4. Repeat step 1 on a Mac without a notch.

**Expected**

- Sky: the notch flashes and collapses into a black hole about half the notch wide; agents lift off and swing into orbits around it without falling in, loose dust falls in; on close the hole fades in under half a second and everything drifts home.
- Solar: the notch lights as a sun; the six most urgent agents orbit it and the rest fall in; on close every planet returns to its slot.
- Reduce motion: no flash or wave, and every agent stays home.
- Without a notch the hole or sun is drawn at least 180 points wide, about a MacBook notch.

### ISL-034 · Settings previews use solid surfaces with Reduce Transparency

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Design/**`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Alerts and Settings › Appearance › Dock and look at the banner and Dock previews.
2. Turn on System Settings › Accessibility › Display › Reduce transparency, and look again in light and dark mode.

**Expected**

- Step 1: the banner and mini Dock are glass (Liquid Glass on macOS 26, a translucent material with a thin edge before it) over a blue-to-pink gradient (dark navy-to-plum in dark mode); previews are 150 points tall with rounded 14-point corners.
- Step 2: the banner and mini Dock become an opaque window-coloured surface with a hairline edge.
- Settings rows are at least 44 points tall; disabled rows dim to half opacity.

### ISL-035 · Sessions from another Mac are labelled with the machine

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Island/IslandView.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; another machine connected under Settings › Agents › Other Machines

**Steps**

1. Start an agent session on the other machine.
2. Make it finish, and hover the island.

**Expected**

- The bloom card and the session row show, beside the agent tag, a small network symbol and the machine's name in faint white.
- Clicking the row marks it seen without bringing any local app forward.
