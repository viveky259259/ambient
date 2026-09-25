import AmbientCore
import AppKit
import ServiceManagement
import UserNotifications

/// Live status for the setup window: hooks, permissions, login item.
final class SetupModel: ObservableObject {
    @Published var agentStates: [AgentKind: InstallState] = [:]
    @Published var agentErrors: [AgentKind: String] = [:]
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted = DockLocator.isTrusted
    @Published var launchAtLogin = false
    @Published var loginItemNeedsApproval = false

    let installer: HookInstaller
    let paths: AmbientPaths
    private let notifier: Notifier

    init(paths: AmbientPaths, notifier: Notifier) {
        self.paths = paths
        self.installer = HookInstaller(paths: paths)
        self.notifier = notifier
    }

    func refresh() {
        for agent in AgentKind.allCases { agentStates[agent] = installer.status(agent) }
        accessibilityTrusted = DockLocator.isTrusted
        notifier.authorizationStatus { [weak self] in self?.notificationStatus = $0 }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginItemNeedsApproval = status == .requiresApproval
    }

    func install(_ agent: AgentKind) {
        do {
            try installer.install(agent)
            agentErrors[agent] = nil
        } catch {
            agentErrors[agent] = String(describing: error)
        }
        refresh()
    }

    func uninstall(_ agent: AgentKind) {
        do {
            try installer.uninstall(agent)
            agentErrors[agent] = nil
        } catch {
            agentErrors[agent] = String(describing: error)
        }
        refresh()
    }

    func requestNotifications() {
        if notificationStatus == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            return
        }
        notifier.requestAuthorization { [weak self] _ in self?.refresh() }
    }

    func requestAccessibility() {
        DockLocator.requestAccess()
        // The grant happens in System Settings; check back for a while.
        var checks = 0
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            checks += 1
            self?.accessibilityTrusted = DockLocator.isTrusted
            if DockLocator.isTrusted || checks > 60 { timer.invalidate() }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Ambient: login item change failed: \(error)")
        }
        refresh()
    }
}
