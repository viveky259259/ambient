# Settings redesign: an Apple-style window and a small design system

Date: 2026-09-26
Status: approved in chat (direction B: Liquid Glass, floating sidebar, live previews)

## Problem

Settings and first run share one 600×700 scrolling `Form` (`SetupView`). Everything is on one long
page, nothing shows what a setting does, and the window doesn't look or feel like a current Apple app.

## Decisions

- Custom SwiftUI, not `NavigationSplitView`: full control over the look.
- Direction B: a floating glass sidebar with pill selection; each pane opens with a large title and a
  live preview of what it controls.
- One window. First run opens it on a **Welcome** pane at the top of the sidebar; no separate flow.
- A small design system (tokens + components) lives in the app target. The island, menu bar and
  notifications keep their current look for now.

## Design system — `Sources/AmbientApp/Design/`

### `Theme.swift` (tokens)

| Token | Values |
| --- | --- |
| Spacing | 4, 8, 12, 16, 20, 28 |
| Radius | control 8, card 14, panel 18, pill = capsule |
| Type | pane title 26 bold · section header 13 semibold, secondary · row 13 regular · caption 11, secondary |
| Status | success / warning / error / neutral, from `Palette` (`done`, `waiting`, `error`, `idle`) |
| Layout | sidebar width 200, content max width 560, preview height 150 |

### `Components.swift`

- `GlassPanel` — `glassEffect` in a rounded rect on macOS 26+; `.regularMaterial` plus a hairline
  stroke on 14–25. With Reduce Transparency: `windowBackgroundColor` plus a hairline.
- `SettingsSection` — optional header and footer around a `SettingsCard`.
- `SettingsCard` — grouped rows, radius 14, hairline dividers inset to the row's text.
- `SettingsRow` — title, optional subtitle, trailing accessory (toggle, button, badge, picker).
- `StatusBadge` — capsule with a dot and label (Connected, Needs update, Not connected, Not found,
  Config unreadable, Allowed, Enabled).
- `PillButtonStyle` — capsule button, `.prominent` (accent fill) and `.plain` (hairline).
- `SidebarItem` — SF Symbol and label; the selected item gets an accent-tinted capsule.

## Settings window — `Sources/AmbientApp/Settings/`

`SettingsView` replaces `SetupView` (deleted). An `HStack` holds the floating sidebar (`GlassPanel`,
inset 8pt, traffic lights over its top 28pt) and a `ScrollView` with the selected pane. The pane is
a `SettingsPane` enum: `welcome, agents, island, alerts, dock, general`.

`SetupModel` keeps its role: agent install state, notification and Accessibility status, login item.

### Panes — `Settings/Panes/`

| Pane | Preview | Contents |
| --- | --- | --- |
| Welcome | App icon, "Welcome to Ambient", tagline | Checklist with live status: connect agents ("2 of 3 connected", Connect all), allow notifications, play the demo. First run: a prominent **Get started** button that marks setup done and closes the window. |
| Agents | none | One row per agent: agent-colored dot, name, config path, `StatusBadge`, Connect / Update / Remove. Codex `/hooks` note inline; the footer explains backups. |
| Notch island | `IslandPreview` | Show agent status at the notch; Show while agents are working. |
| Alerts | `NotificationPreview` | Notifications toggle plus permission badge or button; Chimes toggle; volume slider with speaker symbols; "Announce finished turns longer than" picker; the "stays quiet while you're in the app" caption. |
| Dock glow | `DockGlowPreview` | Glow toggle; intensity slider; "Light up behind the Dock's glass" row with Accessibility status or Enable button. |
| General | none | Open at login (plus approval note); command-line tool path with Copy; About card: version, `ambient doctor`, license, GitHub link. |

### Previews — `Settings/Previews/`

- `IslandPreview` — the real `IslandView` driven by its own `IslandViewModel` with synthetic
  sessions and a fixed geometry (notch 180×32), hanging from a mock menu bar. Cycles
  collapsed-working → bloom needs-you → bloom done every 3 s. Dims with an "Off" label when the island
  is off; skips the working state when "show while working" is off.
- `NotificationPreview` — a copy of Ambient's banner (app icon, title, body, "Claude Code ·
  Terminal") with a segmented Needs you | Done | Error control; choosing a state swaps the copy and
  plays that chime at the current volume, if chimes are on.
- `DockGlowPreview` — a strip of desktop with a glass Dock; the glow uses `GlowStyle` for the chosen
  state (chips for Working, Needs you, Done, Error), breathes at the style's period, and follows the
  intensity slider.

Previews are `accessibilityHidden` with a one-line label, hold still under Reduce Motion, and stop
their timers when their pane leaves the screen.

## Window behavior (`AppDelegate.showSetup`)

- About 780×560, resizable, minimum 700×480. `.fullSizeContentView`, transparent title bar, hidden
  title, window background by the system.
- First run selects Welcome; later opens select the last pane (`@AppStorage("settingsPane")`).
- Closing still marks setup done and returns to the accessory activation policy.
- ↑/↓ move the sidebar selection; ⌘W closes.

## Verification

The app target has no UI tests, and this change is UI only.

1. `swift build` and `swift test` (core unchanged).
2. `scripts/build-app.sh --run` (replaces the running Ambient while testing).
3. Screenshot every pane in light and dark mode; check that toggles drive the previews.
4. First run: `defaults write com.viveky259259.Ambient setupCompleted -bool false`, relaunch, walk
   Welcome → Get started, then restore the setting.
5. Restart `/Applications/Ambient.app`.

## Out of scope

- Restyling the island, menu bar or notifications.
- Allow/Deny actions in permission notifications (its own design, next).
