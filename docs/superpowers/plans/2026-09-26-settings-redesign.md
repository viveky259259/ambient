# Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-page setup `Form` with an Apple-style settings window — floating glass sidebar, six panes, live previews — built on a small design system.

**Architecture:** Tokens and shared components live in `Sources/AmbientApp/Design/`. The window (`Settings/SettingsView.swift`) is an `HStack` of a glass sidebar and a scrolling pane; each pane is its own file under `Settings/Panes/`, and the previews under `Settings/Previews/` reuse the real `IslandView`, `GlowStyle` and chimes. `SetupModel` keeps owning status; `AppDelegate.showSetup` hosts the new view.

**Tech Stack:** Swift 6 toolchain (app target in Swift 5 mode), SwiftUI + AppKit, macOS 14 deployment target, macOS 27 SDK (`glassEffect` behind `#available(macOS 26, *)`).

**Spec:** `docs/superpowers/specs/2026-09-26-settings-redesign-design.md`

## Global Constraints

- Deployment target stays macOS 14; anything newer is behind `#available`.
- No new dependencies. No changes to `AmbientCore`.
- Tokens: spacing 4/8/12/16/20/28; radius control 8, card 14, panel 18; pane title 26 bold; section header 13 semibold; row 13; caption 11.
- Layout: sidebar 200, content max width 560, preview height 150, window 780×560, minimum 700×480.
- Pane and sidebar titles use title case (Apple HIG); row labels and descriptions use sentence case.
- Previews: `accessibilityHidden`-style single label, still under Reduce Motion, timers stop when the pane leaves.
- Reduce Transparency: glass becomes a solid window-colored surface with a hairline.
- The app target has no UI tests; each task is verified by `swift build` (and `swift test` for the untouched core), and the last tasks by running the app.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/AmbientApp/Design/Theme.swift` (new) | Tokens: space, radius, fonts, layout, colors, status |
| `Sources/AmbientApp/Design/Components.swift` (new) | `glassPanel`, `SettingsSection`, `SettingsCard`, `SettingsDivider`, `SettingsRow`, `SettingsToggleRow`, `StatusBadge`, `PillButtonStyle`, `SidebarItem` |
| `Sources/AmbientApp/Settings/SettingsPane.swift` (new) | Pane enum (title, symbol, subtitle) and `PaneHeader` |
| `Sources/AmbientApp/Settings/Previews/PreviewStage.swift` (new) | Desktop backdrop with the "Off" veil |
| `Sources/AmbientApp/Settings/Previews/IslandPreview.swift` (new) | Real `IslandView` cycling scenes |
| `Sources/AmbientApp/Settings/Previews/NotificationPreview.swift` (new) | Banner copy per moment + chime |
| `Sources/AmbientApp/Settings/Previews/DockGlowPreview.swift` (new) | Mini Dock with breathing glow |
| `Sources/AmbientApp/Settings/Panes/*.swift` (new) | Welcome, Agents, Island, Alerts, Dock, General |
| `Sources/AmbientApp/Settings/SettingsView.swift` (new) | Sidebar, pane switching, keyboard |
| `Sources/AmbientApp/Setup/SetupModel.swift` (modify) | `installAll()` |
| `Sources/AmbientApp/AppDelegate.swift` (modify) | Host `SettingsView`, window chrome |
| `Sources/AmbientApp/Setup/SetupView.swift` (delete) | Replaced |
| `README.md`, `CHANGELOG.md` (modify) | Install steps and release note |

---

### Task 1: Design system

**Files:**
- Create: `Sources/AmbientApp/Design/Theme.swift`
- Create: `Sources/AmbientApp/Design/Components.swift`

**Interfaces:**
- Consumes: `Palette` (AmbientCore), `RGB.color` (`Sources/AmbientApp/Colors.swift`).
- Produces: `Theme.Space.{xxs,xs,sm,md,lg,xl}`, `Theme.Radius.{control,card,panel}`, `Theme.Fonts.*`, `Theme.Layout.*`, `Theme.Colors.{card,hairline,hover,selection,wallpaper(_:)}`, `Theme.Status` (`.color`, `.textColor`); `View.glassPanel(radius:)`, `View.settingsRowPadding()`; `SettingsSection(header:footer:content:)`, `SettingsCard(content:)`, `SettingsDivider()`, `SettingsRow(title:subtitle:subtitleStatus:accessory:)`, `SettingsToggleRow(title:subtitle:subtitleStatus:isOn:)`, `StatusBadge(_:_:)`, `ButtonStyle.pill / .pillProminent / .pillProminentLarge`, `SidebarItem(title:symbol:selected:action:)`.

- [ ] **Step 1: Write the tokens**

**File:** `Sources/AmbientApp/Design/Theme.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI

/// Ambient's design tokens: spacing, shape, type, color and layout, in one place.
enum Theme {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let panel: CGFloat = 18
    }

    enum Fonts {
        static let heroTitle = Font.system(size: 30, weight: .bold)
        static let paneTitle = Font.system(size: 26, weight: .bold)
        static let paneSubtitle = Font.system(size: 13)
        static let sectionHeader = Font.system(size: 13, weight: .semibold)
        static let row = Font.system(size: 13)
        static let rowEmphasis = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        static let mono = Font.system(size: 11, design: .monospaced)
        static let button = Font.system(size: 12, weight: .medium)
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 200
        static let contentMaxWidth: CGFloat = 560
        static let previewHeight: CGFloat = 150
        static let rowMinHeight: CGFloat = 44
        static let windowSize = CGSize(width: 780, height: 560)
        static let windowMinSize = CGSize(width: 700, height: 480)
    }

    enum Colors {
        /// Grouped-card fill: a lift above the window in both appearances.
        static let card = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.75)
        })
        static let hairline = Color(nsColor: .separatorColor)
        static let hover = Color.primary.opacity(0.05)
        static let selection = Color.accentColor.opacity(0.16)

        /// A soft desktop behind the previews.
        static func wallpaper(_ scheme: ColorScheme) -> LinearGradient {
            let colors: [Color] = scheme == .dark
                ? [Color(red: 0.11, green: 0.16, blue: 0.29), Color(red: 0.23, green: 0.14, blue: 0.29)]
                : [Color(red: 0.62, green: 0.76, blue: 0.96), Color(red: 0.95, green: 0.78, blue: 0.85)]
            return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// What a badge, dot or note is saying.
    enum Status {
        case success, warning, error, neutral

        /// Fills: dots and tints, in Ambient's own palette.
        var color: Color {
            switch self {
            case .success: Palette.done.color
            case .warning: Palette.waiting.color
            case .error: Palette.error.color
            case .neutral: Palette.idle.color
            }
        }

        /// Text: system colors keep their contrast in light and dark.
        var textColor: Color {
            switch self {
            case .success: .green
            case .warning: .orange
            case .error: .red
            case .neutral: .secondary
            }
        }
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
```

- [ ] **Step 2: Write the components**

**File:** `Sources/AmbientApp/Design/Components.swift`
```swift
import SwiftUI

// MARK: - Glass

/// Liquid Glass on macOS 26 and later; a material with a hairline edge before it, or a solid
/// surface when the user asks for less transparency.
private struct GlassBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = Theme.Radius.panel) -> some View {
        modifier(GlassBackground(radius: radius))
    }

    /// The padding every settings row shares.
    func settingsRowPadding() -> some View {
        padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 9)
            .frame(minHeight: Theme.Layout.rowMinHeight)
    }
}

// MARK: - Sections and rows

/// A titled group of rows on a card, with an optional footnote. Footers read Markdown.
struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(Theme.Fonts.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Space.sm)
                    .accessibilityAddTraits(.isHeader)
            }
            SettingsCard { content }
            if let footer {
                Text(LocalizedStringKey(footer))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.sm)
            }
        }
    }
}

/// Rows on a rounded card.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 0) { content }
            .background(Theme.Colors.card, in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.hairline.opacity(0.6), lineWidth: 0.5))
    }
}

/// A hairline between rows, inset like the system's.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 0.5)
            .padding(.leading, Theme.Space.sm)
    }
}

/// A title, an optional subtitle, and a control on the trailing edge.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleStatus: Theme.Status = .neutral
    @ViewBuilder var accessory: Accessory
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.row)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(subtitleStatus.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            Spacer(minLength: Theme.Space.sm)
            accessory
        }
        .settingsRowPadding()
    }
}

/// A row whose control is a switch.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var subtitleStatus: Theme.Status = .neutral
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, subtitleStatus: subtitleStatus) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - Status

/// A dot and a word: Connected, Needs update, Allowed.
struct StatusBadge: View {
    let text: String
    let status: Theme.Status

    init(_ text: String, _ status: Theme.Status) {
        self.text = text
        self.status = status
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(text).font(Theme.Fonts.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// Capsule buttons: `.pill` for most actions, `.pillProminent` for the one that moves you forward.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case plain, prominent }
    var kind: Kind = .plain
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind, large: large)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let prominent = kind == .prominent
        configuration.label
            .font(large ? .system(size: 13, weight: .semibold) : Theme.Fonts.button)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, large ? 22 : 12)
            .padding(.vertical, large ? 8 : 4)
            .background(Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(hovered ? 0.11 : 0.07)))
            .overlay(Capsule().fill(Color.black.opacity(prominent && hovered ? 0.08 : 0)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(kind: .prominent) }
    static var pillProminentLarge: PillButtonStyle { PillButtonStyle(kind: .prominent, large: true) }
}

// MARK: - Sidebar

/// A sidebar row with a soft pill behind the selection.
struct SidebarItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.hover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build --product AmbientApp`
Expected: `Build complete!` (the new types are unused so far; no warnings about them are errors).

- [ ] **Step 4: Commit**

```bash
git add Sources/AmbientApp/Design
git commit -m "feat(app): design tokens and shared settings components"
```

---

### Task 2: Pane model and live previews

**Files:**
- Create: `Sources/AmbientApp/Settings/SettingsPane.swift`
- Create: `Sources/AmbientApp/Settings/Previews/PreviewStage.swift`
- Create: `Sources/AmbientApp/Settings/Previews/IslandPreview.swift`
- Create: `Sources/AmbientApp/Settings/Previews/NotificationPreview.swift`
- Create: `Sources/AmbientApp/Settings/Previews/DockGlowPreview.swift`

**Interfaces:**
- Consumes: Task 1 tokens and components; `IslandView(model:)`, `IslandViewModel(geometry:)` (`.sessions`, `.presentation`), `IslandGeometry(screenFrame:hasNotch:notchWidth:notchHeight:centerX:)`; `Session(agent:sessionId:at:)`; `GlowStyle.for(mood:agent:)`.
- Produces: `SettingsPane` (`.title`, `.symbol`, `.subtitle`, `CaseIterable`, `String` raw values), `PaneHeader(pane:)`, `PreviewStage(enabled:alignment:content:)`, `IslandPreview(enabled:showsWorking:)`, `NotificationPreview(enabled:chimesOn:onPlay:)`, `DockGlowPreview(enabled:intensity:)`.

- [ ] **Step 1: Write the pane model and header**

**File:** `Sources/AmbientApp/Settings/SettingsPane.swift`
```swift
import SwiftUI

/// The panes of the settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, agents, island, alerts, dock, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .agents: "Agents"
        case .island: "Notch Island"
        case .alerts: "Alerts"
        case .dock: "Dock Glow"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .agents: "terminal"
        case .island: "laptopcomputer"
        case .alerts: "bell.badge"
        case .dock: "dock.rectangle"
        case .general: "gearshape"
        }
    }

    var subtitle: String? {
        switch self {
        case .welcome: nil
        case .agents: "Ambient listens to your agents through lightweight hooks."
        case .island: "A quiet status light that grows out of the notch."
        case .alerts: "Banners and chimes for the moments that need you."
        case .dock: "Light along the Dock in the color of what your agents are doing."
        case .general: "Startup, the command-line tool, and version."
        }
    }
}

/// A pane's large title and one-line description.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pane.title).font(Theme.Fonts.paneTitle)
            if let subtitle = pane.subtitle {
                Text(subtitle).font(Theme.Fonts.paneSubtitle).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
```

- [ ] **Step 2: Write the preview stage**

**File:** `Sources/AmbientApp/Settings/Previews/PreviewStage.swift`
```swift
import SwiftUI

/// A patch of desktop for a live preview, veiled with "Off" while the feature is disabled.
struct PreviewStage<Content: View>: View {
    var enabled = true
    var alignment: Alignment = .top
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        ZStack(alignment: alignment) {
            Theme.Colors.wallpaper(scheme)
            content
                .opacity(enabled ? 1 : 0.35)
                .saturation(enabled ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Layout.previewHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        .overlay(alignment: .bottomLeading) {
            if !enabled {
                Text("Off")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(Theme.Space.sm)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: enabled)
    }
}
```

- [ ] **Step 3: Write the island preview**

**File:** `Sources/AmbientApp/Settings/Previews/IslandPreview.swift`
```swift
import AmbientCore
import SwiftUI

/// The real island, hanging from a pretend menu bar, cycling through what it shows.
struct IslandPreview: View {
    let enabled: Bool
    let showsWorking: Bool

    @StateObject private var island = IslandViewModel(geometry: IslandPreview.geometry)
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let geometry = IslandGeometry(screenFrame: .zero, hasNotch: true, notchWidth: 150,
                                                 notchHeight: 24, centerX: 0)

    private enum Scene { case working, waiting, done }

    var body: some View {
        PreviewStage(enabled: enabled) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(scheme == .dark ? 0.08 : 0.3))
                    .frame(height: Self.geometry.notchHeight)
                IslandView(model: island)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the notch island")
        .onAppear(perform: apply)
        .onChange(of: enabled) { apply() }
        .onChange(of: showsWorking) { apply() }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return apply() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                step += 1
                apply()
            }
        }
    }

    private var scenes: [Scene] { showsWorking ? [.working, .waiting, .done] : [.waiting, .done] }

    private func apply() {
        guard enabled else {
            island.sessions = []
            island.presentation = .hidden
            return
        }
        let scene = reduceMotion ? .waiting : scenes[step % scenes.count]
        let session = Self.session(scene)
        island.sessions = [session]
        island.presentation = scene == .working ? .collapsed : .bloom(session.id)
    }

    private static func session(_ scene: Scene) -> Session {
        let now = Date()
        var s = Session(agent: .claude, sessionId: "preview", at: now)
        s.cwd = "/preview/api-server"
        s.turnStartedAt = now.addingTimeInterval(-134)
        switch scene {
        case .working:
            s.activity = .tool(name: "Bash", detail: "npm test")
        case .waiting:
            s.activity = .waiting(reason: "permission", message: "Bash: rm -rf build")
        case .done:
            s.activity = .done(summary: "All 42 tests pass. Ready for review.")
            s.turnEndedAt = now
        }
        return s
    }
}
```

- [ ] **Step 4: Write the notification preview**

**File:** `Sources/AmbientApp/Settings/Previews/NotificationPreview.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI

/// An Ambient banner as macOS shows it, for each moment that notifies, with its chime.
struct NotificationPreview: View {
    let enabled: Bool
    let chimesOn: Bool
    let onPlay: (Mood) -> Void
    @State private var mood: Mood = .waiting

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            PreviewStage(enabled: enabled, alignment: .topTrailing) {
                BannerMock(mood: mood)
                    .padding(Theme.Space.sm)
                    .id(mood)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mood)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of an Ambient notification")
            HStack(spacing: Theme.Space.xs) {
                Picker("Moment", selection: $mood) {
                    Text("Needs you").tag(Mood.waiting)
                    Text("Done").tag(Mood.done)
                    Text("Error").tag(Mood.error)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Button { onPlay(mood) } label: { Label("Play Chime", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.pill)
            }
            .onChange(of: mood) { if chimesOn { onPlay(mood) } }
        }
    }
}

private struct BannerMock: View {
    let mood: Mood

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Claude · Terminal").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(copy.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
        .glassPanel(radius: 18)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// The same words `Notifier` posts.
    private var copy: (title: String, body: String) {
        switch mood {
        case .done: ("api-server is done", "All 42 tests pass. Ready for review.")
        case .error: ("api-server stopped with an error", "Rate limited — retry in 2 minutes")
        default: ("api-server needs your permission", "Bash: rm -rf build")
        }
    }
}
```

- [ ] **Step 5: Write the Dock glow preview**

**File:** `Sources/AmbientApp/Settings/Previews/DockGlowPreview.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI

/// A small Dock that glows like the real one: the state's color, breathing at its pace,
/// scaled by the intensity slider.
struct DockGlowPreview: View {
    let enabled: Bool
    let intensity: Double
    @State private var mood: Mood = .working
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            PreviewStage(enabled: enabled, alignment: .bottom) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !enabled)) { context in
                    ZStack(alignment: .bottom) {
                        glow(at: context.date)
                        MiniDock().padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the Dock glow")
            Picker("State", selection: $mood) {
                Text("Working").tag(Mood.working)
                Text("Needs you").tag(Mood.waiting)
                Text("Done").tag(Mood.done)
                Text("Error").tag(Mood.error)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
        }
    }

    @ViewBuilder private func glow(at date: Date) -> some View {
        if let style = GlowStyle.for(mood: mood, agent: .claude) {
            Ellipse()
                .fill(style.color.color)
                .frame(width: 330, height: 70)
                .blur(radius: 24)
                .opacity(level(style, at: date) * intensity)
                .offset(y: 30)
        }
    }

    /// Where the breath is: between the style's low and high, or steady.
    private func level(_ style: GlowStyle, at date: Date) -> Double {
        guard let period = style.period, !reduceMotion else { return (style.low + style.high) / 2 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return style.low + (style.high - style.low) * (0.5 - 0.5 * cos(phase * 2 * .pi))
    }
}

/// A Dock with a few familiar-looking tiles and Ambient at the end.
private struct MiniDock: View {
    private static let symbols = ["folder.fill", "safari.fill", "terminal.fill", "message.fill", "music.note", "gearshape.fill"]
    private static let colors: [Color] = [.blue, .cyan, .black, .green, .pink, .gray]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Self.symbols.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Self.colors[i].gradient)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: Self.symbols[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white))
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassPanel(radius: 16)
    }
}
```

- [ ] **Step 6: Build**

Run: `swift build --product AmbientApp`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/AmbientApp/Settings
git commit -m "feat(app): settings panes model and live previews for island, notifications and Dock glow"
```

---

### Task 3: Panes, window and wiring

**Files:**
- Create: `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/IslandPane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/DockPane.swift`
- Create: `Sources/AmbientApp/Settings/Panes/GeneralPane.swift`
- Create: `Sources/AmbientApp/Settings/SettingsView.swift`
- Modify: `Sources/AmbientApp/Setup/SetupModel.swift` (add `installAll()`)
- Modify: `Sources/AmbientApp/AppDelegate.swift:73-101` (`showSetup`)
- Delete: `Sources/AmbientApp/Setup/SetupView.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–2; `SetupModel` (`agentStates`, `agentErrors`, `notificationStatus`, `accessibilityTrusted`, `launchAtLogin`, `loginItemNeedsApproval`, `installer`, `paths`, `refresh()`, `install(_:)`, `uninstall(_:)`, `requestNotifications()`, `requestAccessibility()`, `setLaunchAtLogin(_:)`); `Preferences` published properties.
- Produces: `SettingsView(setup:prefs:firstRun:onDemo:onPreviewSound:onDone:)` (same parameters `SetupView` had); `SetupModel.installAll()`.

- [ ] **Step 1: Add `installAll()` to `SetupModel`**

In `Sources/AmbientApp/Setup/SetupModel.swift`, after `func install(_ agent: AgentKind)`:

```swift
    /// Connects every agent on this Mac that isn't connected yet.
    func installAll() {
        for agent in AgentKind.allCases where [.notInstalled, .partial].contains(agentStates[agent] ?? .notInstalled) {
            install(agent)
        }
    }
```

- [ ] **Step 2: Write the Welcome pane**

**File:** `Sources/AmbientApp/Settings/Panes/WelcomePane.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI
import UserNotifications

/// First run's welcome, and afterwards a glance at whether everything is set up.
struct WelcomePane: View {
    @ObservedObject var setup: SetupModel
    let firstRun: Bool
    let onDemo: () -> Void
    let onGetStarted: () -> Void
    @State private var demoPlayed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            hero
            SettingsSection(header: "Get set up") {
                ChecklistRow(done: agentsReady, title: "Connect your agents", subtitle: agentsSummary) {
                    if !agentsReady && !found.isEmpty {
                        Button("Connect All") { setup.installAll() }.buttonStyle(.pillProminent)
                    }
                }
                SettingsDivider()
                ChecklistRow(done: notificationsAllowed, title: "Allow notifications",
                             subtitle: "So Ambient can tell you when an agent needs you.") {
                    if setup.notificationStatus == .denied {
                        Button("Open System Settings") { setup.requestNotifications() }.buttonStyle(.pill)
                    } else if !notificationsAllowed {
                        Button("Allow") { setup.requestNotifications() }.buttonStyle(.pill)
                    }
                }
                SettingsDivider()
                ChecklistRow(done: demoPlayed, title: "Watch the demo",
                             subtitle: "Every state on the notch, the Dock and the menu bar.") {
                    Button("Play Demo") {
                        demoPlayed = true
                        onDemo()
                    }
                    .buttonStyle(.pill)
                }
            }
            if firstRun {
                HStack {
                    Spacer()
                    Button("Get Started", action: onGetStarted)
                        .buttonStyle(.pillProminentLarge)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            Text(firstRun ? "Welcome to Ambient" : "Ambient")
                .font(Theme.Fonts.heroTitle)
            Text("Your desktop quietly shows what your coding agents are doing — and lights up when they need you.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.md)
    }

    /// Agents installed on this Mac.
    private var found: [AgentKind] {
        AgentKind.allCases.filter { (setup.agentStates[$0] ?? .notInstalled) != .agentMissing }
    }

    private var connected: [AgentKind] { found.filter { setup.agentStates[$0] == .installed } }
    private var agentsReady: Bool { !found.isEmpty && connected.count == found.count }

    private var agentsSummary: String {
        if found.isEmpty { return "No agents found yet. Install Claude Code, Codex or Gemini CLI." }
        return "\(connected.count) of \(found.count) connected"
    }

    private var notificationsAllowed: Bool {
        [.authorized, .provisional].contains(setup.notificationStatus)
    }
}

/// A step with a check that fills in once it's done.
private struct ChecklistRow<Accessory: View>: View {
    let done: Bool
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(done ? Theme.Status.success.color : Color.secondary.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.rowEmphasis)
                Text(subtitle).font(Theme.Fonts.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.sm)
            accessory
        }
        .settingsRowPadding()
    }
}
```

- [ ] **Step 3: Write the Agents pane**

**File:** `Sources/AmbientApp/Settings/Panes/AgentsPane.swift`
```swift
import AmbientCore
import SwiftUI

/// Connect, update or remove Ambient's hooks for each agent.
struct AgentsPane: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .agents)
            SettingsSection(footer: "Ambient adds background hooks that never slow your agent down, keeps a backup of every file it edits, and removes only its own entries.") {
                ForEach(Array(AgentKind.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { SettingsDivider() }
                    AgentRow(agent: agent,
                             state: setup.agentStates[agent] ?? .notInstalled,
                             error: setup.agentErrors[agent],
                             path: setup.installer.configURL(agent).path
                                 .replacingOccurrences(of: setup.paths.userHome.path, with: "~"),
                             install: { setup.install(agent) },
                             uninstall: { setup.uninstall(agent) })
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentKind
    let state: InstallState
    let error: String?
    let path: String
    let install: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(Palette.agent(agent).color.opacity(0.16))
                Circle().fill(Palette.agent(agent).color).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.rowEmphasis)
                Text(path).font(Theme.Fonts.mono).foregroundStyle(.secondary).textSelection(.enabled)
                if agent == .codex, state == .installed {
                    Text("Codex runs new hooks only after you approve them: type /hooks in Codex once.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.warning.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Status.error.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            badge
            action
        }
        .settingsRowPadding()
    }

    private var title: String {
        switch agent {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    private var badge: StatusBadge {
        switch state {
        case .installed: StatusBadge("Connected", .success)
        case .partial: StatusBadge("Needs update", .warning)
        case .notInstalled: StatusBadge("Not connected", .neutral)
        case .agentMissing: StatusBadge("Not found", .neutral)
        case .unreadable: StatusBadge("Config unreadable", .error)
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .installed: Button("Remove", action: uninstall).buttonStyle(.pill)
        case .partial: Button("Update", action: install).buttonStyle(.pillProminent)
        case .notInstalled: Button("Connect", action: install).buttonStyle(.pillProminent)
        case .agentMissing, .unreadable: EmptyView()
        }
    }
}
```

- [ ] **Step 4: Write the Notch Island pane**

**File:** `Sources/AmbientApp/Settings/Panes/IslandPane.swift`
```swift
import SwiftUI

struct IslandPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .island)
            IslandPreview(enabled: prefs.islandEnabled, showsWorking: prefs.islandShowsWorking)
            SettingsSection {
                SettingsToggleRow(title: "Show agent status at the notch", isOn: $prefs.islandEnabled)
                SettingsDivider()
                SettingsToggleRow(title: "Show while agents are working",
                                  subtitle: "Otherwise the island appears only when an agent needs you, finishes, or fails.",
                                  isOn: $prefs.islandShowsWorking)
                    .disabled(!prefs.islandEnabled)
            }
        }
    }
}
```

- [ ] **Step 5: Write the Alerts pane**

**File:** `Sources/AmbientApp/Settings/Panes/AlertsPane.swift`
```swift
import AmbientCore
import SwiftUI

struct AlertsPane: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let onPreviewSound: (Mood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .alerts)
            NotificationPreview(enabled: prefs.notificationsEnabled, chimesOn: prefs.soundsEnabled, onPlay: onPreviewSound)
            SettingsSection(header: "Notifications",
                            footer: "Ambient stays quiet while you're already in the app running the agent.") {
                SettingsRow(title: "Show notifications", subtitle: "When an agent needs you, finishes, or fails.") {
                    HStack(spacing: Theme.Space.sm) {
                        permission
                        Toggle("Show notifications", isOn: $prefs.notificationsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Announce finished turns longer than") {
                    Picker("Announce finished turns longer than", selection: $prefs.doneThreshold) {
                        Text("Always").tag(0.0)
                        Text("10 seconds").tag(10.0)
                        Text("20 seconds").tag(20.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(header: "Sound") {
                SettingsToggleRow(title: "Play chimes", isOn: $prefs.soundsEnabled)
                SettingsDivider()
                SettingsRow(title: "Volume") {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $prefs.soundVolume, in: 0...1) { editing in
                            if !editing { onPreviewSound(.done) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 180)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Volume")
                }
                .disabled(!prefs.soundsEnabled)
            }
        }
    }

    @ViewBuilder private var permission: some View {
        switch setup.notificationStatus {
        case .authorized, .provisional:
            StatusBadge("Allowed", .success)
        case .denied:
            Button("Open System Settings") { setup.requestNotifications() }.buttonStyle(.pill)
        default:
            Button("Allow") { setup.requestNotifications() }.buttonStyle(.pill)
        }
    }
}
```

- [ ] **Step 6: Write the Dock Glow pane**

**File:** `Sources/AmbientApp/Settings/Panes/DockPane.swift`
```swift
import SwiftUI

struct DockPane: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .dock)
            DockGlowPreview(enabled: prefs.dockGlowEnabled, intensity: prefs.dockGlowIntensity)
            SettingsSection {
                SettingsToggleRow(title: "Glow along the Dock", isOn: $prefs.dockGlowEnabled)
                SettingsDivider()
                Group {
                    SettingsRow(title: "Intensity") {
                        HStack(spacing: Theme.Space.xs) {
                            Image(systemName: "sun.min").foregroundStyle(.secondary)
                            Slider(value: $prefs.dockGlowIntensity, in: 0.3...1.5) { Text("Intensity") }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 180)
                            Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: "Light up behind the Dock's glass",
                                subtitle: "Needs Accessibility access to find the Dock. Without it, Ambient draws a light along the screen edge.") {
                        if setup.accessibilityTrusted {
                            StatusBadge("Enabled", .success)
                        } else {
                            Button("Enable…") { setup.requestAccessibility() }.buttonStyle(.pill)
                        }
                    }
                }
                .disabled(!prefs.dockGlowEnabled)
            }
        }
    }
}
```

- [ ] **Step 7: Write the General pane**

**File:** `Sources/AmbientApp/Settings/Panes/GeneralPane.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var setup: SetupModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .general)
            SettingsSection {
                SettingsToggleRow(title: "Open Ambient at login",
                                  subtitle: setup.loginItemNeedsApproval
                                      ? "Approve Ambient in System Settings › General › Login Items." : nil,
                                  subtitleStatus: .warning,
                                  isOn: Binding(get: { setup.launchAtLogin }, set: { setup.setLaunchAtLogin($0) }))
            }
            SettingsSection(header: "Command-line tool",
                            footer: "Try `ambient doctor` or `ambient status`. Add `~/.ambient/bin` to your PATH to use it anywhere.") {
                HStack(spacing: Theme.Space.sm) {
                    Text(cliPath)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: Theme.Space.sm)
                    Button(copied ? "Copied" : "Copy", action: copy).buttonStyle(.pill)
                }
                .settingsRowPadding()
            }
            SettingsSection(header: "About") {
                SettingsRow(title: "Version") {
                    Text(AmbientVersion.current).font(Theme.Fonts.row).foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(title: "Source code") {
                    Link("github.com/viveky259259/ambient",
                         destination: URL(string: "https://github.com/viveky259259/ambient")!)
                        .font(Theme.Fonts.row)
                }
                SettingsDivider()
                SettingsRow(title: "License") {
                    Text("MIT").font(Theme.Fonts.row).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cliPath: String {
        setup.paths.cliLink.path.replacingOccurrences(of: setup.paths.userHome.path, with: "~")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setup.paths.cliLink.path, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
```

- [ ] **Step 8: Write the window view**

**File:** `Sources/AmbientApp/Settings/SettingsView.swift`
```swift
import AmbientCore
import AppKit
import SwiftUI

/// The settings window: a floating glass sidebar and the selected pane.
struct SettingsView: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let firstRun: Bool
    let onDemo: () -> Void
    let onPreviewSound: (Mood) -> Void
    let onDone: () -> Void

    @AppStorage("settingsPane") private var pane: SettingsPane = .welcome
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: Theme.Layout.windowMinSize.width, maxWidth: .infinity,
               minHeight: Theme.Layout.windowMinSize.height, maxHeight: .infinity)
        .onAppear {
            if firstRun { pane = .welcome }
            sidebarFocused = true
            setup.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            setup.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { p in
                SidebarItem(title: p.title, symbol: p.symbol, selected: p == pane) { select(p) }
            }
            Spacer(minLength: 0)
        }
        // Below the traffic lights.
        .padding(.top, 44)
        .padding(.horizontal, Theme.Space.xs)
        .padding(.bottom, Theme.Space.sm)
        .frame(width: Theme.Layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .glassPanel()
        .padding(Theme.Space.xs)
        .focusable()
        .focused($sidebarFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                paneContent
            }
            .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, 40)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .id(pane)
        .transition(.opacity)
    }

    @ViewBuilder private var paneContent: some View {
        switch pane {
        case .welcome:
            WelcomePane(setup: setup, firstRun: firstRun, onDemo: onDemo, onGetStarted: onDone)
        case .agents:
            AgentsPane(setup: setup)
        case .island:
            IslandPane(prefs: prefs)
        case .alerts:
            AlertsPane(setup: setup, prefs: prefs, onPreviewSound: onPreviewSound)
        case .dock:
            DockPane(setup: setup, prefs: prefs)
        case .general:
            GeneralPane(setup: setup)
        }
    }

    private func select(_ p: SettingsPane) {
        withAnimation(.easeOut(duration: 0.18)) { pane = p }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let all = SettingsPane.allCases
        guard let i = all.firstIndex(of: pane) else { return .ignored }
        if all.indices.contains(i + delta) { select(all[i + delta]) }
        return .handled
    }
}
```

- [ ] **Step 9: Host it in `AppDelegate.showSetup` and delete `SetupView`**

Replace the window construction in `showSetup()` (the `let view = SetupView(...)` through `window.center()`) with:

```swift
            let view = SettingsView(setup: setup, prefs: prefs, firstRun: firstRun,
                                    onDemo: { [weak self] in self?.playDemo() },
                                    onPreviewSound: { [weak notifier] in notifier?.preview($0) },
                                    onDone: { [weak self] in
                                        self?.prefs.setupCompleted = true
                                        self?.setupWindow?.close()
                                        self?.askForNotificationsOnce()
                                    })
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ambient"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // An empty unified toolbar gives the title bar the height that seats the traffic lights
            // inside the floating sidebar.
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(Theme.Layout.windowSize)
            window.center()
```

Then: `git rm Sources/AmbientApp/Setup/SetupView.swift`

- [ ] **Step 10: Build and test**

Run: `swift build --product AmbientApp && swift test`
Expected: `Build complete!` and all AmbientCore tests pass.

- [ ] **Step 11: Commit**

```bash
git add -A Sources/AmbientApp
git commit -m "feat(app): Apple-style settings window with glass sidebar, six panes and live previews"
```

---

### Task 4: Run it and look at every pane

**Files:** whatever the fixes touch.

- [ ] **Step 1:** `scripts/build-app.sh --run` (replaces the running Ambient).
- [ ] **Step 2:** Open Settings (`open -a build/Ambient.app` again). Screenshot each pane in light and dark (System Settings › Appearance, or `defaults write -g AppleInterfaceStyle Dark` for the check, then restore). Check: traffic lights sit inside the sidebar's top; titles, cards and badges align; previews animate and follow their toggles; sliders change the Dock glow live; chimes play from the Alerts preview.
- [ ] **Step 3:** First run: `defaults write com.viveky259259.Ambient setupCompleted -bool false`, relaunch, confirm Welcome + **Get Started** closes the window, then confirm `setupCompleted` is back to `1`.
- [ ] **Step 4:** Fix what the screenshots show; rebuild; re-check.
- [ ] **Step 5:** Commit fixes: `git commit -am "fix(app): settings polish from visual review"`.
- [ ] **Step 6:** Quit the dev build and `open /Applications/Ambient.app`.

---

### Task 5: Docs

**Files:**
- Modify: `README.md:27-28`
- Modify: `CHANGELOG.md` (new `Unreleased` section at the top)

- [ ] **Step 1: README install steps**

```markdown
2. Open Ambient. Settings opens on **Welcome**: click **Connect All** to hook up every agent it found
   (or connect them one at a time under **Agents**).
3. Click **Play Demo** to see every state, then **Get Started**.
```

- [ ] **Step 2: CHANGELOG**

```markdown
## Unreleased

- **New settings window**: a floating glass sidebar with Welcome, Agents, Notch Island, Alerts, Dock Glow
  and General. Island, notification and Dock glow panes preview the real thing as you change settings.
- First run opens on a Welcome checklist: connect every agent at once, allow notifications, watch the demo.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: new settings window"
```
