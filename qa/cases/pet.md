# Desktop pet

Id prefix: `PET-`

The optional pixel-art pet (blob, crab or cat) that stands on the desktop, acts out the most urgent session, and
opens a list or a quick look of your sessions. Sessions are easiest to drive with `ambient emit` from a Terminal
tab (see README › Any other agent); the pet ignores idle sessions and results you have already seen.

### PET-001 · The pet is off until turned on

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** none
- **Needs:** a fresh macOS user, or `defaults delete com.viveky259259.Ambient petEnabled`

**Steps**

1. Launch Ambient for the first time and finish setup.
2. Run `ambient emit working --session pet1 --agent Build --tool make --detail "make all"`.
3. Open Settings › Appearance › Pet.
4. Open the menu bar menu.

**Expected**

- No pet appears anywhere on the desktop, even with a working session.
- In the Pet pane, *Show the pet on your desktop* is off, and the *Pet* species picker and *Position* row are greyed out.
- The menu bar menu has *Show Desktop Pet* without a check mark.

### PET-002 · Turning the pet on and off from Settings and the menu bar

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. In Settings › Appearance › Pet, turn on *Show the pet on your desktop*.
2. Turn it off again.
3. In the menu bar menu, choose *Show Desktop Pet*.
4. Quit and relaunch Ambient.

**Expected**

- Step 1: the pet appears at once and plays its wake reaction (a 12 pt jump with a squash). With no session in progress it is grey and asleep.
- Step 2: the pet and any bubble disappear at once.
- Step 3: the pet comes back and the menu item now shows a check mark.
- Step 4: the pet is shown again after relaunch; the setting persists.

### PET-003 · Each species draws and the choice is remembered

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetArt.swift`, `Sources/AmbientApp/Pet/PetFigure.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** `PetArtTests.everySpeciesHasTwoFramesOfTheSameSize`, `PetArtTests.spritesAreRectangularAndUseKnownColors`, `PetArtTests.speciesRoundTripsThroughItsStoredName`
- **Needs:** pet on

**Steps**

1. In the Pet pane, pick *Blob*, then *Crab*, then *Cat* in the segmented picker.
2. With *Cat* picked, quit and relaunch Ambient.
3. Run `defaults write com.viveky259259.Ambient petSpecies dragon` and relaunch.

**Expected**

- The desktop pet and the pane preview switch species as soon as each is picked: a round blob, a crab with two raised pincers, a cat with pointed ears and a curled tail.
- Pixels are crisp and square (no smoothing); the pet is 80 × 72 pt with a 16 pt strip under it for pips.
- After relaunch the cat is still shown.
- With an unknown stored value the pet falls back to the blob, and the picker shows *Blob*.

### PET-004 · Asleep when nothing needs you

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientApp/Pet/PetFigure.swift`, `Sources/AmbientApp/Pet/PetView.swift`
- **Automated by:** `PetPolicyTests.petSleepsWithNothingRelevant`, `PetPolicyTests.idleAndSeenSessionsAreNotRelevant`
- **Needs:** pet on

**Steps**

1. End every session (`ambient emit end --session <id>` for each) or click *Mark all seen* in the pet's list.
2. Watch the pet for 5 seconds.
3. With VoiceOver on, move to the pet.

**Expected**

- The pet is grey (#8B949E), eyes closed, with a "z" beside its head that alternates with a small and a large "z" about every 1.1 s.
- No speech bubble is shown and no pips are under the pet.
- VoiceOver reads *Ambient pet, asleep. No agent needs you.*

### PET-005 · Working: types at a laptop in the agent's colour

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientCore/Pet/PetArt.swift`, `Sources/AmbientApp/Pet/PetFigure.swift`, `Sources/AmbientApp/Pet/PetView.swift`
- **Automated by:** `PetPolicyTests.poseFollowsTheMostUrgentSession`
- **Needs:** pet on; Claude Code connected

**Steps**

1. Start a Claude Code turn that runs a few tools (for example ask it to run the tests).
2. Watch the pet and its bubble.

**Expected**

