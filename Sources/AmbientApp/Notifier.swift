import AmbientCore
import AppKit
import Combine
import UserNotifications

/// Notifications and sounds for moments that need the user; withdraws them once resolved.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let model: AppModel
    private let prefs: Preferences
    private let chimes = Chimes()
    private var cancellables: Set<AnyCancellable> = []
    /// Nil when running outside an app bundle (e.g. `swift run`), where notifications are unavailable.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()

    init(model: AppModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
    }

    func start() {
        center?.delegate = self
        model.transitions
            .sink { [weak self] t in self?.handle(t) }
            .store(in: &cancellables)
        model.openedFromElsewhere
            .sink { [weak self] opened in self?.postOpened(opened.session, from: opened.from) }
            .store(in: &cancellables)
    }

    /// Says why a chat just came forward: another Mac's board opened it. No sound; nothing needs answering.
    private func postOpened(_ s: Session, from: String) {
        guard let center, prefs.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Opened from \(from)"
        content.body = Describe.title(s)
        content.subtitle = [s.agentLabel, HostActivator.appName(for: s.host)].compactMap { $0 }.joined(separator: " · ")
        content.threadIdentifier = "opened"
        content.userInfo = ["session": s.id]
        content.interruptionLevel = .active
        center.add(UNNotificationRequest(identifier: "opened:\(s.id)", content: content, trigger: nil))
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let center else { return completion(false) }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard let center else { return completion(.denied) }
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    func preview(_ mood: Mood) {
        chimes.play(mood, volume: prefs.soundVolume)
    }

    private func handle(_ t: SessionChange) {
        let s = t.session
        // A resolved prompt or a seen result shouldn't linger in Notification Center.
        if t.removed || s.activity.isBusy || s.acknowledged || s.mood == .idle {
            center?.removeDeliveredNotifications(withIdentifiers: [s.id])
        }
        guard let alert = AlertPolicy.decide(t, settings: prefs.alertSettings, hostIsFrontmost: HostActivator.isFrontmost(s.host))
        else { return }
        if alert.sound { chimes.play(alert.mood, volume: prefs.soundVolume) }
        if alert.notify { post(alert.mood, for: s) }
    }

    private func post(_ mood: Mood, for s: Session) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let title = Describe.title(s)
        let agent = s.agentLabel
        switch s.activity {
        case let .waiting(reason, message):
            // "api-server needs you to approve a command", then the command itself.
            let headline = Need(reason: reason).headline
            content.title = "\(title) needs you to \(headline.prefix(1).lowercased() + headline.dropFirst())"
            content.body = message ?? "\(agent) is waiting for you."
        case let .done(summary):
            content.title = "\(title) is done"
            let took = s.turnDuration.map { " in \(Describe.duration($0))" } ?? ""
            content.body = summary ?? "\(agent) finished\(took)."
        case let .error(message):
            content.title = "\(title) stopped with an error"
            content.body = message ?? "\(agent) couldn't finish the turn."
        default:
            return
        }
        content.subtitle = [agent, Describe.machine(s), Describe.place(s), HostActivator.appName(for: s.host)].compactMap { $0 }.joined(separator: " · ")
        content.threadIdentifier = s.id
        content.userInfo = ["session": s.id]
        content.interruptionLevel = .active
        // One notification per session: a newer state replaces the older one.
        center.add(UNNotificationRequest(identifier: s.id, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String
        DispatchQueue.main.async { [weak self] in
            if let self, let id {
                // A chat whose session has ended still opens, from the task that remembers it.
                if let session = self.model.sessions.first(where: { $0.id == id }) {
                    self.model.open(session)
                } else {
                    _ = self.model.openEndedChat(sessionID: id)
                }
            }
            completionHandler()
        }
    }
}
