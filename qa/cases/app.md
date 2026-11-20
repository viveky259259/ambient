# The app as a whole

Id prefix: `APP-`

Installing, launching, upgrading and quitting Ambient; the Settings window and its General and Performance panes;
Play Demo; the performance monitor; platform support, signing and entitlements; and the basics of the `ambient`
command. Feature panes (Agents, Board, Alerts, Appearance, Voice & Sound) belong to their own areas.

Unless a case says otherwise, `ambient` means `~/.ambient/bin/ambient`.

## Install and first launch

### APP-001 · The notarized disk image installs and opens without a Gatekeeper warning

- **Priority:** P0
- **Type:** manual
- **Covers:** `scripts/release.sh`, `scripts/build-app.sh`, `Resources/Info.plist`
- **Automated by:** none
- **Needs:** a clean Mac (or user account) with no Ambient; the release `Ambient-<version>.dmg` downloaded from yaml.cafe

**Steps**

1. Open the disk image.
2. Drag **Ambient** onto the **Applications** link in the window.
3. Open Ambient from Applications, with Wi-Fi off.

**Expected**

- The disk image mounts as *Ambient <version>* and shows only Ambient and an Applications link.
- Ambient opens with no *unidentified developer* or *damaged* warning, even offline (the app and image are stapled).
- Settings opens on **Welcome** with **Connect All**, **Play Demo** and **Get Started**.
- No Dock icon stays once Settings is closed; Ambient lives in the menu bar and the notch.

### APP-002 · Homebrew installs the same signed app

- **Priority:** P1
- **Type:** manual
- **Covers:** `scripts/release.sh`
- **Automated by:** none
- **Needs:** Homebrew; no Ambient installed

**Steps**

1. `brew install --cask viveky259259/tap/ambient`
2. `codesign -dv --verbose=2 /Applications/Ambient.app 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier'`
3. Open Ambient.

**Expected**

- The cask installs `/Applications/Ambient.app` at the latest released version; its checksum matches the release's
  `Ambient-<version>.dmg`.
- The signature is *Developer ID Application*, identifier `com.viveky259259.Ambient`.
- It opens as in APP-001.

### APP-003 · First launch prepares a private ~/.ambient and links the command-line tool

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientBase/Paths.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** no `~/.ambient` yet (rename an existing one first)

**Steps**

1. Open Ambient once.
2. `ls -ld ~/.ambient ~/.ambient/bin ~/.ambient/backups ~/.ambient/logs`
3. `readlink ~/.ambient/bin/ambient`
4. Move Ambient.app to another folder, open it from there, and run `readlink` again.

**Expected**

- All four folders exist with mode `drwx------` (`0700`), owned by you.
- The link points at `/Applications/Ambient.app/Contents/Helpers/ambient`.
- After step 4 it points at the moved app's `Contents/Helpers/ambient`: the link follows the app wherever it runs.

