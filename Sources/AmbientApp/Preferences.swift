import AmbientCore
import Combine
import Foundation

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    @Published var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: "islandEnabled") } }
    @Published var islandShowsWorking: Bool { didSet { defaults.set(islandShowsWorking, forKey: "islandShowsWorking") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "soundVolume") } }
    @Published var dockGlowEnabled: Bool { didSet { defaults.set(dockGlowEnabled, forKey: "dockGlowEnabled") } }
    @Published var dockGlowIntensity: Double { didSet { defaults.set(dockGlowIntensity, forKey: "dockGlowIntensity") } }
    /// Seconds a turn must run before finishing it notifies.
    @Published var doneThreshold: Double { didSet { defaults.set(doneThreshold, forKey: "doneThreshold") } }
    @Published var quietUntil: Date? { didSet { defaults.set(quietUntil, forKey: "quietUntil") } }
    @Published var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: "setupCompleted") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "islandEnabled": true,
            "islandShowsWorking": true,
            "notificationsEnabled": true,
            "soundsEnabled": true,
            "soundVolume": 0.6,
            "dockGlowEnabled": true,
            "dockGlowIntensity": 1.0,
            "doneThreshold": 20.0,
            "setupCompleted": false,
        ])
        islandEnabled = defaults.bool(forKey: "islandEnabled")
        islandShowsWorking = defaults.bool(forKey: "islandShowsWorking")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        soundsEnabled = defaults.bool(forKey: "soundsEnabled")
        soundVolume = defaults.double(forKey: "soundVolume")
        dockGlowEnabled = defaults.bool(forKey: "dockGlowEnabled")
        dockGlowIntensity = defaults.double(forKey: "dockGlowIntensity")
        doneThreshold = defaults.double(forKey: "doneThreshold")
        quietUntil = defaults.object(forKey: "quietUntil") as? Date
        setupCompleted = defaults.bool(forKey: "setupCompleted")
    }

    var isQuiet: Bool {
        guard let quietUntil else { return false }
        return quietUntil > Date()
    }

    var alertSettings: AlertPolicy.Settings {
        AlertPolicy.Settings(notifications: notificationsEnabled, sounds: soundsEnabled,
                             doneThreshold: doneThreshold, quiet: isQuiet)
    }
}
