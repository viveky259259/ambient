import AmbientCore
import EventKit
import Foundation

/// Your next timed event later today, from macOS Calendar. Optional: without access there is none.
final class CalendarSource: ObservableObject {
    @Published private(set) var next: CalendarEvent?
    @Published private(set) var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    /// Access hasn't been asked for yet, so asking shows the system prompt.
    @Published private(set) var canAsk = EKEventStore.authorizationStatus(for: .event) == .notDetermined

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if next != nil { next = nil }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess != (status == .fullAccess) { hasAccess = status == .fullAccess }
        if canAsk != (status == .notDetermined) { canAsk = status == .notDetermined }
        guard running, hasAccess else {
            if next != nil { next = nil }
            return
        }
        let now = Date()
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil))
        let upcoming = events.filter { !$0.isAllDay && $0.startDate > now }.min { $0.startDate < $1.startDate }
        let found = upcoming.map { CalendarEvent(title: $0.title ?? "Event", start: $0.startDate) }
        if found != next { next = found }
    }
}
