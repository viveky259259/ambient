# Ambient speaker, Ambient Microphone and voice sync

Id prefix: `SPM-`

Sound between your Macs: the *Ambient* speaker (this Mac's sound plays on another), *Ambient Microphone* (another Mac's
microphone as an input here), the Core Audio driver that adds both, and voice sync (record on one Mac, copy or play on
another). Settings live under *Settings › Voice & Sound › Ambient Speaker*, *› Ambient Microphone* and *› Voice Sync*.

Most cases need two Macs, called **Desk** (the one whose sound or voice is sent) and **Lap** (the other), both running
the same Ambient build, with Remote Login on. Which one pairs which differs by feature, and the cases say so. The
driver's own tests, `Test*` functions named under **Automated by**, live in `Drivers/AmbientSpeaker/Tests.c` and run in
`scripts/build-speaker.sh`.

### SPM-001 · Installing the driver adds Ambient and Ambient Microphone

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `Drivers/AmbientSpeaker/AmbientSpeaker.c`, `Drivers/AmbientSpeaker/Info.plist`
- **Automated by:** `TestLoading`, `TestObjects`, `TestEveryProperty`
- **Needs:** an admin password; a signed app build that carries `Contents/PlugIns/AmbientSpeaker.driver`; the driver not installed; music playing to the built-in speakers

**Steps**

1. Open Settings › Voice & Sound › Ambient Speaker.
2. Click *Install…* on the *Ambient speaker* row and enter your password.
3. Open System Settings › Sound › Output, then Input.

**Expected**

- Before: the row reads *Adds Ambient to this Mac's outputs. macOS asks for your password, and the sound stops for a moment.*
- The macOS prompt reads *Ambient needs your password to add its speaker and microphone to this Mac's sound devices.*
- While it installs: a spinner and *Installing… Enter your password in the macOS prompt. The sound stops for a moment.*
- The music stops for a moment (Core Audio restarts) and comes back on the built-in speakers: the output, alert output
  and input in use before are put back.
- The row then shows a green *Installed* badge and a ⋯ menu.
- Output lists *Ambient* (by Ambient); Input lists *Ambient Microphone*. *Ambient Loopback* and *Ambient Microphone Feed*
  appear in neither.
- `/Library/Audio/Plug-Ins/HAL/AmbientSpeaker.driver` exists, owned by `root:wheel`.

