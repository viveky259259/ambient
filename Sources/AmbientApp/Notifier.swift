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
        let agent = s.agent.displayName
        switch s.activity {
        case let .waiting(reason, message):
            content.title = reason == "permission" ? "\(title) needs your permission" : "\(title) has a question"
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
        content.subtitle = [agent, Describe.place(s), HostActivator.appName(for: s.host)].compactMap { $0 }.joined(separator: " · ")
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
            if let self, let id, let session = self.model.sessions.first(where: { $0.id == id }) {
                self.model.open(session)
            }
            completionHandler()
        }
    }
}
