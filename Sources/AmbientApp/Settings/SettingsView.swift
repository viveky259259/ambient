import AmbientCore
import AppKit
import SwiftUI

/// The settings window: a floating glass sidebar and the selected pane.
struct SettingsView: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let wallpaper: LivingWallpaper
    let onDemo: () -> Void
    let onPreviewSound: (Mood) -> Void
    let onDone: () -> Void

    @AppStorage("settingsPane") private var pane: SettingsPane = .welcome
    @FocusState private var sidebarFocused: Bool

    /// Live, not captured: the window outlives first run and is reused when Settings opens again.
    private var firstRun: Bool { !prefs.setupCompleted }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: Theme.Layout.windowMinSize.width, maxWidth: Theme.Layout.windowMaxWidth,
               minHeight: Theme.Layout.windowMinSize.height, maxHeight: .infinity)
        // Up under the transparent title bar, so the traffic lights sit on the sidebar.
        .ignoresSafeArea(.container, edges: .top)
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
        case .wallpaper:
            WallpaperPane(prefs: prefs, wallpaper: wallpaper, calendar: wallpaper.calendar)
        case .performance:
            PerformancePane(monitor: PerfMonitor.shared)
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