- The pet takes Claude's coral colour (#D97757), eyes open, with the back of a laptop lid in front of it whose logo glows.
- It flips between its two frames quickly (every 0.28 s): the blob bounces, the crab steps, the cat swings its tail.
- A bubble above the pet (in the lower half of the screen) shows the session's title in white semibold, its status underneath (for example the running tool) and the elapsed turn time on the right, ticking every second.

### PET-006 · Needs you: hops for attention with an amber "!"

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientCore/Pet/PetArt.swift`, `Sources/AmbientApp/Pet/PetFigure.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** `PetPolicyTests.everyPoseHasItsOwnReaction`, `PetPolicyTests.unpromptedReactionsOnlyForTheMomentsTheIslandBloomsFor`
- **Needs:** pet on

**Steps**

1. Run `ambient emit waiting --session pet1 --agent Build --reason command --message "rm -rf build"`.
2. Watch the pet for 3 seconds.

**Expected**

- At once, unprompted, the pet hops twice (two 10 pt jumps) to get attention.
- Its eyes are wide with an "o" mouth; it bobs up 4 pt every other frame (every 0.4 s), and an amber "!" blinks at its top right.
- The bubble names the session and reads what it needs, for example *Approve a command · rm -rf build*.

### PET-007 · Done cheers with sparkles; failed shakes its head

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientCore/Pet/PetArt.swift`, `Sources/AmbientApp/Pet/PetFigure.swift`
- **Automated by:** `PetArtTests.doneAndFailedLookDifferentFromAsleep`, `PetArtTests.mouthsSitOnTheBody`
- **Needs:** pet on

**Steps**

1. Run `ambient emit working --session pet1 --agent Build`, then `ambient emit done --session pet1 --message "Release built"`.
2. Run `ambient emit working --session pet2 --agent Build`, then `ambient emit error --session pet2 --message "make failed"`, after acknowledging pet1 (*Mark all seen*).

**Expected**

- Done: the pet jumps 20 pt with a full 360° spin, then shows happy eyes and a smile with white-and-green sparkles that swap corners every 0.5 s. The bubble reads the summary and *just now*, later *1m ago*.
- Failed: the pet shakes side to side (5 pt), then holds one frame with "x"-like dizzy eyes, a frown and a cyan sweat drop that bobs every 0.6 s.

### PET-008 · Unprompted reactions only for moments the island blooms for, and not while quiet

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** `PetPolicyTests.unpromptedReactionsOnlyForTheMomentsTheIslandBloomsFor`
- **Needs:** pet on

**Steps**

1. Run `ambient emit working --session pet1 --agent Build` and watch the pet.
2. Hover the pet, click *Quiet 1h* in its list, then run `ambient emit waiting --session pet1 --agent Build`.
3. Click *Resume alerts*.

**Expected**

- Step 1: the pet switches to its working pose but plays no hop on its own.
- Step 2: the pet changes to the waiting pose but does not hop twice; the footer button now reads *Resume alerts* with a bell icon.
- Step 3: the button reads *Quiet 1h* with a crossed-out bell again.

### PET-009 · Several sessions finishing at once cheer once

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** `PetReactionGateTests.burstsOfTheSameReactionPlayOnce`, `PetReactionGateTests.somethingMoreUrgentStillGetsThrough`, `PetReactionGateTests.theQuietWindowCountsFromTheLastReactionPlayed`
- **Needs:** pet on

**Steps**

1. Start three sessions working (`a`, `b`, `c`), then send `done` for all three within one second.
2. Within 4 seconds of that, send `waiting` for a fourth session `d`.
3. Wait more than 4 seconds and send `done` for `d`.

**Expected**

- Step 1: one cheer (jump and spin), not three.
- Step 2: the double hop still plays, because needs-you outranks done inside the 4-second window.
- Step 3: a cheer plays again.

### PET-010 · Pips: one per session, with shapes as well as colours

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`
- **Automated by:** `PetMultiSessionTests.pipsOnlyWithSeveralSessions`, `PetMultiSessionTests.orderIsStableByUrgencyThenTitle`
- **Needs:** pet on

**Steps**

