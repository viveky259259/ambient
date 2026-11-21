# Living wallpaper

Id prefix: `WAL-`

The scene drawn behind the desktop icons (Sky, Harbor, Garden or Solar System), its text, the notch effect when the
island opens, and the lock-screen fallback that swaps the real wallpaper while the Mac is locked and puts the user's
own back. Sessions are easiest to drive with `ambient emit` (README › Any other agent). Before any case that locks
the Mac, note the current wallpaper (System Settings › Wallpaper) so it can be compared afterwards.

### WAL-001 · The living wallpaper is off until turned on

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** none
- **Needs:** a fresh macOS user, or `defaults delete com.viveky259259.Ambient wallpaperEnabled`

**Steps**

1. Launch Ambient for the first time and finish setup, with an agent session working.
2. Look at the desktop, then lock the Mac and unlock it.
3. Open Settings › Appearance › Wallpaper.

**Expected**

- The desktop shows the user's own wallpaper; no scene is drawn and nothing changes on the lock screen.
- `~/.ambient/wallpaper-swapped` and `~/.ambient/backups/wallpaper-Index.plist` do not exist.
- In the pane, *Living wallpaper* is off and every section below it (Scene, Lock screen, On the scene) is greyed out. The preview is dimmed.

### WAL-002 · Turning it on draws the scene above the wallpaper and below the icons

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`, `Sources/AmbientApp/Wallpaper/SceneFeed.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** none
- **Needs:** desktop icons visible (a file on the Desktop)

**Steps**

1. Turn on *Living wallpaper*.
2. Click, double-click and drag on empty parts of the scene; drag a desktop icon.
3. Switch Spaces, and press Cmd-Tab.

**Expected**

- The scene fills every display at once; the section footer reads *Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.*
- Desktop icons draw on top of the scene and can be selected and dragged; clicks on the scene behave as clicks on the desktop (the scene never takes focus or shows in Cmd-Tab).
- The scene stays in place on every Space.

### WAL-003 · Turning it off leaves the user's own wallpaper untouched

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`
- **Automated by:** none
- **Needs:** a recognisable wallpaper of the user's own (a photo, a colour and a dynamic one, in turn)

**Steps**

1. With the living wallpaper on and the Mac never locked since, open System Settings › Wallpaper and note the selection.
2. Turn *Living wallpaper* off.
3. Turn it on, then quit Ambient from the menu bar.

**Expected**

- While on, System Settings › Wallpaper still shows the user's own choice: the desk scene is a layer of windows, not a wallpaper change.
- When turned off, and when Ambient quits, the scene disappears at once and the user's own wallpaper is visible, exactly as before.
- `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` is unchanged (same modification time) by these steps.

### WAL-004 · Lock screen: the scene is shown while locked and the user's wallpaper comes back on unlock

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/LockMonitor.swift`, `Sources/AmbientCore/WallpaperSwapFlow.swift`, `Sources/AmbientCore/WallpaperStore.swift`
- **Automated by:** `WallpaperSwapFlowTests.aLockSwapsAndItsUnlockRestoresWithoutTheShortcut`, `WallpaperBackupTests.theUsersOwnWallpaperIsAlwaysBackedUp`, `WallpaperStoreTests.matchingIgnoresWhenThingsWereLastUsed`
- **Needs:** living wallpaper on, *Show on the lock screen* on (default); a photo wallpaper of the user's own; a second Mac or a phone camera to view the lock screen

**Steps**

1. Lock the Mac with Ctrl-Cmd-Q and wait 5 seconds.
2. Look at the lock screen; make sure the password field, user picture and login options are visible and usable.
3. Unlock, then wait 5 seconds.
4. Check System Settings › Wallpaper and `ls ~/.ambient ~/.ambient/backups ~/.ambient/wallpaper`.

**Expected**

