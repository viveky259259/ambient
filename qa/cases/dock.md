# Dock

Id prefix: `DCK-`

The Dock glow: light along the Dock's edge of the screen in the colour of the most urgent session, how it breathes,
arrives and fades for each state, the brighter light behind the Dock's glass with Accessibility access, Dock position
and auto-hide, multiple displays, turning it off, and its settings pane (Settings › Appearance › Dock) with its
preview.

Steps drive a session with `ambient emit` from a Terminal tab, as in `island.md`; run each `emit` from the same tab.
Colours are from `Palette` in `Sources/AmbientCore/Policy.swift`: Claude coral `#D97757`, Codex green `#10A37F`,
custom agents grey-blue `#B4BCC6`, needs-you amber `#F5A524`, done green `#3FB950`, error red `#F85149`. Brightness
per state is `GlowStyle` in the same file.

How the glow is drawn (`DockGlow.swift`): one click-through window, one level below the Dock, on one display. It holds
a *floor*, a gradient rising from the Dock's screen edge (strongest at the edge, gone at its far side), and, only when
Ambient has Accessibility access and the Dock is on screen, a *pill*: a brighter rounded rectangle with feathered
edges exactly behind the Dock's glass. Without access, Ambient reads the Dock's edge from its preferences
(`com.apple.dock` `orientation`). Unless a case says otherwise: Glow along the Dock on, intensity at its default
(the middle mark, 1.0), Reduce motion off, Dock fixed at the bottom, no other sessions active.

### DCK-001 · A working session lights the Dock's edge in the agent's colour, breathing

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** `GlowStyleTests.stylesPerMood`
- **Needs:** Ambient without Accessibility access (remove it in Privacy & Security › Accessibility); Claude Code connected

**Steps**

1. Give Claude Code a prompt that takes at least a minute.
2. Watch the bottom of the screen for 20 seconds.
3. In a Terminal tab, run `ambient emit working --session qa-dock --agent Build --tool make` after ending the Claude turn.

**Expected**

- Step 2: within a second a coral (`#D97757`) light fades in (over about 0.6 s) along the bottom edge of the screen, across its full width and as tall as the space the Dock reserves; strongest at the screen edge and fading to nothing at the top of the Dock's band.
- It breathes slowly between dim and bright, one full breath about every 3.2 s, never fully off.
- No light is drawn on the Dock's glass itself (no pill without access); windows and the desktop above the Dock's band are untouched.
- Step 3: the light turns grey-blue (`#B4BCC6`), the colour for custom agents, and keeps breathing at the same pace.

### DCK-002 · The glow is click-through

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** none
- **Needs:** Accessibility access for Ambient

**Steps**

1. Run `ambient emit working --session qa-click --agent Build` so the glow shows.
2. Click a Dock icon, right-click another, and drag a file onto a third.
3. With a window dragged down so its lower edge sits inside the glowing band, click inside that part of the window.

**Expected**

- Every click, right-click and drop reaches the Dock or the window as if the glow were not there.
- The glow never appears above the Dock's icons or a Dock menu; it sits behind the Dock.

### DCK-003 · Needs you glows amber with a fast breath

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** `GlowStyleTests.stylesPerMood`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session qa-wait --agent Build --tool make`.
2. Run `ambient emit waiting --session qa-wait --agent Build --reason command --message "rm -rf build"`.
3. Watch for 10 seconds.

**Expected**

- Step 2: within a second the glow changes from grey-blue to amber (`#F5A524`).
- It breathes between dim and fully bright, one full breath about every 1.2 s: clearly faster and with a wider swing than the working breath.
- It keeps breathing for as long as the session waits; it does not settle on its own.

### DCK-004 · Done arrives with a green bloom and error with two red pulses, then each holds steady

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** `GlowStyleTests.stylesPerMood`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session qa-fin --agent Build`, then `ambient emit done --session qa-fin --agent Build --message "Release built"`, switch to Finder and watch for 10 seconds.
2. Run `ambient emit working --session qa-fin2 --agent Build`, then `ambient emit error --session qa-fin2 --agent Build --message "make failed"`, switch to Finder and watch for 10 seconds.

**Expected**

- Step 1: the glow turns green (`#3FB950`), flashes from dim to full brightness and settles at three-quarter brightness, all within about 1.1 s; then it holds steady with no breathing.
- Step 2: the glow turns red (`#F85149`) and pulses twice (dim, full, dim, full) before settling, within about 1.3 s; then it holds steady, a little dimmer than the done green.