1. With one non-idle session, look under the pet.
2. Add sessions until there are seven non-idle ones: one waiting, one failed, one done and four working.
3. Leave them running for a minute.

**Expected**

- Step 1: no pips; the pet does not move when a second session starts (the strip under it is always reserved).
- Step 2: five 10 × 10 pt pips under the pet, most urgent first: amber with "!", red with a cross, green with a check, then working pips plain in their agent's colour; then a dark capsule reading *+2*.
- Step 3: pips do not shuffle while agents work; within one urgency they stay in alphabetical order of title.

### PET-011 · The bubble holds its session and shows who else needs you

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetPolicy.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientApp/Pet/PetView.swift`
- **Automated by:** `PetMultiSessionTests.bubbleKeepsItsSessionWhileOthersOfTheSameUrgencyChurn`, `PetMultiSessionTests.bubbleSwitchesWhenSomethingMoreUrgentArrives`, `PetMultiSessionTests.bubbleMovesOnWhenItsSessionStopsMattering`, `PetMultiSessionTests.badgeSaysWhenOthersNeedYou`
- **Needs:** pet on

**Steps**

1. Start two working sessions, `a` then `b`, and keep sending `working` events to `b`.
2. Send `waiting` to `b`.
3. Also send `waiting` to a third session `c`.
4. End `b`.

**Expected**

- Step 1: the bubble stays on `a`'s session; a grey badge beside the title reads *+1*.
- Step 2: the bubble switches to `b` and the badge still reads *+1* (grey).
- Step 3: the badge turns amber and reads *+1 needs you*.
- Step 4: the bubble moves to `c`.

### PET-012 · Hovering opens the session list with the island's actions

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientCore/Pet/PetPolicy.swift`
- **Automated by:** `PetPolicyTests.listIsCappedWithACountOfTheRest`, `PetMultiSessionTests.summaryCountsEachMoodOnlyWithSeveralSessions`, `PetMultiSessionTests.listIsGroupedByUrgencyInAStableOrder`
- **Needs:** pet on; seven non-idle sessions of mixed states

**Steps**

1. Rest the pointer on the pet without clicking.
2. Move the pointer from the pet onto the list, then off both.

**Expected**

- After about a quarter second the bubble is replaced by a list 292 pt wide: up to five rows, each with a state glyph, title, agent tag, status and a clock; below them *+2 more in the menu bar*; then a summary line such as *Needs you 1 · Failed 1 · Done 1 · Working 4*; then a footer with *Quiet 1h*, *Mark all seen*, and icon buttons *Hide pet* and *Settings* (names shown as tooltips).
- The list stays open while the pointer is over the pet or the list, and closes about 0.3 s after it leaves both.
- With no non-idle session the list reads *All quiet* / *No agent needs you right now.* above the footer.

### PET-013 · List footer actions

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Pet/PetView.swift`
- **Automated by:** none
- **Needs:** pet on; a done session you have not looked at

**Steps**

1. Hover the pet and click *Mark all seen*.
2. Hover again and click the gear (*Settings*).
3. Hover again and click the crossed-out eye (*Hide pet*).

**Expected**

- Step 1: the done session drops out; with nothing else, the pet falls asleep and the list reads *All quiet*.
- Step 2: the list closes and Ambient's Settings window opens.
- Step 3: the pet disappears and Settings › Appearance › Pet shows *Show the pet on your desktop* off.

### PET-014 · Clicking the pet pins a quick look at every session

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientCore/Pet/PetPolicy.swift`
- **Automated by:** `PetMultiSessionTests.peekShowsEverySessionInUrgencyOrder`
- **Needs:** pet on; ten non-idle sessions

**Steps**

1. Click the pet once, keeping the pointer on it.
2. Click the pet again.
3. Click the pet, then click anywhere on the desktop outside it.

**Expected**

- Step 1: the pet plays the reaction for its pose (for example a hop while working) and a burst of square pixels in the session's mood colour flies out, falls and fades within 0.9 s. A 228 pt-wide quick look opens: up to eight rows of pip, title and compact clock, most urgent first, then *+2 more — hover the pet for the list*. The hover list does not spring open while the pointer stays on the pet.
- Step 2: the quick look closes.
- Step 3: the click elsewhere closes it, and reaches the app underneath.
- With no session, the quick look reads *All quiet. No agent needs you right now.*