- About 2 seconds after locking (not before), the lock screen shows the scene; macOS's own clock, password field and options stay on top of it.
- After unlock, within about 5 seconds, the user's own wallpaper is back on every display and System Settings › Wallpaper shows their original choice.
- `~/.ambient/wallpaper-swapped` is gone and `~/.ambient/wallpaper/` is empty. `~/.ambient/backups/wallpaper-Index.plist` holds the backup.
- Settings › Appearance › Wallpaper › *Show on the lock screen* reads *Shown as your wallpaper while locked, then put back*.

### WAL-005 · Colour, dynamic and per-display wallpapers come back exactly

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientCore/WallpaperStore.swift`
- **Automated by:** `WallpaperStoreTests.readsTheDesktopChoice`, `WallpaperStoreTests.nestedConfigurationsCompareByContent`, `WallpaperStoreTests.differentChoicesDontMatch`
- **Needs:** lock screen option on; two displays

**Steps**

1. Set a solid colour wallpaper, lock for 10 seconds, unlock.
2. Repeat with a dynamic (time-shifting) macOS wallpaper, then an aerial/screen saver wallpaper.
3. Set a different photo on each display, lock for 10 seconds, unlock.

**Expected**

- Each time the exact same wallpaper returns (same colour, same dynamic or aerial choice, same per-display photos), not a static snapshot or a default.
- No scene image remains as the wallpaper on any display or Space.

### WAL-006 · A crash while locked is put right at the next launch

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/WallpaperSwapFlow.swift`, `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** `WallpaperSwapFlowTests.aSwapLeftBehindIsRestoredAtLaunchUnlessLocked`
- **Needs:** lock screen option on; ssh access to the Mac from another machine

**Steps**

1. Lock the Mac and wait 5 seconds so the scene is the lock-screen wallpaper.
2. From another machine, `ssh` in and run `killall -9 Ambient`.
3. Unlock the Mac and look at the desktop and System Settings › Wallpaper.
4. Launch Ambient.

**Expected**

- Step 3: the scene image is still the wallpaper (Ambient was not there to undo it), and `~/.ambient/wallpaper-swapped` exists.
- Step 4: within about 5 seconds of launch the user's own wallpaper is back and the marker file is gone.
- If Ambient is relaunched while the Mac is still locked, nothing is restored until the unlock, which restores it.

### WAL-007 · A wallpaper picked after a crash is kept

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientCore/WallpaperStore.swift`
- **Automated by:** `WallpaperStoreTests.findsAmbientsImagesWhereverTheyAreSet`
- **Needs:** as WAL-006

**Steps**

1. Leave a swapped scene behind as in WAL-006 steps 1–3.
2. Before relaunching Ambient, pick a new wallpaper in System Settings.
3. Launch Ambient.

**Expected**

- The newly picked wallpaper stays; Ambient does not overwrite it with the older backup.
- `~/.ambient/wallpaper-swapped` is removed and no *Restore my wallpaper* row shows in Settings.