### DCK-005 · The glow fades out once nothing is active

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** `GlowStyleTests.stylesPerMood`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session qa-fade --agent Build`, then `ambient emit done --session qa-fade --agent Build`.
2. Click the Terminal window (so the finished session counts as seen).
3. Run `ambient emit working --session qa-fade2 --agent Build`, then `ambient emit end --session qa-fade2`.

**Expected**

- Step 2: within a second the green glow fades out over about 1.2 s and nothing is left along the Dock.
- Step 3: the grey-blue glow fades in, then fades out over about 1.2 s once the session ends.

### DCK-006 · The most urgent session sets the colour

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session qa-a --agent Build`.
2. In a second Terminal tab, run `ambient emit working --session qa-b --agent Build`, then `ambient emit waiting --session qa-b --agent Build --reason command --message "rm -rf build"`.
3. In the second tab, run `ambient emit end --session qa-b`.

**Expected**

- Step 2: the glow is amber with the fast breath, though another session is still working.
- Step 3: it returns to the grey-blue working colour and slow breath without fading out in between.

### DCK-007 · With Accessibility access, light shows behind the Dock's glass

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockLocator.swift`, `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** none
- **Needs:** Accessibility access for Ambient; Dock fixed at the bottom

**Steps**

1. Run `ambient emit working --session qa-ax --agent Build`.
2. Look closely at the Dock, in light and then dark mode.
3. Add or remove a Dock icon (drag an app into the Dock, then out) while the glow shows.

**Expected**

- Besides the floor along the screen edge, the Dock's glass itself glows grey-blue, brighter than the floor, filling the Dock's shape with soft (feathered) edges and rounded corners; no hard-edged colour shows past the Dock's outline.
- Step 3: within about a second of the Dock changing width, the light behind the glass matches its new width.

### DCK-008 · The glow follows a Dock on the left or right

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockLocator.swift`, `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** none
- **Needs:** with Accessibility access, then without it

**Steps**

1. Run `ambient emit working --session qa-edge --agent Build`.
2. In System Settings › Desktop & Dock, set *Position on screen* to Left, wait 2 seconds, then to Right, then back to Bottom.
3. Remove Ambient's Accessibility access and repeat step 2.

**Expected**

- With access: within about a second of each change the floor moves to the Dock's edge, the full height of the screen for left and right, strongest at that edge and fading towards the middle of the screen, and the light behind the glass sits on the Dock in its new place.
- Without access: the floor moves to the edge named in the Dock's preferences within about a second; no light behind the glass.
- The glow is never left on the old edge.

### DCK-009 · With auto-hide and no Accessibility access, a thin edge line shows

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`, `Sources/AmbientApp/Dock/DockLocator.swift`
- **Automated by:** none
- **Needs:** Ambient without Accessibility access; Desktop & Dock › *Automatically hide and show the Dock* on

**Steps**

1. Run `ambient emit working --session qa-hide --agent Build`.
2. Look at the bottom edge, then move the pointer down to show the Dock.

**Expected**

- A thin line of light, about 14 points tall, runs the full width of the bottom edge, brighter at the edge than the fixed-Dock floor in DCK-001.
- When the Dock slides up it covers the line; the line does not grow to the Dock's height and no light shows behind the glass.

### DCK-010 · With auto-hide and Accessibility access, the light rides the Dock as it slides

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`, `Sources/AmbientApp/Dock/DockLocator.swift`
- **Automated by:** none
- **Needs:** Accessibility access for Ambient; auto-hide on before the glow appears
- **Known gap:** the 20-times-a-second tracking is chosen when the glow fades in. Turning auto-hide on while the glow already shows leaves it checking once a second, so the light trails the sliding Dock in steps until the glow fades out and back in.

**Steps**

1. With auto-hide already on, run `ambient emit working --session qa-ride --agent Build`.
2. Move the pointer down to show the Dock, then away to hide it, a few times.

**Expected**

- With the Dock hidden: only the thin 14-point edge line shows.
- As the Dock slides in, the light behind its glass moves with it smoothly and the floor grows to the Dock's top; as it slides out both follow it back down to the edge line.

