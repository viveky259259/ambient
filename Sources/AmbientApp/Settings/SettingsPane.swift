import SwiftUI

/// The panes of the settings window, in sidebar order. Panes that hold several parts show them as tabs.
enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, agents, board, alerts, appearance, voice, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .agents: "Agents"
        case .board: "Board"
        case .alerts: "Alerts"
        case .appearance: "Appearance"
        case .voice: "Voice & Sound"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .agents: "terminal"
        case .board: "rectangle.split.3x1"
        case .alerts: "bell.badge"
        case .appearance: "paintpalette"
        case .voice: "speaker.wave.2"
        case .general: "gearshape"
        }
    }

    /// For panes without tabs; a tabbed pane says what its selected tab is for instead.
    var subtitle: String? {
        switch self {
        case .board: "A local board of agent work, with optional on-device summaries."
        case .alerts: "Banners and chimes for the moments that need you."
        default: nil
        }
    }

    /// Where a pane from before the panes were grouped went, so the window opens where it was left.
    static func moved(from old: String) -> (pane: SettingsPane, tab: String)? {
        switch old {
        case "remote": (.agents, AgentsTab.otherMachines.rawValue)
        case "island": (.appearance, AppearanceTab.notch.rawValue)
        case "pet": (.appearance, AppearanceTab.pet.rawValue)
        case "dock": (.appearance, AppearanceTab.dock.rawValue)
        case "wallpaper": (.appearance, AppearanceTab.wallpaper.rawValue)
        case "voiceSync": (.voice, VoiceTab.voiceSync.rawValue)
        case "performance": (.general, GeneralTab.performance.rawValue)
        default: nil
        }
    }
}

/// One part of a tabbed pane.
protocol SettingsTab: RawRepresentable, CaseIterable, Hashable, Identifiable where RawValue == String {
    var title: String { get }
    /// What it's for, in a line.
    var subtitle: String { get }
}

extension SettingsTab {
    var id: String { rawValue }
}

enum AgentsTab: String, SettingsTab {
    case thisMac, otherMachines

    var title: String {
        switch self {
        case .thisMac: "This Mac"
        case .otherMachines: "Other Machines"
        }
    }

    var subtitle: String {
        switch self {
        case .thisMac: "Ambient listens to your agents through lightweight hooks."
        case .otherMachines: "Agents on your other machines, over your own ssh. No accounts, relays or open ports."
        }
    }
}

enum AppearanceTab: String, SettingsTab {
    case notch, pet, dock, wallpaper

    var title: String {
        switch self {
        case .notch: "Notch"
        case .pet: "Pet"
        case .dock: "Dock"
        case .wallpaper: "Wallpaper"
        }
    }

    var subtitle: String {
        switch self {
        case .notch: "A quiet status light at the top of the screen, around the notch if there is one."
        case .pet: "A companion on your desktop that acts out what your agents are doing."
        case .dock: "Light along the Dock in the color of what your agents are doing."
        case .wallpaper: "A living world on your desktop and lock screen, where your agents live."
        }
    }
}

enum VoiceTab: String, SettingsTab {
    case readAloud, voiceSync, speaker

    var title: String {
        switch self {
        case .readAloud: "Read Aloud"
        case .voiceSync: "Voice Sync"
        case .speaker: "Ambient Speaker"
        }
    }

    var subtitle: String {
        switch self {
        case .readAloud: "Select text, press the shortcut, and Ambient reads it aloud."
        case .voiceSync: "Talk on one Mac and paste on another. The voice streams there as you speak."
        case .speaker: "Hear this Mac's sound on another Mac, in step with video here."
        }
    }
}

/// Performance is a developer tool, so the tabs show only in dev builds.
enum GeneralTab: String, SettingsTab {
    case general, performance

    static var shown: [GeneralTab] { PerfMonitor.isAvailable ? allCases : [.general] }

    var title: String {
        switch self {
        case .general: "General"
        case .performance: "Performance"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup, the command-line tool, and version."
        case .performance: "What Ambient costs your Mac, measured on your Mac. Nothing is sent anywhere."
        }
    }
}

/// A pane's large title and one-line description.
struct PaneHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    init(pane: SettingsPane) {
        self.init(title: pane.title, subtitle: pane.subtitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.Fonts.paneTitle)
            if let subtitle {
                Text(subtitle).font(Theme.Fonts.paneSubtitle).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A pane of several parts: its title, the tabs, what the selected one is for, and the selected one.
struct TabbedPane<Tab: SettingsTab, Content: View>: View {
    let pane: SettingsPane
    var tabs: [Tab] = Array(Tab.allCases)
    @Binding var selection: Tab
    @ViewBuilder var content: (Tab) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if tabs.count > 1 {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(pane.title)
                        .font(Theme.Fonts.paneTitle)
                        .accessibilityAddTraits(.isHeader)
                    Picker(pane.title, selection: $selection) {
                        ForEach(tabs) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Text(selection.subtitle)
                        .font(Theme.Fonts.paneSubtitle)
                        .foregroundStyle(.secondary)
                }
            } else {
                PaneHeader(title: pane.title, subtitle: selection.subtitle)
            }
            content(tabs.contains(selection) ? selection : tabs[0])
                .id(selection)
        }
    }
}