### WAL-008 · *Restore my wallpaper* when a restore has not finished

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientCore/WallpaperSwapFlow.swift`
- **Automated by:** `WallpaperSwapFlowTests.restoreFromSettingsOnlyWhenOwedAndIdle`, `WallpaperSwapFlowTests.aFailedRestoreIsRetriedCarefullyOnTheNextUnlock`
- **Needs:** a swap left behind (WAL-006 steps 1–3); temporarily rename `~/.ambient/backups/wallpaper-Index.plist`

**Steps**

1. With the backup renamed, launch Ambient and open Settings › Appearance › Wallpaper.
2. Rename the backup back and click *Restore*.

**Expected**

- Step 1: the restore cannot finish; a section at the top of the pane shows *Restore my wallpaper* with a prominent *Restore* button and the footer *Ambient showed the scene as your wallpaper while the Mac was locked and hasn't put yours back yet.*
- Step 2: the user's wallpaper comes back within about 5 seconds and the section disappears.
- The row shows even with *Living wallpaper* turned off, and its button stays clickable.

### WAL-009 · Turning the living wallpaper off with a restore still owed

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** none
- **Needs:** a failed restore as in WAL-008 step 1
- **Known gap:** turning the living wallpaper off does not try the owed restore; the scene image stays as the real wallpaper until *Restore* is clicked, the next unlock, or the next launch. The pane's footer promises *Turn it off and your own wallpaper is simply there.*

**Steps**

1. With the restore owed, put the backup back in place.
2. Turn *Living wallpaper* off and look at the desktop.
3. Click *Restore*.

**Expected**

- Step 2: the user's own wallpaper is visible (see Known gap: today the scene image remains).
- Step 3: the user's wallpaper is back and the restore row disappears.

### WAL-010 · An unknown wallpaper store is never touched

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientCore/WallpaperStore.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** `WallpaperStoreTests.refusesFormatsItDoesntKnow`, `WallpaperSwapFlowTests.aBackupThatFailsMeansNoSwap`, `WallpaperBackupTests.whileAmbientsImageIsSetTheBackupIsTheOnlyRecord`
- **Needs:** a test user whose `Index.plist` is replaced with a valid property list in an unexpected shape (back up the real one first)

**Steps**

1. Turn on the living wallpaper and open the Lock screen section.
2. Lock the Mac for 10 seconds and unlock.

**Expected**

- *Show on the lock screen* reads *Not available on this Mac* in warning colour.
- The lock screen shows the user's wallpaper, not the scene; `Index.plist` is byte-for-byte unchanged and no backup or marker file is written.

### WAL-011 · Turning off the lock-screen option

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** none
- **Needs:** living wallpaper on

**Steps**

1. Turn off *Show on the lock screen*.
2. Lock for 10 seconds and unlock.

**Expected**

- The status line under the toggle disappears and *Show messages on the lock screen* greys out.
- The lock screen shows the user's own wallpaper; the desk scene is unaffected; `Index.plist` is not modified.

### WAL-012 · A quick lock and unlock does not swap

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LockMonitor.swift`
- **Automated by:** none
- **Needs:** lock screen option on

**Steps**

1. Lock with Ctrl-Cmd-Q and unlock with Touch ID within about one second.

**Expected**

- No swap happens: `Index.plist` keeps its modification time and no `~/.ambient/wallpaper-swapped` marker appears. A lock counts only after holding for 2 seconds.

### WAL-013 · The lock screen hides free text unless allowed

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/SceneState.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientApp/Wallpaper/SceneFeed.swift`
- **Automated by:** `SceneStateTests.theLockScreenHidesItsClockAndFreeText`
- **Needs:** lock screen option on; calendar line on with an event later today; a way to view the lock screen

**Steps**

1. Run `ambient emit waiting --session lk --agent Build --message "rm -rf secret-dir"`.
2. Lock the Mac and read the scene on the lock screen.
3. Unlock, turn on *Show messages on the lock screen*, lock again.

**Expected**

- Step 2: the label reads the agent, need and time (*Build · Answer question · 1m*) and the session's title; no message text (*rm -rf secret-dir*) shows anywhere. The calendar line reads *Next event at 15:30* without the title. No board panel, and no clock or date of Ambient's own (the lock screen draws its clock).
- Step 3: the message line and *<event title> at 15:30* show.
- The toggle's subtitle reads *Prompts, summaries, command hints and event titles. Anyone near your Mac can read them.*

### WAL-014 · Lock screen with several displays

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/WallpaperSwap.swift`, `Sources/AmbientApp/Wallpaper/SceneFeed.swift`
- **Automated by:** none
- **Needs:** two displays; lock screen option on

**Steps**

1. Lock with two sessions running and look at both displays.
2. While locked, send `done` to one session and wait 30 seconds.

**Expected**

- The main display shows the full scene with its inhabitants and labels; the other display shows the same world without inhabitants or text.
- The locked scene is redrawn at least every 30 s and on mood changes no more than every 8 s, so the finished session's colour changes on the main display.
- On unlock both displays get their own wallpapers back.