### APP-004 · Ambient is a menu-bar app that shows in the Dock only while a window is open

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/main.swift`, `Sources/AmbientApp/AppDelegate.swift`, `Resources/Info.plist`
- **Automated by:** none
- **Needs:** setup completed

**Steps**

1. Open Ambient with Settings closed; look at the Dock and ⌘-Tab.
2. Choose **Settings…** (⌘,) in the menu bar.
3. Close Settings.

**Expected**

- Step 1: no Dock icon and no ⌘-Tab entry (`LSUIElement`); the menu bar shows Ambient's status orb.
- Step 2: Ambient appears in the Dock and ⌘-Tab while Settings is open.
- Step 3: it leaves the Dock again (unless the Task Board window is still open).

### APP-005 · Only one Ambient runs at a time

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** two copies of Ambient.app (e.g. `/Applications` and `build/`)

**Steps**

1. With Ambient running, launch the second copy directly: `build/Ambient.app/Contents/MacOS/Ambient`.
2. `log show --last 1m --predicate 'subsystem == "com.viveky259259.Ambient"' | grep already`

**Expected**

- The second copy quits within a second without opening any window or menu-bar item; the first keeps running.
- The log reads *Another Ambient is already running; quitting.*

### APP-006 · Opening Ambient again shows Settings

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** Ambient running with Settings closed

**Steps**

1. Double-click Ambient in Applications (or `open -a Ambient`, or Spotlight).

**Expected**

- The Settings window opens on the pane last shown and comes to the front; no second Ambient starts.

### APP-007 · Upgrading over an older version keeps settings, sessions and the board

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Preferences.swift`, `Sources/AmbientApp/Settings/SettingsPane.swift`, `Sources/AmbientApp/Settings/SettingsView.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** none
- **Needs:** the previous release installed and set up with non-default settings (pet on, Dock glow off, a quiet period,
  a board with tasks); the new release's DMG

**Steps**

1. In the old version, open Settings on a pane that was regrouped (for example the old *Performance* or *Wallpaper*
   pane), then quit.
2. Drag the new Ambient over the old one in Applications (**Replace**), or `brew upgrade --cask ambient`.
3. Open Ambient.

**Expected**

- Settings does not reopen on Welcome: setup stays completed.
- Every changed setting is as it was (they live in the `com.viveky259259.Ambient` defaults and `~/.ambient`).
- Settings opens on the pane the old one became: an old *wallpaper* pane opens Appearance › Wallpaper, *performance*
  opens General › Performance (or General, in a release build), *remote* opens Agents › Other Machines.
- Agents stay connected, sessions still running reappear, and the board holds the same tasks.
- `ambient --version` prints the new version.

### APP-008 · Open Ambient at login

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/GeneralPane.swift`
- **Automated by:** none
- **Needs:** a user account you can log out of

**Steps**

1. In Settings › General, turn on *Open Ambient at login*.
2. Look in System Settings › General › Login Items.
3. Log out and back in.
4. Turn it off and log out and in again.

**Expected**

- Ambient is listed under *Open at Login* in System Settings.
- After logging in, Ambient is running (menu-bar orb present) without opening Settings.
- When macOS needs you to approve it, the toggle's subtitle reads, in amber, *Approve Ambient in System Settings ›
  General › Login Items.*
- After step 4 Ambient does not start at login.

## Quit, relaunch and crashes

### APP-009 · Quit and relaunch keep running sessions

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppModel.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** `StateFileTests.sessionsSurviveARoundTrip`, `StateFileTests.restoredSessionsKeepAging`
- **Needs:** two Claude Code sessions running, one of them finished (green)

**Steps**

1. Choose **Quit Ambient** (⌘Q) in the menu bar.
2. Open Ambient again.

**Expected**

- Both sessions are back on the island and in the menu with the same state; the finished one is still green until you
  look at it.
- Their saved state is in `~/.ambient/state.json`; demo sessions are never saved.

### APP-010 · Sessions whose agent exited while Ambient was closed don't come back

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientBase/ProcessProbe.swift`, `Sources/AmbientApp/AppModel.swift`
- **Automated by:** none
- **Needs:** two Claude Code sessions in terminals

**Steps**

1. Quit Ambient.
2. Exit one Claude Code session (`/exit`), leave the other running.
3. Open Ambient and wait 5 seconds.

**Expected**

- Only the running session is shown; the one whose process exited is gone.
- A session Ambient can't check (no process id, or one owned by another user) is kept rather than dropped.

### APP-011 · A crash or force quit loses at most the last second, and relaunching recovers

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppModel.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** `StateFileTests.missingOrCorruptFilesLoadEmpty`
- **Needs:** agents running

**Steps**

1. Let an agent change state, wait 2 seconds, then `kill -9 $(pgrep -x Ambient)`.
2. Open Ambient.
3. Quit Ambient, write `garbage` into `~/.ambient/state.json`, and open Ambient.

**Expected**

- After step 2 the sessions and board are as they were 1 second before the kill (state is written about a second after
  each change); agents keep working, and their hooks dropped events silently while Ambient was down.
- After step 3 Ambient opens with no sessions and no error, and new events show as usual.

## Settings window

### APP-012 · The sidebar lists every pane in order and remembers where you were

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/SettingsPane.swift`, `Sources/AmbientApp/Settings/SettingsView.swift`
- **Automated by:** none
- **Needs:** setup completed

**Steps**

1. Open Settings. Read the sidebar.
2. Click the sidebar, then press ↓ repeatedly, then ↑.
3. Leave it on *Alerts*, close the window, and open Settings again.
4. Drag the window's edges.

