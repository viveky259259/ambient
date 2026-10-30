import AmbientCore
import Foundation

/// Keeps the permission hook of connected agents in step with Settings › Island: in the foreground while the
/// island answers prompts, in the background otherwise. Agents that aren't connected are left alone.
enum PermissionHooks {
    /// Returns what went wrong, if anything, for the settings pane to show.
    @discardableResult
    static func apply(_ settings: PermissionSettings, paths: AmbientPaths = .current()) -> String? {
        let installer = HookInstaller(paths: paths, permissions: settings)
        var problems: [String] = []
        for agent in PermissionReply.agents.sorted(by: { $0.rawValue < $1.rawValue }) where installer.status(agent) == .partial {
            do { try installer.install(agent) } catch { problems.append("\(agent.displayName): \(error)") }
        }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
}