### PET-015 · Clicking a session jumps to it

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** none
- **Needs:** pet on; a Claude Code session in a Terminal tab that needs you, while another app is in front

**Steps**

1. Click the pet's speech bubble.
2. Bring another app forward; hover the pet and click the session's row in the list.
3. Bring another app forward; click the pet and click the session's row in the quick look.

**Expected**

- Each time a pixel burst plays where you clicked, and the Terminal tab running that session comes to the front.
- After the row clicks, the list or quick look folds away about a quarter second later and does not reopen until the pointer leaves the pet.

### PET-016 · Drag anywhere; the spot is remembered; Reset puts it back

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientCore/Pet/PetLayout.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** `PetLayoutTests.defaultSpotIsTheBottomRightCorner`, `PetLayoutTests.petIsKeptOnScreen`
- **Needs:** pet on

**Steps**

1. Note the pet's first spot. Drag it to the upper left of the screen and release.
2. Try to drag it past the screen's edge and under the menu bar.
3. Quit and relaunch Ambient.
4. In Settings › Appearance › Pet, click *Reset* under *Position*.

**Expected**

- The first spot is the bottom-right corner of the visible screen, 24 pt from the right edge and above the Dock.
- The pet follows the pointer while dragged; the hover list closes as soon as it moves 3 pt or more, and does not spring open on drop.
- The whole pet always stays inside the visible screen; it cannot go under the menu bar or the Dock.
- After relaunch it is where it was dropped. *Reset* moves it back to the bottom-right corner and then greys out.

### PET-017 · Bubble opens above in the lower half and below in the upper half

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Pet/PetLayout.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientApp/Pet/PetView.swift`
- **Automated by:** `PetLayoutTests.opensUpInTheLowerHalfAndDownInTheUpperHalf`, `PetLayoutTests.panelCentersOnThePetAwayFromEdges`, `PetLayoutTests.panelStaysOnScreenAtTheEdge`, `PetLayoutTests.bubbleCentersOnThePetButStaysInThePanel`
- **Needs:** pet on; one working session

**Steps**

1. Drag the pet to the bottom-left corner and look at the bubble.
2. Drag it to the top-right corner, below the menu bar.
3. Hover in each spot.

**Expected**

- Bottom: bubble and list open above the pet with the tail pointing down at it.
- Top: they open below with the tail pointing up.
- At a corner the bubble stays fully on screen and its tail still points at the pet, not at the bubble's middle.

### PET-018 · Clicks pass through everywhere but the pet and its bubble

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`
- **Automated by:** none
- **Needs:** pet on

**Steps**

1. Place a Finder window so its contents sit just beside the pet, inside the pet's 304 × 430 pt panel but outside the pet and bubble.
2. Click and double-click those Finder items.
3. Click the pet, then type in a text editor that was frontmost before.

**Expected**

- Finder receives every click next to the pet; nothing is blocked by an invisible area.
- Clicking the pet does not take keyboard focus from the frontmost app: typing goes to the editor.
- The pet floats above ordinary windows but below the menu bar and the island.

### PET-019 · The pet works with the notch island turned off

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** none
- **Needs:** pet on; Settings toggle for the island turned off

**Steps**

1. Turn the notch island off in Settings.
2. Run `ambient emit waiting --session pet1 --agent Build --message "Approve?"`.
3. Turn the island back on and repeat with `pet2`.

**Expected**

- The Pet pane's toggle subtitle reads *Works whether or not the notch light is on.*
- With the island off, the pet still hops twice, shows the waiting pose and the bubble, and the list and quick look still work.
- With the island on, both show the session; the pet's behaviour does not change.

### PET-020 · On every Space and over full-screen apps

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** none
- **Needs:** pet on; two Spaces

**Steps**

1. Switch to another Space with Ctrl-→.
2. Put an app into full screen.
3. Press Cmd-Tab and Mission Control.

**Expected**