**Expected**

- The sidebar lists, top to bottom: *Welcome*, *Agents*, *Board*, *Alerts*, *Appearance*, *Voice & Sound*, *General*,
  each with its symbol; the traffic lights sit inside the floating sidebar and the window has no visible title.
- ↓ and ↑ move the selection one pane at a time and stop at the ends.
- Step 3 reopens on *Alerts*.
- The window resizes within its minimum and maximum width and can't be made smaller than its minimum size.
- Tabbed panes show a segmented control: *Agents* (*This Mac*, *Other Machines*), *Appearance* (*Notch*, *Pet*,
  *Dock*, *Wallpaper*), *Voice & Sound* (*Read Aloud*, *Voice Sync*, *Ambient Speaker*, *Ambient Microphone*), and each
  remembers its tab.

### APP-013 · First run opens on Welcome until you get started

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/SettingsView.swift`, `Sources/AmbientApp/AppDelegate.swift`, `Sources/AmbientApp/Preferences.swift`
- **Automated by:** none
- **Needs:** `defaults delete com.viveky259259.Ambient setupCompleted`, then relaunch

**Steps**

1. Open Ambient. Click *General* in the sidebar, then quit and reopen.
2. Click **Get Started**.
3. Quit and reopen Ambient.

**Expected**

- While setup isn't complete, Settings opens on its own at launch and always on *Welcome*.
- **Get Started** closes the window and, if notifications are undecided, macOS asks once for permission.
- After step 3 Settings does not open at launch.
- Closing the window with its red button also counts as finishing setup.

### APP-014 · Settings › General shows startup, the command-line tool and About

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/GeneralPane.swift`, `Sources/AmbientBase/Version.swift`
- **Automated by:** `FeatureRequestsTests.websiteIsTheHomepage`
- **Needs:** a release (Developer ID) build

**Steps**

1. Open Settings › General.
2. Click **Copy** next to the command-line tool path, and paste into a terminal.

**Expected**

- The pane has no tabs and reads *General* with *Startup, the command-line tool, and version.*
- It shows *Open Ambient at login*; under *Command-line tool* the path `~/.ambient/bin/ambient` and the footer *Try
  `ambient doctor` or `ambient status`. Add `~/.ambient/bin` to your PATH to use it anywhere.*
- *About* lists *Version* (e.g. `0.10.0`), *Website* *yaml.cafe*, *Feature requests* *Suggest or vote*, *License* *MIT*.
- **Copy** reads *Copied* for 1.5 seconds, and the clipboard holds the full path (`/Users/<you>/.ambient/bin/ambient`).

### APP-015 · Feature previews are veiled with "Off" while the feature is off

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/PreviewStage.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open a pane with a live preview (e.g. Appearance › Pet) with the feature off.
2. Turn the feature on.

**Expected**

- While off, the preview is faded and grey with an *Off* label in a dark capsule at its bottom-left corner.
- Turning it on brings the preview to full colour and removes the label with a quarter-second fade.

## Play Demo

### APP-016 · Play Demo walks through every state in about 36 seconds

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Demo.swift`, `Sources/AmbientApp/AppDelegate.swift`, `Sources/AmbientBase/RGB.swift`
- **Automated by:** `DescribeTests`, `PolicyTests.hexColorsParse`
- **Needs:** island on

**Steps**

1. Click **Play Demo** on Welcome (or in the menu bar) and time it.

**Expected**

- Every 3 seconds, starting at once: Claude starts working on *api-server* (coral, `#D97757`); Codex joins on *web*
  (green, `#10A37F`); Claude needs permission (*Bash: rm -rf build*, amber `#F5A524`); Claude gets back to work;
  Gemini hits an error on *docs* (*Quota exceeded*, red `#F85149`); Codex finishes (*Release build ready: 3 crates
  updated*, green `#3FB950`); Claude finishes (*All 42 tests pass. Ready for review.*).
- About 15 seconds after the last step (36 seconds in all) every demo session disappears.
- Demo sessions never count as "you're already looking", aren't saved to `state.json`, and don't reach the board.
- Clicking **Play Demo** again mid-tour restarts the tour rather than running two at once.