### DCK-011 · On several displays, the glow is on the Dock's display

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`, `Sources/AmbientApp/Dock/DockLocator.swift`
- **Automated by:** none
- **Needs:** a second display arranged beside the main one; with Accessibility access, then without it
- **Known gap:** README promises light along the Dock's edge of the screen. Without Accessibility access the glow is always on the main display (`NSScreen.screens.first`), even when the Dock has moved to the other display.

**Steps**

1. Run `ambient emit working --session qa-disp --agent Build`.
2. Move the Dock to the second display (rest the pointer at that display's bottom edge until the Dock moves).
3. Disconnect the second display, then reconnect it.
4. Remove Accessibility access and repeat step 2.

**Expected**

- Step 2: within about a second the glow leaves the main display and appears along the bottom of the second display, behind its Dock. It never shows on both displays at once.
- Step 3: the glow moves to the display that has the Dock as soon as the arrangement changes.
- Step 4: the glow stays on the main display (see Known gap).

### DCK-012 · Turning the glow off fades it out and disables its settings

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/DockPane.swift`, `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session qa-off --agent Build` and open Settings › Appearance › Dock.
2. Turn off *Glow along the Dock*.
3. Run `ambient emit waiting --session qa-off --agent Build --reason command --message "rm -rf build"`.
4. Quit and relaunch Ambient, then reopen the pane.
5. Turn *Glow along the Dock* back on.

**Expected**

- Step 2: the glow fades out over about 1.2 s. The *Intensity* slider and the *Light up behind the Dock's glass* row grey out and cannot be used; the preview fades to grey and shows an *Off* badge.
- Step 3: no glow appears.
- Step 4: the toggle is still off and nothing glows.
- Step 5: the amber needs-you glow fades in within a second, and the other rows are usable again.

### DCK-013 · The intensity slider dims and brightens the glow

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/DockPane.swift`, `Sources/AmbientApp/Dock/DockGlow.swift`
- **Automated by:** none
- **Needs:** Accessibility access for Ambient

**Steps**

1. Run `ambient emit working --session qa-int --agent Build` and open Settings › Appearance › Dock.
2. Drag the *Intensity* slider (between a small sun and a large filled sun) to the far left, then to the far right.
3. Quit and relaunch Ambient.

**Expected**

- The slider runs from 0.3 to 1.5 times the default brightness. At the far left the floor and the light behind the glass are faint but still visible; at the far right they are clearly brighter than at the default.
- The real glow eases to each new brightness over about 0.8 s, without restarting its breath; the preview follows at once.
- Step 3: the slider and the glow keep the last intensity.

### DCK-014 · Granting Accessibility access from the pane

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/DockPane.swift`, `Sources/AmbientApp/Dock/DockLocator.swift`
- **Automated by:** none
- **Needs:** Ambient without Accessibility access

**Steps**

1. Run `ambient emit working --session qa-grant --agent Build` and open Settings › Appearance › Dock.
2. Read the *Light up behind the Dock's glass* row, then click *Allow…*.
3. In the system prompt, open System Settings and turn Ambient on under Privacy & Security › Accessibility, within a minute.
4. Return to the Dock pane.

**Expected**

- Step 2: the row's subtitle reads *Needs Accessibility access to find the Dock. Without it, Ambient draws a light along the screen edge.* Clicking *Allow…* shows the macOS prompt that leads to Privacy & Security › Accessibility.
- Step 4: within about a second of the grant the button becomes a green *Allowed* badge, without reopening Settings.
- Within about a second the real glow gains the light behind the Dock's glass, without fading out first.

### DCK-015 · The preview shows each state's colour and breath

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Previews/DockGlowPreview.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Open Settings › Appearance › Dock with no session active.
2. Select each segment under the preview in turn: *Working*, *Needs you*, *Done*, *Error*.

**Expected**

- The preview shows a small Dock of six coloured tiles (folder, Safari, Terminal, Messages, music, gear) and Ambient's icon on a glass panel, with a wash of light rising from the bottom and a blurred bright band behind the small Dock.
- *Working* is coral (`#D97757`, the Claude colour) with a slow breath (about 3.2 s); *Needs you* is amber with a fast breath (about 1.2 s); *Done* is steady green; *Error* is steady red. The preview shows no arrival bloom or pulses for done and error.
- The preview always shows the band behind the small Dock, whether or not Ambient has Accessibility access.
- VoiceOver reads the preview as *Preview of the Dock glow*.

### DCK-016 · With Reduce motion the glow holds steady

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Dock/DockGlow.swift`, `Sources/AmbientApp/Settings/Previews/DockGlowPreview.swift`
- **Automated by:** none
- **Needs:** System Settings › Accessibility › Display › Reduce motion on

**Steps**

1. Run `ambient emit working --session qa-rm --agent Build`, watch 10 seconds.
2. Run `ambient emit waiting --session qa-rm --agent Build --reason command --message "rm -rf build"`, watch 10 seconds.
3. Run `ambient emit error --session qa-rm --agent Build --message "make failed"`.
4. Open Settings › Appearance › Dock and select *Needs you* in the preview.

**Expected**

- Steps 1–2: the glow shows in grey-blue, then amber, each at a fixed mid brightness, with no breathing.
- Step 3: the glow turns red with no pulses.
- Step 4: the preview is amber and still.