- The pet is on every Space in the same spot and does not slide with the Space transition.
- It shows over the full-screen app.
- It never appears in the Cmd-Tab switcher or as a window in Mission Control.

### PET-021 · Multiple displays: drag across, default corner follows the main display

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetController.swift`, `Sources/AmbientCore/Pet/PetLayout.swift`
- **Automated by:** none
- **Needs:** pet on; a second display
- **Known gap:** a chosen spot is meant to stay put across display changes, but when its display is disconnected the pet is clamped onto another display and stays there after the display comes back, until it is dragged or Ambient relaunches (the clamped spot replaces the in-memory spot; the saved one is only re-read on settings changes).

**Steps**

1. With *Position* reset, connect a second display and rearrange so the main display changes.
2. Drag the pet onto the second display and release near its bottom edge.
3. Disconnect the second display.
4. Reconnect it.

**Expected**

- Step 1: an unmoved pet goes to the bottom-right corner of the display with the menu bar.
- Step 2: the pet crosses displays while dragged and stays fully inside the second display's visible area; the bubble opens on that display.
- Step 3: the pet moves fully onto the remaining display rather than vanishing off screen.
- Step 4: the pet returns to its saved spot on the second display (see Known gap).

### PET-022 · Reduce Motion stills the pet

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetFigure.swift`, `Sources/AmbientApp/Pet/PetViewModel.swift`, `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientCore/Pet/PetBurst.swift`, `Sources/AmbientApp/Settings/Previews/PetPreview.swift`
- **Automated by:** `PetBurstTests.sameSeedSameParticles`, `PetBurstTests.particlesFadeOutByTheEnd`, `PetBurstTests.gravityPullsParticlesDownOverTime`
- **Needs:** pet on; System Settings › Accessibility › Display › Reduce motion

**Steps**

1. Turn Reduce Motion on with a working session.
2. Click the pet, then hover it.
3. Open Settings › Appearance › Pet.

**Expected**

- The pet holds one frame (no frame flipping, no waiting bob); the laptop, "!" or "z" prop still shows.
- Clicking plays no pixel burst; the quick look and list fade in without drifting.
- The pane preview holds still in the waiting pose instead of cycling through poses.

### PET-023 · The settings preview acts out each pose

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/PetPreview.swift`, `Sources/AmbientApp/Settings/Panes/PetPane.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Appearance › Pet with the pet off, then on.
2. Watch the preview for 15 seconds; change the species.

**Expected**

- The preview is dimmed while the pet is off and full strength while on.
- Every 2.6 s it moves to the next pose with its reaction: working (*api-server*, running *npm test*), waiting (*rm -rf build*), done (*All 42 tests pass.*), error (*Build failed*), then asleep with no bubble.
- The preview's species follows the picker at once. The section footer reads *Hover the pet for your sessions and actions, click it for a quick look at all of them, and click a session to jump to it.*

### PET-024 · Reading aloud shows in the bubble with controls

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** none
- **Needs:** pet on; a voice set up in Settings › Voice & Sound

**Steps**

1. Select a paragraph in Terminal and press ⌥⎋.
2. Click pause in the pet's bubble, then continue, then stop.

**Expected**

- While reading, the bubble shows a speaker icon, *Reading aloud*, a moving level meter and the speech controls.
- Paused, it reads *Paused* and the meter stops; continue resumes; stop ends speech and the bubble returns to the session (or disappears if none).

### PET-025 · VoiceOver can use the pet

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Pet/PetView.swift`, `Sources/AmbientApp/Pet/PetController.swift`
- **Automated by:** none
- **Needs:** pet on; VoiceOver; three non-idle sessions

**Steps**

1. Move VoiceOver to the pet and listen.
2. Press VO-Space.
3. Open the Actions rotor and choose *Show sessions and actions*.

**Expected**

- The pet reads like *Ambient pet. Needs you 1 · Working 2. Most urgent: <title>, <status>*, as a button with hint *Shows all your agent sessions*.
- VO-Space opens the quick look (hint becomes *Hides your agent sessions*); rows read *<title>, <mood>*.
- The action opens the full list and keeps it open until a click elsewhere; rows have the hint *Opens Terminal* (or *Opens the session*).