### WAL-015 · Pick a scene; "A new one each day" changes at midnight

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/ScenePolicy.swift`, `Sources/AmbientApp/Settings/Panes/ScenePicker.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** `ScenePolicyTests.aPickedSceneStays`, `ScenePolicyTests.dailyChangesAtMidnightAndCyclesThroughAll`, `ScenePolicyTests.choicesRoundTripThroughTheirRawValues`
- **Needs:** living wallpaper on

**Steps**

1. Open the Scene section and look at the cards.
2. Click *Sky*, *Harbor*, *Garden* and *Solar System* in turn.
3. Click *A new one each day*, then set the Mac's clock to 23:59 and wait two minutes (or advance the date by a day four times).

**Expected**

- Five cards, each with a thumbnail of the world alone: *Sky*, *Harbor*, *Garden*, *Solar System*, and *A new one each day* showing four slices. The selected card has an accent-coloured 2 pt border. *A new one each day* is selected by default.
- Each click changes the desktop within a second.
- With *A new one each day*, the world changes at local midnight, cycling Sky → Harbor → Garden → Solar System; it stays the same all day.

### WAL-016 · Sky: sessions are stars, finished turns build a constellation

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/SkyScene.swift`, `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`
- **Automated by:** none
- **Needs:** Sky scene; *Look* set to *Always dark*

**Steps**

1. Start three sessions: one working, one waiting, one done.
2. Finish another turn and watch the top of the sky.

**Expected**

- Each session is a glowing star in its state's colour: the working one in its agent's colour with sparks circling it (more as its turn uses more tools), the waiting one amber, the done one green. A failing star flickers red.
- Each star has a label beside it (left of it near the right edge): headline such as *Claude · Approve command · 2m* (amber for the waiting one), the title and project, and a monospaced detail line.
- A finished turn streaks in over about 2 seconds and joins an arc of stars across the top; the Milky Way and twinkling stars show at night.

### WAL-017 · Harbor: sessions are boats

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/HarborScene.swift`
- **Automated by:** none
- **Needs:** Harbor scene

**Steps**

1. Start sessions in each state; finish two more turns. Try *Always light* and *Always dark*.

**Expected**

- Each session is a boat with a lantern at its masthead: working boats sail with a wake, a waiting boat swings an amber lantern, done and failed boats glow green and red.
- Each finished turn glides in from the left (about 160 pt) and moors along the pier, in two rows.
- At night the moon shows and a lighthouse beam sweeps the water; by day the sun is high. Labels, story and timeline stay light text on dark water in both looks.

### WAL-018 · Garden: sessions are plants

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/GardenScene.swift`
- **Automated by:** none
- **Needs:** Garden scene

**Steps**

1. Start a working session and let it run 20 tools; add a waiting, a done and a failed one; finish another turn.

**Expected**

- The working plant grows taller as its turn uses more tools; the waiting plant holds up a glowing bud; the done one blooms; the failed one droops.
- Each finished turn grows a small flower in the bed; fireflies drift at night.

### WAL-019 · Solar System: sessions are planets in rows

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/SolarScene.swift`, `Sources/AmbientCore/SolarLayout.swift`, `Sources/AmbientCore/SceneState.swift`
- **Automated by:** `SolarLayoutTests.oneRowUpToFourThenTwoCentredRows`, `SceneStateTests.theSolarSystemHoldsTenPlanets`
- **Needs:** Solar System scene

**Steps**

1. Start three sessions, then six, then twelve.

**Expected**

- Up to four planets stand in one centred row across the middle; five or more split into two centred rows.
- Each planet is a globe in its agent's colour with its mood's glow, a moon circling while it works, and its label centred below it.
- Ten planets at most; with twelve, the story line ends with *+2 more sessions now*.

