# Living Wallpaper: a world your agents live in, on the desktop and the lock screen

Date: 2026-09-29
Status: design approved in chat, section by section; spec awaiting review

## Problem

Every Ambient signal (island, Dock glow, menu bar, banners) disappears the moment the Mac locks, which
is exactly when you've stepped away and want to know whether an agent needs you. At the desk, the
desktop itself carries no signal at all.

## Goal

A living wallpaper that is worth looking at on its own and that your agents live in. It shows:

- a scene that follows the real time of day;
- one inhabitant per agent session, whose look follows what the session is doing;
- the details: live per-session state, the day's story (totals), and a recent timeline;
- your day: the clock, the date and your next calendar event.

It covers both surfaces: the desktop while you work, and the lock screen while you're away.

Non-goals: the pre-login window after a restart (no agents run there), weather (it needs the
network, and Ambient promises none), history beyond today.

## Spike findings (macOS 27.0, 26A428; probes were throwaway and not kept)

1. **Setting the wallpaper while locked reaches the lock screen, live.** `NSWorkspace.setDesktopImageURL`
   changed the lock screen six times in 47 s; each call takes 3–10 ms. But:
   - it applies to the current Space only (other Spaces kept the user's wallpaper);
   - it records per-display and per-Space entries in
     `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`;
   - the public API can't restore a color or aerial choice: for a black system color,
     `desktopImageURL(for:)` reports `DefaultDesktop.heic`.
2. **Restoring works by putting the store file back.** Copying a backup of `Index.plist` back and running
   `killall WallpaperAgent` restored the exact choices (black system color, Sequoia aerial idle) three
   times out of three. `WallpaperAgent` rewrites the file on launch (only timestamps differ).
3. **A window can be drawn over the lock screen with SkyLight.** A window in a space created with
   `SLSSpaceCreate(cid, 1, 0)` and `SLSSpaceSetAbsoluteLevel(cid, space, 400)`, shown with
   `SLSShowSpaces` and filled with `SLSSpaceAddWindowsAndRemoveFromSpaces(…, 7)`, was visible and
   updating every second on the lock screen. Level 100 was not. An ordinary `.screenSaver`-level window was not.
4. **`occlusionState` tells the truth on the lock screen.** While locked, the level-400 window reported
   `.visible`, and the level-100 and ordinary windows didn't. This is the basis of the self-check below.
5. **Ctrl-Cmd-Q emits lock → unlock → lock within 1–4 s** on this Mac, every time.
6. A window in a level-400 space floats above everything while unlocked too, so it must be transparent
   and click-through until the Mac locks.

## Design

### Units

AmbientCore (pure, unit-tested):

| Unit | Job |
| --- | --- |
| `DayLog` | Folds each `SessionChange` into today's story and timeline; `Codable`; resets at local midnight |
| `SceneState` | Everything a scene draws, as data: phase, inhabitants, build-up, text, with privacy applied per surface |
| `ScenePolicy` | Which world is showing: the picked one, or one per day chosen from the date |
| `WallpaperStore` | Parses `Index.plist` into a summary of the desktop and idle choices; says whether the format is one we know, and whether two stores match |

AmbientApp, in `Sources/AmbientApp/Wallpaper/`:

| Unit | Job |
| --- | --- |
| `SceneView` | SwiftUI `Canvas` + `TimelineView`; hosts one world and the shared text layer |
| `SkyScene`, `HarborScene`, `GardenScene` | Draw a `SceneState`, as vector shapes with no image assets |
| `DesktopLayer` | Desktop-level window per display, on every Space |
| `LockMonitor` | Debounced lock state |
| `SkyLight` | `dlopen`/`dlsym` wrapper for the five SkyLight functions; `isAvailable` |
| `LockLayer` | Level-400 SkyLight space with a window per display, visible only while locked, with a self-check |
| `WallpaperSwap` | Fallback: swaps the real wallpaper while locked, then restores it; crash recovery |
| `CalendarSource` | Next timed event later today, through EventKit |
| `WallpaperPane` | Settings pane |
| `LivingWallpaper` | Coordinator: owns the layers, `LockMonitor` and `CalendarSource`; builds `SceneState` from `AppModel` and `Preferences`; decides which surface draws |

Wiring follows `IslandController` and `DockGlow`: `AppDelegate` creates a `LivingWallpaper` coordinator
that subscribes to `AppModel` and `Preferences`.

### Data flow

```
AppModel.transitions ─▶ DayLog ─┐
AppModel.sessions ──────────────┼─▶ SceneState ─▶ SceneView ─▶ DesktopLayer   (at the desk)
CalendarSource, clock ──────────┘                           ├─▶ LockLayer      (locked, SkyLight works)
                                                            └─▶ WallpaperSwap  (locked, fallback; ImageRenderer → PNG)
```

### Day's story (`DayLog`)

| Shown as | Counted from |
| --- | --- |
| Agent time | `turnDuration` of turns finished today, plus live elapsed of running turns; time before midnight is not counted; parallel sessions add up (hence "agent time") |
| Tools | each `.toolStarted` |
| Turns done / failed | each `.turnCompleted` / `.turnFailed` |
| Needed you | each `.needsInput` that moves a session into waiting (repeats while waiting don't count) |
| Projects | distinct project folders seen today |
| Longest run | largest `turnDuration` today |
| Build-up | one entry per finished or failed turn: agent, outcome, time. Scenes draw up to 40; counts stay exact |
| Timeline | the last 20 needs-you / done / failed moments: time, agent, outcome, session title or project |

- **No free text is ever stored** in `DayLog`: no summaries, prompts or tool hints. Free text is shown only
  for live sessions, read from session state Ambient already keeps.
- Saved to `~/.ambient/day.json` (0600, atomic, debounced 1 s), like `state.json`.
- Rolls over on the first event or sweep after local midnight.
- `demo-` sessions are ignored.

### Scenes

Shared rules (the engine):

- **Phase.** Night, dawn 05:00–07:30, day, dusk 17:30–21:00 on the local clock. Palettes blend across each
  transition window, recomputed every minute. There's no location lookup.
- **Inhabitants.** One per session Ambient is tracking (idle ones rest), up to 8, most urgent first;
  beyond that a "+N more" label. Each takes a stable slot
  chosen from a hash of its session id.
  - Body color = `Palette.agent`, glow = `Palette.mood`.
  - Rhythms reuse `GlowStyle` timings: working breathes every 3.2 s, needs-you pulses every 1.2 s,
    done holds steady.
  - Busyness comes from `toolCount` on a log scale, capped.
- **Moments.** When a turn finishes, a ~2 s animation carries it into the day's build-up.
- **Text layer**, shared by all worlds:
  - top-left: clock, date, next event;
  - beside each inhabitant: title or project, state and `Describe.clock`, and the free-text line
    (`Describe.activity`);
  - bottom-left: the day's story; bottom-right: the last 3–5 timeline moments.
  - Each phase defines the ink: light at night, dawn and dusk; dark by day.
- **Idle.** With no sessions, the world rests. The build-up, story and timeline stay.
- **Displays.** Every display draws the world. Inhabitants and text appear on the main display only
  (`NSScreen.screens[0]`, the one with the menu bar).
- **Lock variant.**
  - No clock or date (macOS draws its own).
  - Inhabitant slots and labels avoid the top-center clock and the bottom-center password area.
  - Free text (tool hints, prompts, summaries) and calendar event titles are removed unless
    *Show messages on the lock screen* is on. The event then reads "Next event at 19:30".

The worlds:

| | Sky | Harbor | Garden |
| --- | --- | --- | --- |
| A session is | a star | a boat with a lantern | a plant |
| Working | twinkles; sparks circle as tools run | sails; wake lengthens with tools | grows taller with tools |
| Needs you | pulses amber | swings an amber lantern at the pier | holds up a pulsing amber bud |
| Done | settles green, then streaks into the constellation | ties up green | blooms |
| Failed | flickers red | fires a red flare | droops red |
| Idle | dims | anchored, lantern off | closes |
| The day builds | a constellation | boats moored along the pier | a flower bed |
| At night | the Milky Way | a lighthouse beam | fireflies |

Choosing: a picker with Sky, Harbor, Garden, and "A new one each day". The daily option rotates in a
fixed order at midnight, when the day's build-up resets.

Reference sketches: `.superpowers/brainstorm/*/content/living-scene.html` (local, not committed).

### Surfaces

**`DesktopLayer` (public API).**
- Window setup:
  - one borderless window per `NSScreen`;
  - level `CGWindowLevelForKey(.desktopWindow)`: above the wallpaper, below Finder's icons;
  - collection behavior `[.canJoinAllSpaces, .stationary, .ignoresCycle]`;
  - `ignoresMouseEvents`, so "click wallpaper to reveal desktop" still works;
  - never key, and not shown in Mission Control.
- Rebuilds on `didChangeScreenParametersNotification`.
- Animation pauses when `occlusionState` lacks `.visible`, while the displays sleep, and while locked.
- Turning it off, quitting or crashing just removes the windows. Nothing is restored because nothing
  was changed.

**`LockMonitor`.**
- Listens for `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` on
  `DistributedNotificationCenter`.
- Initial state comes from `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`.
- A lock counts once it has held for 2 s (finding 5). An unlock counts immediately.

**`LockLayer` (SkyLight, private API).**
- At start, `SkyLight` resolves `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`,
  `SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces`.
- It creates one level-400 space, with a window per display showing the lock variant.
- While unlocked, those windows have `alphaValue = 0` and are click-through (finding 6).
- On lock they fade in; on unlock they go to 0 immediately.
- **Self-check.** 2 s after each lock, read `occlusionState` (finding 4). If it isn't `.visible`, or a
  symbol is missing, or space creation fails, then:
  - use `WallpaperSwap` for that lock;
  - remember the result for this macOS build (`ProcessInfo.operatingSystemVersionString`) in
    `UserDefaults`, so later locks go straight to the fallback until the build changes.

**`WallpaperSwap` (fallback, only while locked).**
1. On lock, when no restore is pending:
   - parse the store with `WallpaperStore`, and don't swap if the format is unknown;
   - copy `Index.plist` to `~/.ambient/backups/wallpaper-Index.plist`;
   - write the marker `~/.ambient/wallpaper-swapped`.
2. While locked:
   - render the lock variant per display at native pixel size with `ImageRenderer`;
   - write it to `~/.ambient/wallpaper/scene-<uuid>.png` (a unique name defeats caching) and set it
     for each screen;
   - re-render every 30 s, and on any mood change, with at least 8 s between swaps.
3. On unlock:
   - copy the backup over `Index.plist` and run `/usr/bin/killall WallpaperAgent`;
   - confirm with `WallpaperStore` that the store matches the backup;
   - delete the marker and the PNGs.
4. On launch with the marker present: restore before anything else (crash recovery).
5. If a restore fails:
   - keep the marker, and retry on the next unlock and launch;
   - the Wallpaper pane shows **Restore my wallpaper** until a restore succeeds.

### Settings: the Wallpaper pane

A new `SettingsPane.wallpaper`, between Dock Glow and General, with:

- a live preview of the chosen world, with demo sessions;
- **Living wallpaper**, off by default (it changes how the whole desktop looks);
- **Scene**: Sky, Harbor, Garden, A new one each day, with thumbnails;
- **On the lock screen**, on by default, with a status line: *live*, *wallpaper swap* or *unavailable*;
- **Show messages on the lock screen**, off by default;
- **Next calendar event**, with *Grant access*;
- **Restore my wallpaper**, shown only when a restore is pending.

New `Preferences` keys: `wallpaperEnabled` (false), `wallpaperScene` ("sky" | "harbor" | "garden" |
"daily", default "daily"), `wallpaperOnLockScreen` (true), `wallpaperLockMessages` (false),
`wallpaperCalendar` (false).

### Calendar

- EventKit full access (`requestFullAccessToEvents`), which needs:
  - `NSCalendarsFullAccessUsageDescription` in `Info.plist`;
  - the `com.apple.security.personal-information.calendars` hardened-runtime entitlement.
- Shows the next timed (not all-day) event that starts later today: title up to 40 characters, and its
  start time.
- Refreshes on `EKEventStoreChanged` and every 5 minutes.
- Without access, the scene leaves the line out.

### Cost and accessibility

- **Frame rate:** `TimelineView(.animation(minimumInterval: 1/30))` while something moves, about 1 fps
  otherwise.
- **Paused:** when occluded, while the displays sleep, and for the desk layer while locked.
- **Low Power Mode** (`ProcessInfo.isLowPowerModeEnabled`): still frames, redrawn only on changes.
- **Reduce Motion:** no drift or orbit; pulses become opacity fades.
- **Target:** under 2 % CPU at the desk while visible on Apple Silicon, and about 0 when covered.
  Measured, not assumed.

### Error handling

- Each surface degrades on its own, and none crashes the app.
- Logs go to the `Logger` category `wallpaper`.
- SkyLight missing or not visible → fallback. Store format unknown → the lock screen is *unavailable*
  and the desk still works. Restore failure → marker kept, retried, surfaced in Settings.

### Privacy and docs

- **README:**
  - the feature;
  - a row in *What Ambient changes on your system* for `Index.plist`: only during a locked fallback,
    backed up first, restored on unlock;
  - a note that the lock screen uses a private macOS API;
  - the calendar permission.
- The network promise is unchanged: no weather, no location.
- **CHANGELOG** entry.

## Testing

Unit tests (`swift test`):

- **`DayLog`:**
  - each event kind, and repeated `needsInput`;
  - the midnight rollover, and a turn crossing midnight;
  - demo sessions ignored, and the 20-entry timeline cap;
  - a `Codable` round trip, and a check that the encoded file holds no free text.
- **`SceneState`:**
  - phase and blend at every boundary, and ink per phase;
  - stable slots, and the 8-inhabitant cap with "+N more";
  - lock privacy removes free text and event titles, and the switch restores them;
  - text on the main display only.
- **`ScenePolicy`:** the daily rotation is deterministic and changes at midnight.
- **`WallpaperStore`:** parses synthetic `Index.plist` fixtures (color, image, aerial, per-Space entries),
  rejects unknown formats, and compares stores ignoring timestamps.

Manual checklist (as for the island and Dock glow):

- **At the desk:** every Space and display, click-through, and covered/uncovered pausing.
- **Lock screen:** the live layer, and the fallback forced with the debug default
  `AmbientForceWallpaperSwap`.
- **Crash recovery:** `kill -9` while locked in fallback, then relaunch; the wallpaper must be restored.
- **Comfort:** Reduce Motion, Low Power Mode, and a CPU measurement.
- `ambient demo` drives the scene.

## Tasks

1. Core: `DayLog`, `SceneState`, `ScenePolicy`, `WallpaperStore`, all with tests; `AppModel` owns and
   publishes the `DayLog`.
2. Desk: `SceneView` engine, `SkyScene`, `DesktopLayer`, `Preferences` keys, Wallpaper pane.
3. Lock: `LockMonitor`, `SkyLight`, `LockLayer` with the self-check.
4. Fallback: `WallpaperSwap` and crash recovery, and *Restore my wallpaper*.
5. Worlds: `HarborScene`, `GardenScene`, and the daily rotation in the picker.
6. Calendar: `CalendarSource`, entitlement, usage string, *Grant access*.
7. Docs: README, CHANGELOG.

Each task leaves a working app.
