import Foundation

/// The public feature-request board on yaml.cafe. The app opens it in the browser and sends nothing itself.
public enum FeatureRequests {
    public static func url(version: String = AmbientVersion.current) -> URL {
        var parts = URLComponents(string: "https://yaml.cafe/requests/")!
        parts.queryItems = [URLQueryItem(name: "from", value: "app"), URLQueryItem(name: "v", value: version)]
        return parts.url!
    }

    public static let website = URL(string: "https://yaml.cafe/")!
}
