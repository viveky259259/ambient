import Foundation
import Testing
@testable import AmbientCore

private func plist(_ value: Any, _ format: PropertyListSerialization.PropertyListFormat = .binary) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
}

private func choice(_ provider: String, _ configuration: [String: Any]?,
                    format: PropertyListSerialization.PropertyListFormat = .binary) -> [String: Any] {
    ["Provider": provider, "Files": [Any](), "Configuration": configuration.map { plist($0, format) } ?? Data()]
}

private func entry(_ c: [String: Any], _ lastUse: Date) -> [String: Any] {
    ["Content": ["Choices": [c], "Shuffle": "$null", "EncodedOptionValues": "$null"], "LastSet": lastUse, "LastUse": lastUse]
}

/// A store shaped like macOS 27's: every Space and display, per display, per Space, and the system default.
private func store(desktop: [String: Any], idle: [String: Any], lastUse: Date = Date(timeIntervalSince1970: 1),
                   spaces: [String: Any] = [:]) -> Data {
    plist([
        "AllSpacesAndDisplays": ["Desktop": entry(desktop, lastUse), "Idle": entry(idle, lastUse), "Type": "individual"],
        "Displays": [String: Any](),
        "Spaces": spaces,
        "SystemDefault": ["Desktop": entry(desktop, lastUse)],
    ])
}

private var black: [String: Any] { choice("com.apple.wallpaper.choice.color", ["type": "systemColor", "systemColor": ["black": [String: Any]()]]) }
private var aerial: [String: Any] { choice("com.apple.wallpaper.choice.sequoia", nil) }

private func image(_ path: String) -> [String: Any] {
    choice("com.apple.wallpaper.choice.image", ["type": "imageFile", "url": ["relative": URL(fileURLWithPath: path).absoluteString]])
}

@Suite struct WallpaperStoreTests {
    @Test func readsTheDesktopChoice() {
        let data = store(desktop: black, idle: aerial)
        #expect(WallpaperStore.desktopProvider(of: data) == "com.apple.wallpaper.choice.color")
        #expect(WallpaperStore.isKnownFormat(data))
    }

    @Test func refusesFormatsItDoesntKnow() {
        #expect(!WallpaperStore.isKnownFormat(Data("nope".utf8)))
        #expect(!WallpaperStore.isKnownFormat(plist(["Something": "else"])))
        #expect(!WallpaperStore.isKnownFormat(plist(["AllSpacesAndDisplays": ["Desktop": ["Content": ["Choices": [Any]()]]]])))
    }

    @Test func matchingIgnoresWhenThingsWereLastUsed() {
        #expect(WallpaperStore.matches(store(desktop: black, idle: aerial, lastUse: Date(timeIntervalSince1970: 1)),
                                       store(desktop: black, idle: aerial, lastUse: Date(timeIntervalSince1970: 999))))
    }

    @Test func differentChoicesDontMatch() {
        let original = store(desktop: black, idle: aerial)
        #expect(!WallpaperStore.matches(original, store(desktop: image("/tmp/a.png"), idle: aerial)))
        #expect(!WallpaperStore.matches(original, store(desktop: black, idle: aerial,
                                                        spaces: ["S1": ["Default": entry(image("/tmp/a.png"), Date())]])))
        #expect(!WallpaperStore.matches(original, Data("nope".utf8)))
    }

    @Test func nestedConfigurationsCompareByContent() {
        let xmlBlack = choice("com.apple.wallpaper.choice.color",
                              ["type": "systemColor", "systemColor": ["black": [String: Any]()]], format: .xml)
        #expect(WallpaperStore.matches(store(desktop: black, idle: aerial), store(desktop: xmlBlack, idle: aerial)))
    }

    @Test func findsAmbientsImagesWhereverTheyAreSet() {
        let dir = URL(fileURLWithPath: "/Users/Jane Doe/.ambient/wallpaper", isDirectory: true)
        let swapped = store(desktop: black, idle: aerial,
                            spaces: ["S1": ["Default": entry(image("/Users/Jane Doe/.ambient/wallpaper/scene-1.png"), Date())]])
        #expect(WallpaperStore.references(directory: dir, in: swapped))
        #expect(!WallpaperStore.references(directory: dir, in: store(desktop: black, idle: aerial)))
        #expect(!WallpaperStore.references(directory: dir, in: store(desktop: image("/Users/Jane Doe/Pictures/cat.png"), idle: aerial)))
    }
}
