import Foundation

/// Reads macOS's wallpaper store just enough to back it up and put it back safely. The format is
/// undocumented, so anything unexpected means "don't touch".
public enum WallpaperStore {
    public static func url(userHome: URL) -> URL {
        userHome.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// The provider of the wallpaper chosen for every Space and display, e.g. "com.apple.wallpaper.choice.color",
    /// when the store is in a format we know.
    public static func desktopProvider(of data: Data) -> String? {
        guard let root = propertyList(data) as? [String: Any],
              let all = root["AllSpacesAndDisplays"] as? [String: Any],
              let desktop = all["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let provider = choices.first?["Provider"] as? String else { return nil }
        return provider
    }

    public static func isKnownFormat(_ data: Data) -> Bool { desktopProvider(of: data) != nil }

    /// Whether two stores choose the same wallpapers everywhere, ignoring when each was last set or used.
    public static func matches(_ a: Data, _ b: Data) -> Bool {
        guard let x = propertyList(a).map(normalized) as? [String: Any],
              let y = propertyList(b).map(normalized) as? [String: Any] else { return false }
        return NSDictionary(dictionary: x).isEqual(to: y)
    }

    /// Whether any choice in the store points into `directory`, i.e. an image Ambient set is still the wallpaper.
    public static func references(directory: URL, in data: Data) -> Bool {
        guard let root = propertyList(data) else { return false }
        let path = directory.standardizedFileURL.path
        var encoded = directory.standardizedFileURL.absoluteString
        if encoded.hasSuffix("/") { encoded.removeLast() }
        return mentions(normalized(root)) { $0.contains(path) || $0.contains(encoded) }
    }

    private static let timestampKeys: Set<String> = ["LastSet", "LastUse"]

    /// Drops timestamps and opens nested property lists (choices keep their configuration as encoded data),
    /// so two stores compare by what they choose.
    private static func normalized(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in dict where !timestampKeys.contains(key) { out[key] = normalized(inner) }
            return out
        }
        if let array = value as? [Any] { return array.map(normalized) }
        if let data = value as? Data, !data.isEmpty, let inner = propertyList(data) { return normalized(inner) }
        return value
    }

    private static func mentions(_ value: Any, _ test: (String) -> Bool) -> Bool {
        if let s = value as? String { return test(s) }
        if let dict = value as? [String: Any] { return dict.values.contains { mentions($0, test) } }
        if let array = value as? [Any] { return array.contains { mentions($0, test) } }
        return false
    }

    private static func propertyList(_ data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}
