import AmbientCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var prefs: Preferences
    let firstRun: Bool
    let onDemo: () -> Void
    let onPreviewSound: (Mood) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                agentsSection
                islandSection
                alertsSection
                dockSection
                generalSection
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 600, height: 700)
        .onAppear { setup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(firstRun ? "Welcome to Ambient" : "Ambient").font(.title2.weight(.semibold))
                Text("Your desktop quietly shows what your coding agents are doing — and lights up when they need you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack {
            Button("Play Demo", action: onDemo)
            Text("Watch the notch, the Dock and the menu bar.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(firstRun ? "Get Started" : "Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Sections

    private var agentsSection: some View {
        Section {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                AgentRow(agent: agent, state: setup.agentStates[agent] ?? .notInstalled, error: setup.agentErrors[agent],
                         path: setup.installer.configURL(agent).path.replacingOccurrences(of: setup.paths.userHome.path, with: "~"),
                         install: { setup.install(agent) }, uninstall: { setup.uninstall(agent) })
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Ambient adds background hooks that never slow your agent down, keeps a backup of every file it edits, and removes only its own entries.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var islandSection: some View {
        Section("Notch island") {
            Toggle("Show agent status at the notch", isOn: $prefs.islandEnabled)
            Toggle("Show while agents are working", isOn: $prefs.islandShowsWorking)
                .disabled(!prefs.islandEnabled)
        }
    }

    private var alertsSection: some View {
        Section("Notifications & sound") {
            HStack {
                Toggle("Notifications", isOn: $prefs.notificationsEnabled)
                Spacer()
                notificationBadge
            }
            HStack {
                Toggle("Chimes", isOn: $prefs.soundsEnabled)
                Spacer()
                ForEach([(Mood.waiting, "Needs you"), (.done, "Done"), (.error, "Error")], id: \.0) { mood, label in
                    Button(label) { onPreviewSound(mood) }.controlSize(.small)
                }
            }
            Slider(value: $prefs.soundVolume, in: 0...1) { Text("Volume") }
                .disabled(!prefs.soundsEnabled)
            Picker("Announce finished turns longer than", selection: $prefs.doneThreshold) {
                Text("Always").tag(0.0)
                Text("10 seconds").tag(10.0)
                Text("20 seconds").tag(20.0)
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
            }
            Text("Ambient stays quiet while you're already in the app running the agent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var notificationBadge: some View {
        switch setup.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .denied:
            Button("Open System Settings") { setup.requestNotifications() }.controlSize(.small)
        default:
            Button("Allow Notifications") { setup.requestNotifications() }.controlSize(.small)
        }
    }

    private var dockSection: some View {
        Section {
            Toggle("Glow along the Dock", isOn: $prefs.dockGlowEnabled)
            Slider(value: $prefs.dockGlowIntensity, in: 0.3...1.5) { Text("Intensity") }
                .disabled(!prefs.dockGlowEnabled)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Light up behind the Dock's glass")
                    Text("Needs Accessibility access to find the Dock. Without it, Ambient draws a light along the screen edge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if setup.accessibilityTrusted {
                    Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                } else {
                    Button("Enable…") { setup.requestAccessibility() }.controlSize(.small)
                }
            }
            .disabled(!prefs.dockGlowEnabled)
        } header: {
            Text("Dock glow")
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Open Ambient at login", isOn: Binding(get: { setup.launchAtLogin }, set: { setup.setLaunchAtLogin($0) }))
            if setup.loginItemNeedsApproval {
                Text("Approve Ambient in System Settings › General › Login Items.").font(.caption).foregroundStyle(.orange)
            }
            LabeledContent("Command-line tool") {
                Text(setup.paths.cliLink.path.replacingOccurrences(of: setup.paths.userHome.path, with: "~"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text("Try `ambient doctor` or `ambient status`. Add ~/.ambient/bin to your PATH to use it anywhere.")
                .font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(Palette.agent(agent).color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(path).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                status
                actions
            }
            if agent == .codex, state == .installed {
                Text("Codex runs new hooks only after you approve them: type /hooks in Codex once.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        switch agent {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .installed: Text("Connected").font(.caption).foregroundStyle(.green)
        case .partial: Text("Needs update").font(.caption).foregroundStyle(.orange)
        case .notInstalled: Text("Not connected").font(.caption).foregroundStyle(.secondary)
        case .agentMissing: Text("Not found").font(.caption).foregroundStyle(.secondary)
        case .unreadable: Text("Config unreadable").font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .installed:
            Button("Remove", action: uninstall).controlSize(.small)
        case .partial:
            Button("Update", action: install).controlSize(.small)
        case .notInstalled:
            Button("Connect", action: install).controlSize(.small).buttonStyle(.borderedProminent)
        case .agentMissing, .unreadable:
            EmptyView()
        }
    }
}
