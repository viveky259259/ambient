import AppKit

/// The private SkyLight calls that put a window above the lock screen, resolved at runtime: a macOS
/// without them means no live lock screen, never a crash. Proven on macOS 27 in the 2026-09-29 spike.
final class SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Nil when this macOS doesn't have the calls.
    static let shared = SkyLight()

    /// Above the lock screen. Level 100 is not.
    static let lockScreenLevel: Int32 = 400

    private let mainConnection: MainConnectionID
    private let spaceCreate: SpaceCreate
    private let setLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowSpaces
    private let addWindows: SpaceAddWindows

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(handle, name).map { unsafeBitCast($0, to: T.self) } }
        guard let main = symbol("SLSMainConnectionID", MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", SpaceCreate.self),
              let level = symbol("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", ShowSpaces.self),
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddWindows.self) else { return nil }
        mainConnection = main
        spaceCreate = create
        setLevel = level
        showSpaces = show
        addWindows = add
    }

    /// A space above the lock screen, shown. Nil if SkyLight refused one.
    func makeLockScreenSpace() -> Int32? {
        let cid = mainConnection()
        let space = spaceCreate(cid, 1, 0)
        guard space != 0 else { return nil }
        _ = setLevel(cid, space, Self.lockScreenLevel)
        _ = showSpaces(cid, [space] as CFArray)
        return space
    }

    func move(_ window: NSWindow, to space: Int32) {
        _ = addWindows(mainConnection(), space, [window.windowNumber] as CFArray, 7)
    }
}
