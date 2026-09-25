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