### APP-017 · `ambient demo` plays the tour from a terminal

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Demo.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `DescribeTests`
- **Needs:** Ambient running

**Steps**

1. `ambient demo`
2. Quit Ambient and run it again.

**Expected**

- It prints *Ambient demo — watch the notch, the Dock and the menu bar*, then one line per step with a coloured dot and
  its title, 3 seconds apart, then *Clearing the demo sessions in 15 seconds…*, and exits 0 after clearing them.
- With Ambient quit it exits 1.

## Performance monitor

### APP-018 · Release builds measure nothing and have no Performance tab

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/PerfMonitor.swift`, `Sources/AmbientApp/Settings/SettingsPane.swift`, `scripts/build-app.sh`
- **Automated by:** none
- **Needs:** a Developer ID release build, and an ad-hoc build from `scripts/build-app.sh`

**Steps**

1. In the release build, open Settings › General.
2. In the ad-hoc build, open Settings › General.

**Expected**

- Release: no *General* / *Performance* tabs, just the General pane; no sampling timer runs (Instruments shows no
  5-second wake-ups from Ambient while idle).
- Ad-hoc: the pane shows tabs *General* and *Performance*.
- A Performance tab saved by a dev build opens General in a release build.

### APP-019 · The Performance tab shows what Ambient costs this Mac

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/PerformancePane.swift`, `Sources/AmbientApp/PerfMonitor.swift`, `Sources/AmbientBase/PerfLog.swift`
- **Automated by:** `PerfLogTests.cpuAndMemoryAverageAndPeakOverTheWindow`, `PerfLogTests.framesGiveARateAndALateShareFromTheirIntervals`, `PerfLogTests.aPauseIsNotAFrame`, `PerfLogTests.hookLatencyPercentiles`, `PerfLogTests.theWindowLeavesOlderMinutesOut`, `PerfLogTests.keepsADayAtMost`, `PerfLogTests.anEmptyLogSummarisesToZeros`
- **Needs:** an ad-hoc build; agents running; the living wallpaper on

**Steps**

1. Open Settings › General › Performance right after launch.
2. Wait 15 seconds while agents send events; switch *Last hour* / *Last 24 hours*.

**Expected**

- The subtitle reads *What Ambient costs your Mac, measured on your Mac. Nothing is sent anywhere.*
- Right after launch, *CPU* and *Memory* read *Measuring…*; within about 10 seconds they read *x.x% average · y.y% peak*
  and *N MB now · M MB peak*.
- *Living wallpaper* and *Notch effect* read *N frames · x.x fps · n% late*, or *No frames drawn*.
- *Hook events* reads *None yet*, then *N · x ms median · y ms p95*.
- The figures refresh every 5 seconds while the pane is open.