### WAL-020 · At most eight inhabitants, most urgent first, in stable spots

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SceneState.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`
- **Automated by:** `SceneStateTests.inhabitantsMostUrgentFirstCappedAtEight`, `SceneStateTests.slotsStayPutWhenSessionsArrive`, `SceneStateTests.newSessionsTakeTheFirstFreeSpots`, `SceneStateTests.busynessGrowsWithToolsOnALogScale`
- **Needs:** Sky scene

**Steps**

1. Start nine working sessions, then make one of them wait.
2. Start and end other sessions for a minute, watching the first three.

**Expected**

- Eight stars show; the story line ends with *+1 more session now*. The waiting session is among the eight even if it was the ninth.
- Sessions that stay keep their spots; new ones take free spots; nothing jumps around when others come and go.

### WAL-021 · The scene follows the time of day

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/DayLight.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** `DayLightTests.steadyPhases`, `DayLightTests.blendsAcrossTransitions`, `DayLightTests.followsTheWallClockOnDaylightSavingDays`, `DayLightTests.darkInkOnlyByDay`
- **Needs:** *Look* set to *Follow the time of day*; permission to set the clock by hand

**Steps**

1. Set the clock to 04:30, 05:30, 06:15, 07:00, 12:00, 18:00, 19:00, 20:30 and 22:00 in turn, waiting a minute after each.
2. Change the time zone in System Settings.

**Expected**

- Night at 04:30 and 22:00; blending into dawn 05:00–06:00; dawn at 06:15; blending into day 06:30–07:30; day at 12:00; blending into dusk 17:30–18:30; dusk at 19:00; blending into night 20:00–21:00.
- Text is dark ink on bright sky by day and white at dawn, dusk and night.
- The scene and clock update within a minute of each change, and immediately on a time-zone change.

### WAL-022 · Light, dark or Match macOS

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/DayLight.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** `DayLightTests.theLookCanFollowTheDayTheSystemOrStayPut`, `SceneStateTests.theLookSetsTheSceneLight`
- **Needs:** living wallpaper on

**Steps**

1. Open the *Look* menu.
2. Choose *Always light* at night, then *Always dark* at midday.
3. Choose *Match macOS* and switch System Settings › Appearance between Light and Dark.

**Expected**

- Four options: *Follow the time of day* (default), *Match macOS*, *Always light*, *Always dark*; the row subtitle reads *Automatic is light by day and dark at night.*
- *Always light* holds the midday look and *Always dark* the night look regardless of the clock.
- With *Match macOS* the scene switches to day or night within a second of the appearance change, also when macOS's Auto appearance switches.

### WAL-023 · The clock, date and story text

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SceneState.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`
- **Automated by:** `SceneStateTests.theDeskShowsClockDateAndEvent`, `SceneStateTests.theStoryReadsTheDay`, `SceneStateTests.labelsReadNaturally`, `SceneStateTests.longTextIsClipped`
- **Needs:** living wallpaper on; a day with agent activity

**Steps**

1. Look at the top-left and bottom-left of the main display at the start of a day with no activity.
2. Run a Claude Code turn longer than a minute that uses tools, needs a permission once and finishes.
3. Watch the clock pass the top of a minute.

**Expected**

- Top-left: a large thin clock in the system's 12/24-hour format and the full date in the Mac's locale (for example *Saturday 21 November*). The clock changes within 2 seconds of the minute.
- Bottom-left with no activity: *A quiet day so far*.
- After the turn: *Today   1m of agent time  ·  N tools  ·  1 turn done  ·  1 call for you  ·  1 project*, numbers in semibold; plurals switch at two (*turns done*, *calls for you*). Failed turns add *N failed*; a run over a minute adds *longest run*. Agent time under a minute is left out.
- Long titles end in an ellipsis rather than running across the screen.

