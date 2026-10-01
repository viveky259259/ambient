import SwiftUI

/// The panes of the settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, agents, island, alerts, dock, wallpaper, performance, general

    var id: String { rawValue }

    /// The panes in the sidebar. Performance is a developer tool, only in dev builds.
    static var shown: [SettingsPane] { allCases.filter { $0 != .performance || PerfMonitor.isAvailable } }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .agents: "Agents"
        case .island: "Notch Island"
        case .alerts: "Alerts"
        case .dock: "Dock Glow"
        case .wallpaper: "Wallpaper"
        case .performance: "Performance"
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
        case .wallpaper: "photo.artframe"
        case .performance: "gauge.with.dots.needle.33percent"
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
        case .wallpaper: "A living world on your desktop and lock screen, where your agents live."
        case .performance: "What Ambient costs your Mac, measured on your Mac. Nothing is sent anywhere."
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