### SPM-002 · Cancelling the password prompt changes nothing

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`
- **Automated by:** none
- **Needs:** the driver not installed

**Steps**

1. Click *Install…* and click *Cancel* in macOS's password prompt.

**Expected**

- The row goes back to its *Adds Ambient to this Mac's outputs…* text with *Install…*, with no error message.
- Core Audio isn't restarted: the sound doesn't drop.

### SPM-003 · A failed install says so and can be tried again

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`
- **Automated by:** none
- **Needs:** a non-admin account (so the password prompt can't succeed), or an admin who enters a wrong password three times

**Steps**

1. Click *Install…* and fail the authentication.
2. Click *Try Again…*.

**Expected**

- The row shows, in the error colour, *macOS didn't let Ambient install the speaker.* and a *Try Again…* button.
- *Try Again…* asks for the password again and installs on success.

### SPM-004 · A newer driver in the app is offered as an update

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `scripts/build-speaker.sh`
- **Automated by:** none
- **Needs:** an installed driver whose `CFBundleVersion` is lower than the one in the app's `Contents/PlugIns/AmbientSpeaker.driver`

**Steps**

1. Open Settings › Voice & Sound › Ambient Speaker.
2. Click *Update…* and enter your password.

**Expected**

- The row reads *A newer version comes with this version of Ambient.* in the warning colour, with *Update…*.
- After updating it shows *Installed*. The Ambient Microphone tab's driver row shows the same state.
- An app carrying the same driver build number as the one installed shows *Installed*, not *Update…*.

### SPM-005 · Removing the driver removes both devices and stops the speaker

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`
- **Automated by:** none
- **Needs:** driver installed; *Play this Mac's sound there* on

**Steps**

1. From the ⋯ menu on the driver row, choose *Remove Ambient Speaker and Microphone…* and enter your password.
2. Open System Settings › Sound.

**Expected**

- The prompt reads *Ambient needs your password to remove its speaker and microphone from this Mac's sound devices.*
- While it removes: a spinner and *Removing…*.
- *Play this Mac's sound there* turns off and the other Mac stops playing.
- Sound settings no longer list *Ambient* or *Ambient Microphone*; if Ambient was the output, another output is chosen.
- The row goes back to *Install…*.

### SPM-006 · The installed speaker gives back exactly what it plays

- **Priority:** P1
- **Type:** both
- **Covers:** `scripts/speaker-check.swift`, `Drivers/AmbientSpeaker/AmbientSpeaker.c`
- **Automated by:** `TestLoopback`, `TestSettings`
- **Needs:** driver installed; Terminal allowed to use the microphone; *Ambient*'s volume up and not muted

**Steps**

1. Run `swift scripts/speaker-check.swift`.
2. Mute *Ambient* in Sound settings and run it again.

**Expected**

- Step 1 prints `ok` lines for: Sound settings lists "Ambient"; its loopback is hidden; the 48 kHz stereo format; the
  loopback kept time with the speaker; both sides heard all frames and came back as the 997 Hz and 1499 Hz tones, then
  silence. It ends with *The Ambient speaker works.* and exits 0.
- The Mac's own output doesn't change while it runs.
- Step 2 prints *FAIL  Ambient is muted or turned all the way down…* and *The Ambient speaker isn't working yet.*

### SPM-007 · Building the driver tests it first

- **Priority:** P2
- **Type:** both
- **Covers:** `scripts/build-speaker.sh`, `Drivers/AmbientSpeaker/Tests.c`, `Drivers/AmbientSpeaker/Load.c`, `Drivers/AmbientSpeaker/Info.plist`, `Drivers/AmbientSpeaker/AmbientSpeaker.c`
- **Automated by:** `TestLoading`, `TestObjects`, `TestEveryProperty`, `TestSettings`, `TestStreamDelay`, `TestLoopback`, `TestMicrophone`
- **Needs:** Xcode

**Steps**

1. Run `scripts/build-speaker.sh`.
2. Run `scripts/build-speaker.sh --if-needed` without changing anything.
3. Touch `Drivers/AmbientSpeaker/AmbientSpeaker.c` and run step 2 again.

**Expected**

- Step 1 runs `build/speaker-tests` under the address and undefined-behaviour sanitizers first; a failing test stops the
  build. It then builds `build/AmbientSpeaker.driver` for arm64 and x86_64, checks `_AmbientSpeaker_Create` is the only
  exported symbol, signs and verifies it, loads it through CFPlugIn with `build/load-speaker`, and ends with
  *Built build/AmbientSpeaker.driver <version> (<build>)*.
- Step 2 prints *build/AmbientSpeaker.driver <version> (<build>) is up to date* and builds nothing.
- Step 3 builds again.

### SPM-008 · The install script installs and removes the driver

- **Priority:** P2
- **Type:** manual
- **Covers:** `scripts/install-speaker.sh`
- **Automated by:** none
- **Needs:** an admin password; `build/AmbientSpeaker.driver` built

**Steps**

1. Run `scripts/install-speaker.sh` with no `build/AmbientSpeaker.driver` (rename it).
2. Put it back and run `scripts/install-speaker.sh`.
3. Run `scripts/install-speaker.sh --remove`.

**Expected**

- Step 1 prints *Build it first: scripts/build-speaker.sh* and exits 1.
- Step 2 asks for the password, the sound drops for a moment, and it prints *Installed: Ambient is in Sound settings.*
- Step 3 prints *Removed.* and Ambient is gone from Sound settings.

### SPM-009 · The speaker waits for the microphone permission

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `Resources/AmbientSpeaker.entitlements`
- **Automated by:** none
- **Needs:** driver installed; microphone not yet allowed for Ambient (`tccutil reset Microphone com.viveky259259.Ambient`); Lap paired

**Steps**

1. Open Settings › Voice & Sound › Ambient Speaker.
2. Click *Allow…* on the *Microphone* row and allow it.

**Expected**

- The row reads *Picks up only what plays to the Ambient speaker.*
- Before allowing, *Play this Mac's sound there* is disabled with the subtitle *Allow the microphone first.*
- After allowing, the row shows *Allowed* and the toggle can be turned on.
- If the permission is revoked while it's on, the status reads *Allow the microphone first. Ambient hears only the
  Ambient speaker.* and it starts by itself once it's allowed again.
- `codesign -d --entitlements - Ambient.app/Contents/Helpers/ambient-speaker` shows `com.apple.security.device.audio-input`.

### SPM-010 · Choosing the Mac to play on

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `Sources/AmbientApp/Speaker/SpeakerController.swift`
- **Automated by:** none
- **Needs:** driver installed; microphone allowed; Desk with no machines paired at first

**Steps**

1. On Desk, open Settings › Voice & Sound › Ambient Speaker.
2. On Desk, pair Lap: `ambient remote add lap`. Reopen the pane.
3. Pair a third machine with a custom transport (`ambient remote add box -- my-tunnel box`) and remove Lap.
4. Re-pair Lap and put Lap to sleep.

**Expected**

- Step 1: *Play on* shows *Show Other Machines* (which opens Settings › Agents › Other Machines) and the subtitle
  *Pair the Mac you want to play on, from this Mac.*; the toggle's subtitle is *Pair a Mac first.*
- Step 2: the picker lists Lap. The speaker pairs from the Mac that plays to the one that listens.
- Step 3: the custom-transport machine isn't listed; the subtitle reads *box is paired with a custom command, so the
  speaker can't play there.*
- Step 4: Lap is listed as *Lap (away)*.

### SPM-011 · A Mac plays other Macs' sound only when its own setting allows it

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `scripts/speaker-pipe.swift`
- **Automated by:** none
- **Needs:** Desk paired with Lap; driver installed and microphone allowed on Desk; a fresh Ambient install on Lap

**Steps**

1. On Lap, open Settings › Voice & Sound › Ambient Speaker and look at *Receive*.
2. On Desk, turn on *Play this Mac's sound there* for Lap and play music to Ambient.
3. On Lap, turn on *Play sound from other Macs*.

**Expected**

- Step 1: *Play sound from other Macs* (*Lets your other Macs play their sound here.*) is off.
- Step 2: Lap plays nothing. Desk's status reads *Lap doesn't take sound from other Macs yet. On Lap, turn on Voice &
  Sound › Ambient Speaker › Play sound from other Macs. Trying again in 5 seconds.* (then 10, 20, 40, 60).
- Step 3: at Desk's next try, Lap plays the music.

### SPM-012 · Desk's sound plays on Lap

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Speaker/HelperRun.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`, `Resources/AmbientSpeaker.entitlements`
- **Automated by:** none
- **Needs:** Desk paired with Lap by ssh; driver and microphone permission on Desk; *Play sound from other Macs* on Lap; Lap's firewall letting UDP in

**Steps**

1. On Desk, turn on *Play this Mac's sound there*.
2. Play music on Desk.
3. Click *Use Ambient* in the *Output* row.

**Expected**

- The status goes *Connecting to Lap…*, then *Connected to Lap. Choose Ambient as this Mac's output to play there.*
- The *Output* row reads *This Mac's sound still goes to <current output>.* with *Use Ambient*.
- After *Use Ambient*, the row reads *Ambient is this Mac's output.* with an *Ambient* badge, the music plays from Lap's
  speakers (not Desk's), and the status reads *Playing on Lap's <device>.*, then *Playing on Lap's <device>, N ms
  behind. Video here waits to match.* in green.
- Choosing Ambient in Sound settings instead of *Use Ambient* works the same.

### SPM-013 · Video on Desk waits for its sound on Lap

- **Priority:** P1
- **Type:** both
- **Covers:** `Drivers/AmbientSpeaker/AmbientSpeaker.c`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`
- **Automated by:** `TestStreamDelay`
- **Needs:** SPM-012 playing; a video with clear lip-sync or a clapperboard, in QuickTime or Safari

**Steps**

1. Note the *N ms behind* in Desk's status.
2. Start the video on Desk and listen on Lap.

**Expected**

- Lips and sound on Lap line up as closely as on a local speaker: the video waits about N ms for its sound, which the
  driver reports as Ambient's output latency (N × 48 frames).
- With an older driver that can't report latency, the status reads *Playing on Lap's <device>, N ms behind. Update the
  Ambient speaker so video waits to match.* in the warning colour.

### SPM-014 · A change in delay restarts the speaker briefly so a playing video follows it

- **Priority:** P2
- **Type:** both
- **Covers:** `Drivers/AmbientSpeaker/AmbientSpeaker.c`, `scripts/speaker-pipe.swift`
- **Automated by:** `TestStreamDelay`
- **Needs:** SPM-013 playing a video; a way to add network delay to Lap (Network Link Conditioner, about +100 ms)

**Steps**

1. While the video plays, turn on the extra delay, and later turn it off.

**Expected**

- When the delay changes by 30 ms or more, the sound drops for about 90 ms and the video keeps in sync with the new delay.
- Smaller changes cause no drop.

### SPM-015 · Lap going away mid-stream retries until it's back

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Speaker/HelperRun.swift`
- **Automated by:** none
- **Needs:** SPM-012 playing

**Steps**

1. Turn off Lap's Wi-Fi (or close its lid) while music plays.
2. Watch Desk's status for two minutes.
3. Bring Lap back.

**Expected**

- Desk's status reads *Lost the connection to Lap. Trying again in 5 seconds.* (or *Couldn't reach Lap.* when the ssh
  connection fails, after up to 10 seconds), counting 5, 10, 20, 40, then 60 seconds between tries.
- *Details* under the toggle shows the helper's own message, capitalised.
- Desk's music keeps going to Ambient (silent here) and Desk doesn't hang.
- Once Lap is reachable, the next try plays there again and the wait resets to 5 seconds.

### SPM-016 · Turning the speaker off stops it and clears the delay

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/Speaker/HelperRun.swift`, `Drivers/AmbientSpeaker/AmbientSpeaker.c`
- **Automated by:** `TestStreamDelay`
- **Needs:** SPM-012 playing

**Steps**

1. Turn off *Play this Mac's sound there*.
2. Run `pgrep -fl ambient-speaker` on both Macs after 5 seconds.
3. Read Ambient's output latency on Desk.

**Expected**

- Lap stops playing within a moment, after playing what it held.
- No `ambient-speaker` process remains on either Mac (the helper stops when its input closes, and is terminated after 3 s if not).
- Ambient's latency is back to 0, so a local player using Ambient isn't delayed.
- Ambient stays this Mac's output; nothing is heard on Desk until you choose another output.

### SPM-017 · The speaker comes back after quitting and relaunching

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** SPM-012 playing

**Steps**

1. Quit Ambient on Desk.
2. Open Ambient again.

**Expected**

- On quitting, Lap stops playing within about 3 seconds.
- After relaunch, without touching Settings, Lap plays Desk's sound again; the toggle is still on.
- If Lap was unpaired meanwhile, the status reads *The Mac it played on isn't paired any more. Choose another.*

### SPM-018 · ⏯ on Lap plays and pauses Desk

- **Priority:** P2
- **Type:** manual
- **Covers:** `scripts/speaker-pipe.swift`, `Sources/AmbientApp/Settings/Panes/SpeakerPane.swift`
- **Automated by:** none
- **Needs:** SPM-012 playing music from Music on Desk; headphones on Lap

**Steps**

1. On Lap, press ⏯ on the keyboard, then again.
2. Tap an AirPod stem on Lap, and use Lap's Control Center play button.

**Expected**

- The *Send* section footer on Desk reads *⏯ on the other Mac plays and pauses here.*
- Each press pauses or plays Music on Desk, and Lap's sound follows.

### SPM-019 · The helper on the other Mac is private and copied only when it changed

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/SpeakerController.swift`
- **Automated by:** none
- **Needs:** Desk paired with Lap

**Steps**

1. Turn the speaker on, then run on Lap: `ls -la ~/.ambient/speaker`.
2. Turn it off and on again; check the file's modification time.

**Expected**

- `~/.ambient/speaker` is mode `drwx------` and holds `ambient-speaker-<first 12 hex of its SHA-256>`, mode 755, and no
  `.part` file.
- Step 2 doesn't copy it again: the modification time is unchanged.
- Helpers of other hashes older than 7 days are deleted on the next copy.

### SPM-020 · Using Lap's microphone on Desk

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`, `Sources/AmbientApp/Settings/Panes/MicrophonePane.swift`, `Drivers/AmbientSpeaker/AmbientSpeaker.c`
- **Automated by:** `TestMicrophone`
- **Needs:** driver installed on Desk; Desk paired with Lap by ssh; microphone allowed and *Lend this Mac's microphone* on, on Lap

**Steps**

1. On Desk, open Settings › Voice & Sound › Ambient Microphone, choose Lap under *Microphone of*, and turn on *Use its
   microphone here*.
2. Click *Use as Input*.
3. Start a recording in QuickTime Player on Desk and speak into Lap.

**Expected**

- The section footer reads *Apps hear it when Ambient Microphone is their microphone. The other Mac's microphone is on
  only while one does.*
- After step 1 the status reads *Ready. Lap's microphone turns on when an app here records from Ambient Microphone.*
- The *Input* row reads *Or choose Ambient Microphone in an app's own settings.* with *Use as Input*; after it,
  *Ambient Microphone is this Mac's input.* with an *Ambient Microphone* badge.
- During recording: *Connecting to Lap…*, then *Apps here hear Lap's <device>.* in green, and QuickTime's level meter
  follows your voice on Lap.

### SPM-021 · The lending Mac's microphone is on only while an app records from Ambient Microphone

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`
- **Automated by:** none
- **Needs:** SPM-020 set up

**Steps**

1. With *Use its microphone here* on and no app recording on Desk, look at Lap's menu bar for the orange microphone dot.
2. Start recording in QuickTime on Desk; look again.
3. Stop the recording on Desk; wait a few seconds and look again.

**Expected**

- Step 1: no orange dot on Lap; Desk's status reads *Ready…*.
- Step 2: the orange dot shows on Lap (for Ambient), and Lap's lend status reads *Desk is using this Mac's <device>.*
- Step 3: the dot goes within a few seconds; Desk goes back to *Ready…* and Lap to *Your other Macs can use it now.*

### SPM-022 · A Mac lends its microphone only when its own setting allows it

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`, `Sources/AmbientApp/Settings/Panes/MicrophonePane.swift`
- **Automated by:** none
- **Needs:** Desk set up as in SPM-020, with a fresh Ambient on Lap

**Steps**

1. On Lap, open Settings › Voice & Sound › Ambient Microphone.
2. On Desk, record from Ambient Microphone.

**Expected**

- *Lend this Mac's microphone* is off on Lap; the *Lend* footer reads *Your other Macs can use this Mac's microphone while
  Ambient runs here. It records only while one does.*
- Lap's microphone never turns on (no orange dot).
- Desk's status reads *Lap doesn't lend its microphone yet. On Lap, turn on Voice & Sound › Ambient Microphone › Lend
  this Mac's microphone. Trying again in 5 seconds.*, and the recording hears silence.

### SPM-023 · Lending needs the microphone permission

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`, `Sources/AmbientApp/Settings/Panes/MicrophonePane.swift`
- **Automated by:** none
- **Needs:** microphone not yet allowed for Ambient on Lap

**Steps**

1. On Lap, open the Ambient Microphone tab.
2. Click *Allow…* in the *Lend* section and allow it.
3. Turn on *Lend this Mac's microphone*.

**Expected**

- Before allowing, *Lend this Mac's microphone* is disabled with *Allow the microphone first.*
- After turning it on, the subtitle reads *Your other Macs can use it now.*
- If permission is later denied in System Settings, it reads *Allow the microphone first.* in the warning colour.

### SPM-024 · Lap quitting Ambient stops lending, and Desk retries

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`, `Sources/AmbientApp/Speaker/HelperRun.swift`
- **Automated by:** none
- **Needs:** SPM-020 recording

**Steps**

1. Quit Ambient on Lap while Desk records.
2. Open Ambient on Lap again.

**Expected**

- Lap's orange microphone dot goes when Ambient quits.
- Desk's status reads *Lap doesn't lend its microphone yet…* or *Lost the connection to Lap.*, with *Trying again in N
  seconds* growing from 5 to 60.
- After Lap's Ambient opens (lending resumes by itself, since the setting stays on), Desk's next try hears Lap again.
- If Desk's recording stops meanwhile, Desk goes to *Ready…* and stops trying.

### SPM-025 · One Mac at a time uses a microphone

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`
- **Automated by:** none
- **Needs:** three Macs: Desk and a third Mac both set up to use Lap's microphone

**Steps**

1. Record from Ambient Microphone on Desk.
2. Start recording from Ambient Microphone on the third Mac.

**Expected**

- The third Mac's status reads *Another Mac is using Lap's microphone. Trying again in 5 seconds.*
- Desk keeps hearing Lap.
- A lending Mac without a microphone (a Mac mini with none attached) gives *Lap has no microphone to lend.*

### SPM-026 · Ambient Microphone doesn't stay the input while it's not in use

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speaker/MicController.swift`, `Sources/AmbientApp/Speaker/SpeakerController.swift`
- **Automated by:** none
- **Needs:** driver installed; *Use its microphone here* off

**Steps**

1. In System Settings › Sound › Input, choose *Ambient Microphone*.

**Expected**

- Within a moment the input switches back to the built-in microphone (or another visible input), so apps don't record
  silence.
- With *Use its microphone here* on, choosing Ambient Microphone sticks.

### SPM-027 · Voice sync lists the Macs that pair this one

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientCore/VoiceSync/VoiceHub.swift`
- **Automated by:** `VoiceHubTests`, `RemoteEndToEndTests.VoiceSync.aHubHearsOnlyItsOwnVoices`
- **Needs:** two Macs; Remote Login on Lap

**Steps**

1. On Lap, before any pairing, open Settings › Voice & Sound › Voice Sync and press ⌃⌥V.
2. On Desk, pair Lap: `ambient remote add lap`. Wait 20 seconds and reopen Lap's Voice Sync tab.
3. Put Desk to sleep for a minute.

**Expected**

- Step 1: *Send to* shows *No Mac yet* and *To send to a Mac, pair this Mac from that one.*; ⌃⌥V shows at the notch *No Mac
  receives voices from this one yet. Pair it from the other Mac's Settings › Agents › Other Machines.*
- Step 2: *Send to* lists Desk by its computer name (ASCII letters, digits, spaces, `.`, `_`, `-`, at most 40 characters)
  with *Connected now.* Voices go the other way from the speaker: the Mac that receives pairs the one that sends.
- Step 3: after about 45 seconds without a heartbeat, Desk shows as *Desk (away)* and *Away. A voice waits for it, for up
  to a day.*
- On Desk, *This Mac's name* shows the name Lap lists it by.

### SPM-028 · Recording a voice on Lap and receiving it on Desk

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/VoiceSync/VoiceRecorder.swift`, `Sources/AmbientApp/Island/VoiceCards.swift`, `Sources/AmbientCore/VoiceSync/VoiceOutbox.swift`, `Sources/AmbientCore/VoiceSync/VoiceInbox.swift`, `Sources/AmbientCore/VoiceSync/VoiceLine.swift`, `Sources/AmbientCore/VoiceSync/ADTS.swift`
- **Automated by:** `RemoteEndToEndTests.VoiceSync.aVoiceStreamsToItsHubAsItIsRecorded`, `VoiceOutboxTests`, `VoiceInboxTests`, `VoiceLineTests`, `ADTSTests`
- **Needs:** SPM-027 step 2 done; microphone and speech recognition allowed on Lap

**Steps**

1. On Lap, press ⌃⌥V and say "Run the tests in the speaker package" for about ten seconds.
2. Watch Desk's notch while you speak.
3. Press ⌃⌥V again on Lap.

**Expected**

- Lap's notch shows a red dot, *For Desk*, a running clock, a level meter, an ✕ and *Send*, and the words so far
  (*Listening…* until there are some).
- Desk's notch shows a moving amber waveform on one side and the elapsed time on the other, within a second or so of
  starting (VoiceOver: *Lap is recording a voice for you*). Nothing on it needs answering.
- After step 3 Lap shows *Sending to Desk…*, then *Sent to Desk* for 3 seconds.
- Desk at once shows *Voice from Lap*, its length, the transcript, *Play*, *Copy Audio*, *Copy Text*, ✕, and a countdown
  from *60s*, then the card goes.
- The menu bar shows *Record Voice for Desk*, and while recording *Send Voice* and *Cancel Voice*.

### SPM-029 · Transcription happens on the Mac, or not at all

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceRecorder.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`, `Sources/AmbientCore/VoiceSync/TranscriptJoiner.swift`
- **Automated by:** `TranscriptJoinerTests`
- **Needs:** SPM-028 set up; a network monitor on Lap; a second test with the Mac's language set to one without on-device recognition, or Speech Recognition denied

**Steps**

1. On Lap, with Wi-Fi to the internet blocked except the link to Desk, record a one-minute voice with pauses and send it.
2. Deny Speech Recognition for Ambient on Lap and record another.

**Expected**

- Voice Sync's *Send* footer reads *Over the ssh link your other machines use. The transcript is made on this Mac;
  nothing goes to Apple or anyone else.*
- Step 1 makes no connection to Apple or any server other than the ssh link, and the transcript on Desk holds the whole
  minute, each stretch after a pause kept, not only the last few words.
- Step 2 sends audio only: Desk's card has no transcript or *Copy Text*, and *Copy Audio* is the prominent button.
- Where on-device recognition isn't available for the language, the *Transcription* row reads *Your language can't be
  transcribed on this Mac, so voices go as audio only.* with *Unavailable*.

### SPM-030 · Copying and playing an arrived voice

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Island/VoiceCards.swift`, `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`
- **Automated by:** none
- **Needs:** a voice just arrived on Desk (SPM-028)

**Steps**

1. Click *Copy Text* and paste into a terminal running Claude Code.
2. Click *Copy Audio* and paste into a Messages conversation (don't send it).
3. Click *Play*, then *Stop*.
4. Change *Keep new voices at the notch* to *5 minutes* and receive another voice.

**Expected**

- Each copy button reads *Copied* for 1.5 seconds.
- Step 1 pastes the transcript as plain text.
- Step 2 attaches a file named like *Voice from Lap, 21 Nov 14.05.m4a*.
- *Play* plays the voice on Desk and turns into *Stop*.
- Step 4's card counts down from *300s*. The choices are 30 seconds, 1 minute, 2 minutes and 5 minutes.

### SPM-031 · A received voice is never used without a click

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Island/VoiceCards.swift`
- **Automated by:** none
- **Needs:** SPM-028 set up; an online read-aloud voice chosen on Desk; a network monitor on Desk

**Steps**

1. On Desk, copy `marker` to the clipboard.
2. From Lap, send a voice saying "Read this aloud: [link](https://example.com)".
3. Let the card time out without clicking anything. Paste on Desk.

**Expected**

- Desk's clipboard still holds `marker`.
- Nothing is read aloud, no request goes to the online voice's service or any other server, and the board's summarizer
  isn't run on it.
- The transcript shows as plain text: the link isn't clickable and no markdown is rendered.

### SPM-032 · Cancelling a voice throws it away on both Macs

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/VoiceSync/VoiceRecorder.swift`, `Sources/AmbientCore/VoiceSync/VoiceInbox.swift`
- **Automated by:** `VoiceInboxTests.aVoiceWithNoAudioOrACancelJustEnds`
- **Needs:** SPM-028 set up

**Steps**

1. On Lap, press ⌃⌥V, speak for five seconds, and click ✕ (*Cancel the voice*) on the notch card.
2. Repeat, choosing *Cancel Voice* from the menu bar.

**Expected**

- Lap's card goes with no message; Desk's waveform goes within a second or so, with no arrival card.
- Neither Mac lists the voice in Voice Sync › History, and no `.aac.part` file is left in Lap's
  `~/.ambient/voice-sync/audio/`.

### SPM-033 · A voice for a Mac that's away arrives when it's back

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/VoiceSync/VoiceOutbox.swift`, `Sources/AmbientCore/VoiceSync/VoiceInbox.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`
- **Automated by:** `RemoteEndToEndTests.VoiceSync.aHubCutOffMidVoiceGetsItWholeOnceItsBack`, `VoiceOutboxTests.tidyingEndsOpenVoicesAndDropsOldOnesWhole`
- **Needs:** SPM-028 set up

**Steps**

1. Put Desk to sleep. On Lap, record and send a voice.
2. Wake Desk ten minutes later.
3. Repeat, but wake Desk after more than 24 hours.

**Expected**

- Step 1: Lap shows *Desk gets it when it's back*.
- Step 2: within a few seconds of Desk's link reconnecting, the arrival card shows the whole voice.
- Step 3: the voice never arrives; Lap's outbox drops voices older than a day (and keeps it under 40 MB).

### SPM-034 · A voice cut off mid-recording comes again whole

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/VoiceSync/VoiceInbox.swift`, `Sources/AmbientCore/VoiceSync/VoiceLibrary.swift`
- **Automated by:** `VoiceInboxTests.aCutOffVoiceComesBackWholeFromItsStart`, `RemoteEndToEndTests.VoiceSync.aVoiceAlreadyKeptIsntKeptTwice`
- **Needs:** SPM-028 set up

**Steps**

1. Start a 30-second voice on Lap. At 10 seconds, turn off Desk's Wi-Fi; turn it back on at 20 seconds.
2. Send it at 30 seconds.

**Expected**

- Desk's waveform goes while it's cut off.
- After reconnecting, one arrival card shows the voice at its full 30 seconds: the audio from before the cut-off is there.
- History lists it once.

### SPM-035 · Voice sync without the microphone says what to do

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`
- **Automated by:** none
- **Needs:** microphone denied for Ambient on Lap; Desk listed under *Send to*

**Steps**

1. On Lap, press ⌃⌥V.
2. Open Voice Sync settings.

**Expected**

- The notch shows *Ambient can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.* for
  6 seconds; nothing is recorded and Desk shows nothing.
- The *Microphone* row (*Only while you're recording a voice.*) shows *Open Privacy Settings…*, which opens the
  Microphone privacy pane.

### SPM-036 · Changing the microphone mid-voice sends what was recorded

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceRecorder.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`
- **Automated by:** none
- **Needs:** SPM-028 set up; AirPods

**Steps**

1. On Lap, start a voice with the built-in microphone and speak for five seconds.
2. Connect AirPods so the input changes.

**Expected**

- Recording stops and Lap shows *The microphone changed, so the voice stopped there. Sent to Desk.* for 6 seconds.
- Desk receives the five seconds recorded before the change.
- A voice of no audio at all instead shows *Nothing was recorded. Check the microphone in System Settings › Sound.*

### SPM-037 · Voice history is kept privately until deleted

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/VoiceSync/VoiceLibrary.swift`, `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`
- **Automated by:** `VoiceLibraryTests.deletingForgettingAndPurging`, `VoiceLibraryTests.anUnreadableLibraryIsSetAsideNotReplaced`
- **Needs:** a few voices sent and received on Desk

**Steps**

1. Open Voice Sync › History on Desk.
2. Run `ls -la ~/.ambient/voice-sync ~/.ambient/voice-sync/audio`.
3. Use one row's ⋯ menu: *Show in Finder*, then *Delete*.
4. Click *Delete All…* and confirm.

**Expected**

- Rows read *From Lap* or *To Lap*, with date, time and length, and the transcript or *No transcript*; newest first.
- The folders are `drwx------`; `library.json`, `hub.id` and each `audio/<id>.aac` are `-rw-------`.
- *Show in Finder* selects the `.aac` file; *Delete* removes the row and its file.
- *Delete All…* asks *Delete every voice on this Mac?* with *Their audio and transcripts go from this Mac. Your other
  Macs keep their own copies.*; after it, History reads *No voices yet.* and `audio/` is empty. Lap's history is unchanged.

### SPM-038 · Unpairing keeps a Mac's voices; purging deletes them

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientCore/VoiceSync/VoiceLibrary.swift`
- **Automated by:** `VoiceLibraryTests.deletingForgettingAndPurging`
- **Needs:** voices received on Desk from Lap

**Steps**

1. On Desk, run `ambient remote remove lap`.
2. Pair Lap again, then run `ambient remote purge lap`.

**Expected**

- After step 1, voices from Lap are still in History.
- After step 2, every voice received from Lap is gone from History and its audio from `~/.ambient/voice-sync/audio/`;
  voices Desk sent are kept.

### SPM-039 · Quitting while recording or sending

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientCore/VoiceSync/VoiceOutbox.swift`
- **Automated by:** `VoiceOutboxTests.tidyingLeavesAVoiceStartedSinceLaunch`, `VoiceOutboxTests.theLiveMarkerComesAndGoes`
- **Needs:** SPM-028 set up

**Steps**

1. On Lap, start a voice and quit Ambient while recording.
2. Start Ambient, record a voice, press ⌃⌥V to send, and quit at once while it reads *Sending to Desk…*.

**Expected**

- Step 1: Desk's waveform goes and no voice arrives; Lap keeps nothing, and `~/.ambient/voice-sync/outbox.live` is gone.
- Step 2: Desk receives the voice with the words so far, and both Macs list it in History.

### SPM-040 · A text note from Lap arrives at Desk's notch

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Island/VoiceCards.swift`, `Sources/AmbientCore/VoiceSync/VoiceLine.swift`, `Sources/AmbientCore/VoiceSync/VoiceInbox.swift`, `Sources/AmbientCore/VoiceSync/VoiceLibrary.swift`
- **Automated by:** `VoiceNoteTests.aNoteArrivesAtOnceWithoutAudio`, `VoiceNoteTests.aNoteKeepsItsLinesAndIndentationButNothingHidden`, `VoiceNoteTests.aNoteIsKeptWithoutAudioAndStaysANote`
- **Needs:** SPM-028 set up

**Steps**

1. On Lap, choose *Send Note to Desk…* from the menu bar, type `git pull`, a line break, `  swift build`, and click Send.
2. On Desk, click *Copy Text* on the card and paste into a text editor.
3. Open Settings › Voice & Sound › Voice Sync › History on both Macs.

**Expected**

- Step 1: Lap shows *Note sent to Desk* at the notch. Within about a second, Desk's notch shows *Note from Lap* with the
  text, no clock, no Play and no *Copy Audio*.
- Step 2: the paste is the two lines, with the second line's two spaces kept.
- Step 3: both list it with *Note* where a voice shows its length, with no Play button and no *Copy Audio* or *Show in
  Finder*. No `.aac` file for it is in `~/.ambient/voice-sync/audio/`.

### SPM-041 · The note window takes typing, pasting and the editing shortcuts

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/VoiceSync/NoteComposer.swift`, `Sources/AmbientApp/MenuBarController.swift`
- **Automated by:** none
- **Needs:** SPM-028 set up; some styled text (a web page) and an image to copy

**Steps**

1. On Lap, copy a paragraph of styled text from a web page. Choose *Send Note to Desk…* and press ⌘V.
2. Press ⌘A, ⌘X, then ⌘Z, then ⌘⇧Z. Click *Paste*.
3. Copy an image and press ⌘V in the window.
4. Clear the text. Type a few words, close the window with Escape, and choose *Send Note to Desk…* again.
5. Type a note and press ⌘↩.

**Expected**

- Step 1: the window opens in front with the cursor in the box, and the paragraph pastes as plain text.
- Step 2: each shortcut works as in any text box, and *Paste* pastes the clipboard at the cursor.
- Step 3: nothing is pasted.
- Step 4: *Send* is disabled while the box is empty or only spaces; Escape closes the window and nothing is sent. Choosing
  the menu item while the window is open brings that window to the front with its text.
- Step 5: the note is sent and the window closes. The count reads `n / 10,000` and turns orange past the limit.

### SPM-042 · The shared clipboard passes text both ways and keeps secrets

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/VoiceSync/ClipboardShare.swift`, `Sources/AmbientApp/VoiceSync/VoiceSyncController.swift`, `Sources/AmbientApp/Settings/Panes/VoiceSyncPane.swift`, `Sources/AmbientCore/VoiceSync/VoiceOutbox.swift`
- **Automated by:** `ClipboardShareTests.onlyPlainTextWithNoPrivateMarkIsShared`, `ClipboardShareTests.onlyRecentCopiesInOrderGoOnTheClipboard`, `ClipboardShareTests.copiesLeaveTheOutboxAfterTenMinutesAndNotesStay`, `ClipboardShareTests.aCopyGoesThroughTheDecoderExactlyAsCopied`
- **Needs:** SPM-028 set up, with each Mac paired from the other; a password manager on Lap

**Steps**

1. With *Share the clipboard* off on both Macs, copy text on Lap and paste on Desk.
2. Turn *Share the clipboard* on in Settings › Voice Sync on both Macs. Copy a few indented lines on Lap; paste on Desk.
3. Copy text on Desk; paste on Lap. Wait ten seconds and paste on Desk again.
4. On Lap, copy a password from the password manager. Paste on Desk.
5. On Lap, copy an image. Paste on Desk.
6. Put Desk to sleep, copy text on Lap, wait three minutes, wake Desk and paste.

**Expected**

- Step 1: Desk pastes what it had; nothing is shared while the setting is off.
- Step 2: within about a second Desk pastes exactly the lines copied, indentation included.
- Step 3: Lap pastes Desk's text, and Desk still pastes its own text: nothing bounces back.
- Step 4: Desk pastes what it had before. The password never leaves Lap: it isn't in Lap's
  `~/.ambient/voice-sync/outbox.jsonl`.
- Step 5: Desk pastes what it had before.
- Step 6: Desk pastes what it had before sleeping, not the copy made while it was away. Copies leave Lap's outbox after
  ten minutes.