### WAL-024 · Latest moments, bottom-right

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SceneState.swift`, `Sources/AmbientContracts/DayLog.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`
- **Automated by:** `SceneStateTests.theTimelineShowsTheLatestFour`, `DayLogTests.aPromptCountsOnceWhileItWaits`
- **Needs:** living wallpaper on

**Steps**

1. Make sessions need you, finish and fail, six moments in all.
2. Send `waiting` twice in a row to the same session.

**Expected**

- Bottom-right shows the four newest moments, newest on top, each as a monospaced time and text such as *10:42  Gemini finished · docs*, *Claude needed you · api-server*, *Codex failed · web*.
- A prompt that is still waiting counts once: the second `waiting` adds no moment and no call for you.

### WAL-025 · Today's story survives restarts and starts fresh at midnight

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/DayLogFile.swift`, `Sources/AmbientContracts/DayLog.swift`
- **Automated by:** `DayLogTests.midnightStartsAFreshDayAndSplitsATurnThatCrossesIt`, `DayLogTests.rollOverOnlyPastMidnight`, `DayLogTests.missingOrCorruptFilesLoadNothing`, `DayLogTests.capsKeepTheNewestAndCountsStayExact`
- **Needs:** living wallpaper on

**Steps**

1. After some activity, quit and relaunch Ambient.
2. Run `ls -l ~/.ambient/day.json`.
3. Set the clock past midnight and wait a minute.
4. Quit Ambient, write `garbage` into `~/.ambient/day.json`, relaunch.

**Expected**

- Step 1: the story and moments are the same after relaunch.
- Step 2: the file is readable and writable by the user only (`-rw-------`).
- Step 3: the story reads *A quiet day so far* and the moments are empty (a turn running across midnight counts only its time after midnight).
- Step 4: Ambient launches normally with a fresh day.

### WAL-026 · Today's story never stores prompts, messages or commands

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientContracts/DayLog.swift`, `Sources/AmbientCore/DayLogFile.swift`
- **Automated by:** `DayLogTests.savesWithoutFreeText`, `DayLogTests.demoSessionsAndSweepsDontCount`, `FormatFixtureTests`, `ContractFixtureTests`
- **Needs:** living wallpaper on

**Steps**

1. Run `ambient emit working --session priv --agent Build --tool bash --detail "echo TOPSECRET-1"`, then `ambient emit waiting --session priv --message "TOPSECRET-2"`, then `ambient emit done --session priv --message "TOPSECRET-3"`.
2. Choose *Play Demo* in the menu bar menu.
3. Wait two seconds and run `grep -c TOPSECRET ~/.ambient/day.json`.

**Expected**

- `grep` prints `0`: the file holds only counts, agents, outcomes, times and session titles or project names.
- The demo's sessions add nothing to the story or moments.

### WAL-027 · Next calendar event, only with Calendar access

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/CalendarSource.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientCore/SceneState.swift`
- **Automated by:** `SceneStateTests.theDeskShowsClockDateAndEvent`
- **Needs:** Calendar access not yet decided (`tccutil reset Calendar com.viveky259259.Ambient`); a timed event later today, an all-day event, and an event that has already started

**Steps**

1. Turn on *Next calendar event* (subtitle *Only your next timed event today, read on this Mac.*).
2. Grant access from the *Calendar access* row.
3. Add an earlier timed event later today in Calendar.
4. Deny access in System Settings › Privacy & Security › Calendars and reopen the pane.
5. Turn *Next calendar event* off.

**Expected**

- Before step 1 no Calendar prompt has ever appeared.
- Step 1: a *Calendar access* row appears with a button to ask; nothing is shown on the scene yet.
- Step 2: under the date, a small coral square and *<title> at <time>* for the next timed event; all-day and already-started events are skipped; titles over 40 characters end in an ellipsis.
- Step 3: the line switches to the new event within a few seconds.
- Step 4: the row reads *Turned off for Ambient in Privacy & Security.* in warning colour with a way to open Privacy settings, and the line is gone.
- Step 5: the line is gone.

### WAL-028 · Task board cues on the desk scene

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/SceneState.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** `SceneStateTests.boardCuesPreferBlockedAndHideWhenQuiet`
- **Needs:** living wallpaper on; seven tasks on the board: two blocked, four in progress, one done

**Steps**

