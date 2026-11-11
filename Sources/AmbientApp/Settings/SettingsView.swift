import AmbientCore
import AppKit
import SwiftUI

/// The settings window: a floating glass sidebar and the selected pane.
struct SettingsView: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    let remote: RemoteCoordinator
    let wallpaper: LivingWallpaper
    let speech: SpeechController
    let voicePack: VoicePackInstaller
    let shortcuts: ShortcutCenter
    let voiceSync: VoiceSyncController
    let voiceShortcuts: ShortcutCenter
    let speaker: SpeakerController
    let onDemo: () -> Void
    let onPreviewSound: (Mood) -> Void
    let onDone: () -> Void
    var onOpenBoard: (() -> Void)? = nil

    /// A raw value, which may name a pane from before the panes were grouped (`SettingsPane.moved`).
    @AppStorage("settingsPane") private var paneName = SettingsPane.welcome.rawValue
    @AppStorage("settingsTab.agents") private var agentsTab = AgentsTab.thisMac
    @AppStorage("settingsTab.appearance") private var appearanceTab = AppearanceTab.notch
    @AppStorage("settingsTab.voice") private var voiceTab = VoiceTab.readAloud
    @AppStorage("settingsTab.general") private var generalTab = GeneralTab.general
    @FocusState private var sidebarFocused: Bool

    /// Live, not captured: first run can end while the window is open.
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
            moveOldPane()
            if firstRun { paneName = SettingsPane.welcome.rawValue }
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
                SidebarItem(title: p.title, symbol: p.symbol, selected: p == current) { select(p) }
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
        .id(current)
        .transition(.opacity)
    }

    private var current: SettingsPane { SettingsPane(rawValue: paneName) ?? .welcome }

    /// A pane saved before the panes were grouped opens as the tab it became.
    private func moveOldPane() {
        guard SettingsPane(rawValue: paneName) == nil else { return }
        guard let (pane, tab) = SettingsPane.moved(from: paneName) else {
            paneName = SettingsPane.welcome.rawValue
            return
        }
        paneName = pane.rawValue
        switch pane {
        case .agents: agentsTab = AgentsTab(rawValue: tab) ?? agentsTab
        case .appearance: appearanceTab = AppearanceTab(rawValue: tab) ?? appearanceTab
        case .voice: voiceTab = VoiceTab(rawValue: tab) ?? voiceTab
        case .general: generalTab = GeneralTab(rawValue: tab) ?? generalTab
        default: break
        }
    }

    @ViewBuilder private var paneContent: some View {
        switch current {
        case .welcome:
            WelcomePane(setup: setup, firstRun: firstRun, onDemo: onDemo, onGetStarted: onDone)
        case .agents:
            TabbedPane(pane: .agents, selection: $agentsTab) { tab in
                switch tab {
                case .thisMac: AgentsPane(setup: setup)
                case .otherMachines: RemotePane(model: model, prefs: prefs, remote: remote)
                }
            }
        case .board:
            BoardPane(model: model, prefs: prefs, onOpenBoard: onOpenBoard)
        case .alerts:
            AlertsPane(setup: setup, prefs: prefs, onPreviewSound: onPreviewSound)
        case .appearance:
            TabbedPane(pane: .appearance, selection: $appearanceTab) { tab in
                switch tab {
                case .notch: IslandPane(prefs: prefs)
                case .pet: PetPane(prefs: prefs)
                case .dock: DockPane(setup: setup, prefs: prefs)
                case .wallpaper: WallpaperPane(prefs: prefs, wallpaper: wallpaper, calendar: wallpaper.calendar)
                }
            }
        case .voice:
            TabbedPane(pane: .voice, selection: $voiceTab) { tab in
                switch tab {
                case .readAloud: VoicePane(prefs: prefs, voicePack: voicePack, speech: speech, shortcuts: shortcuts)
                case .voiceSync: VoiceSyncPane(voice: voiceSync, prefs: prefs, shortcuts: voiceShortcuts)
                case .speaker: SpeakerPane(speaker: speaker, prefs: prefs, model: model)
                }
            }
        case .general:
            TabbedPane(pane: .general, tabs: GeneralTab.shown, selection: $generalTab) { tab in
                switch tab {
                case .general: GeneralPane(setup: setup)
                case .performance: PerformancePane(monitor: PerfMonitor.shared)
                }
            }
        }
    }

    private func select(_ p: SettingsPane) {
        withAnimation(.easeOut(duration: 0.18)) { paneName = p.rawValue }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let all = SettingsPane.allCases
        guard let i = all.firstIndex(of: current) else { return .ignored }
        if all.indices.contains(i + delta) { select(all[i + delta]) }
        return .handled
    }
}