### APP-020 · A performance report is copied or saved only by hand

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/PerformancePane.swift`, `Sources/AmbientBase/PerfLog.swift`
- **Automated by:** `PerfLogTests.theReportStatesEveryFigure`
- **Needs:** an ad-hoc build

**Steps**

1. In Settings › General › Performance, click **Copy Report** and paste it.
2. Click **Save Report…** and save.
3. Quit and reopen Ambient, then open the tab.

**Expected**

- The report starts *# Ambient performance*, then *Ambient <version> · macOS <x.y.z> (arm64|x86_64) · <ISO time>* and
  *Measured on this Mac while Ambient ran; nothing was sent anywhere.*, with *## Last hour* and *## Last 24 hours*
  sections listing CPU, Memory, Wallpaper, Notch effect and Hooks.
- **Copy Report** reads *Copied* for 1.5 seconds.
- The save panel suggests *Ambient performance YYYY-MM-DD.md*.
- After step 3 the figures start over: nothing was kept on disk.

### APP-021 · `scripts/measure-perf.sh` measures a separate copy and leaves your Ambient alone

- **Priority:** P2
- **Type:** manual
- **Covers:** `scripts/measure-perf.sh`
- **Automated by:** none
- **Needs:** `scripts/build-app.sh` run; your own Ambient running with settings you can recognise

**Steps**

1. `scripts/measure-perf.sh build/Ambient.app 20`
2. `scripts/measure-perf.sh --board 500 build/Ambient.app 20`
3. Afterwards, check your Ambient's settings and `ls ~/Library/Preferences | grep Ambient.perf`.

**Expected**

- Step 1 prints a Markdown table with six rows (*Island only, nothing happening* … *Everything on, agents working*) and
  columns *CPU, average*, *CPU, peak*, *Energy impact*, *Memory*, then the CPU model, macOS version and seconds per scenario.
- Step 2 prints four board rows (no window, Settings › Board open, Settings closed, Task Board window open); the copy
  opens those windows on screen.
- Your Ambient, its settings and `~/.ambient` are unchanged; the `com.viveky259259.Ambient.perf` preferences and the
  temporary folder are gone, even after Ctrl-C.

**Known gap:** the README says the script runs the copy for 45 seconds per case, but its default is 60 seconds.

## Platform, signing and entitlements

### APP-022 · Ambient needs macOS 14 or later

- **Priority:** P1
- **Type:** manual
- **Covers:** `Resources/Info.plist`, `Package.swift`
- **Automated by:** none
- **Needs:** a Mac or VM on macOS 13, and one on macOS 14

**Steps**

1. `plutil -extract LSMinimumSystemVersion raw /Applications/Ambient.app/Contents/Info.plist`
2. Try to open Ambient on macOS 13.
3. Open it on macOS 14 and run through APP-001.

**Expected**

- Step 1 prints `14.0`.
- On macOS 13 Finder refuses to open it, saying it needs a newer macOS.
- On macOS 14 it opens and works.

### APP-023 · One app runs natively on Apple silicon and Intel

- **Priority:** P0
- **Type:** manual
- **Covers:** `scripts/build-app.sh`, `scripts/release.sh`, `Package.swift`
- **Automated by:** none
- **Needs:** the release build; an Intel Mac (or Rosetta-free check on Apple silicon plus an Intel Mac)

**Steps**

1. `lipo -archs /Applications/Ambient.app/Contents/MacOS/Ambient`, the same for `Contents/Helpers/ambient` and
   `Contents/Helpers/ambient-speaker`.
2. On an Intel Mac, open Ambient and run `ambient status`.
3. On Apple silicon, check Activity Monitor's *Kind* column for Ambient.

**Expected**

- Each prints `x86_64 arm64`.
- On Intel it launches and the CLI answers; on Apple silicon *Kind* reads *Apple*, not *Intel*.

### APP-024 · The release is Developer ID signed, hardened, notarized and stapled

- **Priority:** P0
- **Type:** manual
- **Covers:** `scripts/release.sh`, `scripts/build-app.sh`
- **Automated by:** none
- **Needs:** the release `.dmg` and the app from it

**Steps**

1. `codesign --verify --strict --deep -v /Applications/Ambient.app`
2. `codesign -dv /Applications/Ambient.app/Contents/Helpers/ambient 2>&1 | grep -E 'Identifier|flags'`
3. `spctl --assess --type execute -vv /Applications/Ambient.app` and `spctl --assess --type open --context context:primary-signature -vv Ambient-<version>.dmg`
4. `xcrun stapler validate /Applications/Ambient.app` and the same for the `.dmg`.

**Expected**

- Step 1 reports *valid on disk* and *satisfies its Designated Requirement*.
- The CLI's identifier is `com.viveky259259.Ambient.cli` and its flags include `runtime` (hardened); the speaker helper's
  is `com.viveky259259.Ambient.speaker-stream`.
- Both `spctl` checks say *accepted*, *source=Notarized Developer ID*.
- Both staple checks report *The validate action worked!*
- `dist/Ambient-<version>.sha256` lists the `.dmg` and `.zip` and matches them.

### APP-025 · The app asks for only the entitlements and permissions it explains

- **Priority:** P0
- **Type:** manual
- **Covers:** `Resources/Ambient.entitlements`, `Resources/Info.plist`
- **Automated by:** none
- **Needs:** the release app

**Steps**

1. `codesign -d --entitlements - /Applications/Ambient.app`
2. Read the usage strings in `Contents/Info.plist`.

**Expected**

- Exactly three entitlements: `com.apple.security.automation.apple-events`, `com.apple.security.device.audio-input`,
  `com.apple.security.personal-information.calendars`. No network-server, camera, location or contacts entitlement.
- Each permission macOS can ask for has its reason: Apple Events (*Ambient selects the terminal tab your agent is
  running in…*), microphone (*…only while you press its voice shortcut…*), speech recognition (*…on this Mac. Nothing
  is sent to Apple or anyone else.*), calendars (*…your next event today on its living wallpaper. Nothing leaves your Mac.*).
- `NSServices` offers *Speak with Ambient* for text.

### APP-026 · `scripts/cut-release.sh` refuses an unsafe release and its dry run changes nothing

- **Priority:** P2
- **Type:** manual
- **Covers:** `scripts/cut-release.sh`, `Sources/AmbientBase/Version.swift`
- **Automated by:** none
- **Needs:** a clone of the repository on `main`

**Steps**

1. On a feature branch: `scripts/cut-release.sh 9.9.9`
2. On `main` without a `## 9.9.9` section in `CHANGELOG.md`: run it again.
3. `scripts/cut-release.sh 9.9` and `scripts/cut-release.sh <current version>`
4. Add the changelog section and run `scripts/cut-release.sh 9.9.9 --dry-run`.