1. Turn on *Task board* (subtitle *What's in progress or blocked, as soft cues on the desk scene.*).
2. Lock the Mac and look at the lock screen.
3. Move every task to done.

**Expected**

- Off by default. When on, a panel titled *Board* at the top-right shows five cues, blocked first, each a title, a status (*Blocked*, *In progress*, or *Needs you* in amber when its session waits) and a coloured dot.
- No board panel on the lock screen.
- With no active task the panel disappears.

### WAL-029 · Every display shows the scene, the island's display plays the effect

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`, `Sources/AmbientApp/Wallpaper/SceneFeed.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** none
- **Needs:** two displays; living wallpaper on

**Steps**

1. Look at both displays with sessions running.
2. Disconnect and reconnect the second display; change its resolution.
3. Open the island.

**Expected**

- Each display shows the full scene with inhabitants and text, sized to that display.
- After reconnecting or a resolution change the scene redraws to fill the display within a couple of seconds, with no black or stretched area.
- The notch effect plays only on the display with the island.

### WAL-030 · Opening the island makes a black hole in Sky, Harbor and Garden

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/NotchEffect.swift`, `Sources/AmbientApp/Wallpaper/NotchEffectDrawing.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`
- **Automated by:** `BlackHoleTests.agentsOrbitTheHoleWithoutBeingSwallowed`, `BlackHoleTests.dustFallsInAndComesBackAfterClosing`, `BlackHoleTests.afterClosingEveryAgentComesHome`, `BlackHoleTests.theHoleIsBornOncePerOpening`, `BlackHoleTests.quickReopenIsClean`
- **Needs:** Mac with a notch; Sky scene; three sessions; desktop uncovered

**Steps**

1. Hover or click the notch so the island opens; watch the desktop.
2. Close the island and watch for 10 seconds.
3. Open and close it quickly twice.

**Expected**

- A black hole forms at the notch: the sessions lift off as points of light with trails and swing into orbits, clear of the island's open menu, while loose dust falls in. Their labels move with them.
- On close, every session drifts back to its home spot and the dust comes back; the scene then returns to its calm frame rate.
- A quick reopen starts cleanly with no jump or duplicated bodies.
- The settings footer reads *When you open the notch, the Solar System's planets orbit; the other scenes can form a black hole at the notch.*

### WAL-031 · Solar System: the notch becomes the sun and six planets orbit

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/NotchEffectDrawing.swift`, `Sources/AmbientApp/Wallpaper/SolarScene.swift`, `Sources/AmbientCore/SolarLayout.swift`
- **Automated by:** `SolarSimulationTests.sixOrbitAndTheRestFallIntoTheSun`, `SolarSimulationTests.afterClosingEveryPlanetReturnsToItsSlot`, `SolarLayoutTests.theSixMostUrgentOrbitInnermostFirst`, `SolarLayoutTests.innerOrbitClearsTheMenuAndOuterFitsTheScreen`, `SolarLayoutTests.periodsFollowKeplersThirdLaw`
- **Needs:** Mac with a notch; Solar System scene; eight sessions, one of them waiting

**Steps**

1. Open the island and watch for 20 seconds.
2. Close it.

**Expected**

- The notch lights up as a sun; the six most urgent planets (the waiting one innermost) orbit on tilted ellipses, fast near the sun and slow at the bottom of the screen, with the innermost orbit clear of the island's menu.
- The other two planets fall into the sun while it is open.
- On close every planet returns to its place in the rows.

### WAL-032 · Turning the black hole off

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** none
- **Needs:** Mac with a notch

**Steps**

1. With *Harbor* picked, turn off *Black hole when the notch opens* and open the island.
2. Pick *Solar System* and look at the toggle; open the island.

**Expected**

- *Black hole when the notch opens* is on by default.
- With it off, opening the island leaves the Harbor scene unchanged.
- With *Solar System* picked, the toggle is greyed out and the sun and orbits still play.

### WAL-033 · No notch effect in Low Power Mode

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Wallpaper/NotchEffect.swift`
- **Automated by:** none
- **Needs:** Mac with a notch; Low Power Mode in System Settings › Battery

**Steps**

1. Open the island with Low Power Mode off; while it is open, turn Low Power Mode on.
2. Close and reopen the island.
3. Turn Low Power Mode off and reopen the island.

**Expected**

- Turning Low Power Mode on mid-effect stops it at once and the sessions are back in their spots.
- In Low Power Mode, opening the island draws no black hole or sun; the scene holds a still frame (no drifting, twinkling or sparks).
- With Low Power Mode off again, the effect and motion return.

### WAL-034 · Reduce Motion

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Wallpaper/SceneRenderer.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientApp/Settings/Previews/WallpaperPreview.swift`
- **Automated by:** `NotchSimulationTests.reduceMotionKeepsEveryoneHome`, `BlackHoleTests.reduceMotionHasNoWaveOrFlash`
- **Needs:** Mac with a notch; System Settings › Accessibility › Display › Reduce motion

**Steps**

1. Turn on Reduce Motion with working, waiting and failed sessions on the Sky scene.
2. Open the island.
3. Look at the Settings preview.

**Expected**

- Nothing drifts, sways or circles (no twinkles moving, no sparks orbiting, failures do not flicker); glows still fade in and out.
- Opening the island keeps every session at home with no wave or flash.
- The preview follows the same rule. Turning Reduce Motion off restores motion without relaunching.

### WAL-035 · The scene rests when covered or when nothing moves

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/DesktopLayer.swift`, `Sources/AmbientApp/Wallpaper/SceneView.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`
- **Automated by:** none
- **Needs:** Activity Monitor; Quartz Debug or Ambient's performance log for frame rate

**Steps**

1. With a working session, leave the desktop bare and note Ambient's CPU.
2. Cover the whole display with app windows and wait 5 seconds.
3. End all sessions and uncover the desktop.
4. Let the displays sleep and wake them.

**Expected**

- Bare desktop with something moving: about 12 frames a second.
- Fully covered: the scene stops drawing within about 2 seconds and CPU falls; uncovering resumes it.
- Nothing moving: about one frame a second.
- While the displays sleep nothing is drawn; after wake the clock and light are current.

### WAL-036 · Settings preview and thumbnails

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/WallpaperPreview.swift`, `Sources/AmbientApp/Settings/Panes/ScenePicker.swift`, `Sources/AmbientApp/Settings/Panes/WallpaperPane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Appearance › Wallpaper with the wallpaper off, then on.
2. Change the scene and the look.

**Expected**

- The preview shows the chosen world with three demo sessions: Claude on *api-server* needing you (*rm -rf build*), Codex on *web* running *npm test*, Gemini on *docs* done (*Docs rebuilt*). It is dimmed and still while off and animated while on.
- The preview switches world and look as soon as they change; with *Match macOS* it follows Settings' own light or dark appearance.
- VoiceOver reads the preview as *Preview of the living wallpaper* and each card by its name, the selected one as selected.

### WAL-037 · Experimental live lock layer stays off unless enabled

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Wallpaper/SkyLight.swift`, `Sources/AmbientApp/Wallpaper/LockLayer.swift`, `Sources/AmbientApp/Wallpaper/LivingWallpaper.swift`, `Sources/AmbientCore/WallpaperSwapFlow.swift`
- **Automated by:** `LockLayerCheckTests.anUnseenLayerFallsBackOnlyWithTheDisplaysAwake`
- **Needs:** a test Mac; `defaults write com.viveky259259.Ambient AmbientLiveLockLayer -bool true`, then relaunch

**Steps**

1. Without the default, check the Lock screen status line.
2. Set the default, relaunch, check the status line, then lock the Mac.
3. If the scene cannot be seen above the lock screen, unlock and check the status again.
4. Delete the default and relaunch.

**Expected**

- Without the default: *Shown as your wallpaper while locked, then put back* (the swap).
- With it, on a macOS that has the SkyLight calls: *Live above the lock screen* in green; on lock the scene fades in over 0.4 s with `Index.plist` untouched. The password field must still be reachable; if it is covered, file a bug.
- If the layer is not visible within 2 seconds with the displays awake, Ambient falls back to the swap for this macOS build and the status reads the swap text.
- After deleting the default the swap is used again.