**Expected**

- Step 1: *cut-release: cut releases from main.*; step 2: *cut-release: add a '## 9.9.9 — <date>' section to
  CHANGELOG.md first.*
- Step 3: the usage message, then *… is already the current version.*
- Step 4 shows a diff stat for `Version.swift` and the site files, then *Dry run: nothing committed; files restored.*,
  and `git status` shows only the changelog edit.

## Command line basics

### APP-027 · `ambient --version` matches the app

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/main.swift`, `Sources/ambient/Commands.swift`, `Sources/AmbientBase/Version.swift`, `scripts/build-app.sh`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient --version`, `ambient version` and `ambient -v`
2. `plutil -extract CFBundleShortVersionString raw /Applications/Ambient.app/Contents/Info.plist`
3. Compare with Settings › General › *Version*.

**Expected**

- Each command prints `ambient 0.10.0` (the release's version) and exits 0, with or without Ambient running.
- The plist and Settings show the same version; `CFBundleVersion` is the build number.

### APP-028 · `ambient help` lists every command

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient help` (also `--help`, `-h`, and `ambient` with no arguments).

**Expected**

- It prints *ambient <version> — ambient desktop status for coding agents*, a *Usage* section listing install,
  uninstall, status, tasks, task, memory, mcp, remote, doctor, emit, demo, open, ack and version, and the line about
  `AMBIENT_DEBUG=1` logging to `~/.ambient/logs/hook.log`. Exit status 0.

### APP-029 · An unknown command says so and exits 64

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. `ambient frobnicate; echo $?`

**Expected**

- It prints *Unknown command 'frobnicate'.* followed by the usage, and `64`.

### APP-030 · `ambient status` lists the tracked sessions

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** two agent sessions running, one waiting for you

**Steps**

1. `ambient status`
2. `ambient status --json`
3. Quit Ambient and run `ambient status; echo $?`

**Expected**

- Step 1: *Ambient · 2 sessions · <most urgent state>*, then a line per session: a coloured dot, the agent, its title
  (cut to 28 characters), *on <machine>* for remote ones, its status and how long it has been at it.
- Step 2: a pretty, key-sorted JSON array of the sessions with ISO 8601 dates.
- Step 3: *Ambient isn't running. Open Ambient.app, then try again.* and `1`, within about 3 seconds.

### APP-031 · `AMBIENT_HOME` moves everything Ambient keeps

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientBase/Paths.swift`
- **Automated by:** none
- **Needs:** Ambient quit

**Steps**

1. `AMBIENT_HOME=/tmp/qa-ambient /Applications/Ambient.app/Contents/MacOS/Ambient &`
2. `AMBIENT_HOME=/tmp/qa-ambient /Applications/Ambient.app/Contents/Helpers/ambient status`
3. Look at `/tmp/qa-ambient` and `~/.ambient`.

**Expected**

- `/tmp/qa-ambient` holds `ambient.sock`, `bin/`, `backups/`, `logs/` (mode `0700`) and, after a change, `state.json` and
  `tasks.json`; `~/.ambient` is untouched.
- Step 2 answers from that copy. An empty `AMBIENT_HOME` falls back to `~/.ambient`.
