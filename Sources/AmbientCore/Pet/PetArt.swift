import Foundation

public struct PixelPoint: Equatable, Sendable, CustomStringConvertible {
    public let x, y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "(\(x), \(y))" }
}

public struct PixelSize: Equatable, Sendable {
    public let width, height: Int
}

/// A small picture as rows of color keys; "." is transparent.
///
/// Keys: `o` outline, `b` body, `s` body shade, `h` body highlight, `w` white, `e` eye, `k` eye glint,
/// `g` screen glow, `a` amber, `G` green, `c` cyan, `z` the sleeping "z".
public struct PixelSprite: Equatable, Sendable {
    public let rows: [String]
    private let grid: [[Character]]

    public init(_ rows: [String]) {
        self.rows = rows
        grid = rows.map(Array.init)
    }

    public var width: Int { grid.first?.count ?? 0 }
    public var height: Int { grid.count }

    /// The color key at a pixel, or nil where it's transparent or outside the sprite.
    public func pixel(x: Int, y: Int) -> Character? {
        guard grid.indices.contains(y), grid[y].indices.contains(x), grid[y][x] != "." else { return nil }
        return grid[y][x]
    }
}

public enum PetSpecies: String, CaseIterable, Sendable {
    case blob, crab, cat

    /// The stored choice, or the blob when it's missing or from a newer version.
    public init(stored: String?) {
        self = stored.flatMap(PetSpecies.init(rawValue:)) ?? .blob
    }

    public var displayName: String {
        switch self {
        case .blob: "Blob"
        case .crab: "Crab"
        case .cat: "Cat"
        }
    }
}

public enum PetExpression: CaseIterable, Sendable {
    case open, closed, happy, wide, dizzy
}

public enum PetProp: CaseIterable, Sendable {
    case laptop, bang, sparkle, sparkleSmall, sweat, z, zSmall
}

/// One frame of a species: its body and where its two 2×2 eyes go.
public struct PetFrame: Sendable {
    public let body: PixelSprite
    public let eyes: [PixelPoint]

    /// Where a 4×2 mouth goes: centered under the eyes, a row below them.
    public var mouth: PixelPoint {
        PixelPoint((eyes[0].x + eyes[1].x + 2) / 2 - 2, eyes[0].y + 2)
    }
}

public struct PlacedProp: Sendable {
    public let sprite: PixelSprite
    public let at: PixelPoint

    init(prop: PetProp, at: PixelPoint) {
        sprite = PetArt.prop(prop)
        self.at = at
    }

    init(sprite: PixelSprite, at: PixelPoint) {
        self.sprite = sprite
        self.at = at
    }
}

/// The pet's pixel art. A body sits in a larger canvas that leaves room for props around it.
public enum PetArt {
    public static let bodySize = PixelSize(width: 16, height: 13)
    public static let canvasSize = PixelSize(width: 20, height: 18)
    /// Where the body's top-left pixel sits in the canvas.
    public static let bodyOrigin = PixelPoint(2, 5)

    /// Two frames per species, which poses alternate between.
    public static func frames(_ species: PetSpecies) -> [PetFrame] {
        switch species {
        case .blob: blob
        case .crab: crab
        case .cat: cat
        }
    }

    public static func expression(for pose: PetPose) -> PetExpression {
        switch pose {
        case .sleeping: .closed
        case .working: .open
        case .waiting: .wide
        case .done: .happy
        case .error: .dizzy
        }
    }

    public static func eye(_ expression: PetExpression) -> PixelSprite {
        switch expression {
        case .open: PixelSprite(["ke", "ee"])
        case .closed: PixelSprite(["..", "ee"])
        case .happy: PixelSprite(["ee", ".."])
        case .wide: PixelSprite(["ee", "ee"])
        case .dizzy: PixelSprite(["e.", ".e"])
        }
    }

    /// A mouth for the poses that have one: a smile when done, a frown when failed, an "o" when it needs you.
    public static func mouth(for pose: PetPose) -> PixelSprite? {
        switch pose {
        case .sleeping, .working: nil
        case .waiting: PixelSprite([".ee.", ".ee."])
        case .done: PixelSprite(["e..e", ".ee."])
        case .error: PixelSprite([".ee.", "e..e"])
        }
    }

    /// The props around the pet in a pose, in canvas coordinates. With several sessions waiting, their count
    /// stands where the "!" would, and holds still so it can be read.
    public static func props(for pose: PetPose, frame: Int, waiting: Int = 1) -> [PlacedProp] {
        let even = frame % 2 == 0
        switch pose {
        case .sleeping:
            return even ? [PlacedProp(prop: .z, at: PixelPoint(15, 1))]
                : [PlacedProp(prop: .zSmall, at: PixelPoint(17, 0)), PlacedProp(prop: .z, at: PixelPoint(14, 2))]
        case .working:
            return [PlacedProp(prop: .laptop, at: PixelPoint(4, 14))]
        case .waiting:
            if waiting >= 2 { return [PlacedProp(sprite: digit(waiting), at: PixelPoint(16, 0))] }
            return even ? [PlacedProp(prop: .bang, at: PixelPoint(17, 0))] : []
        case .done:
            return even
                ? [PlacedProp(prop: .sparkle, at: PixelPoint(0, 0)), PlacedProp(prop: .sparkleSmall, at: PixelPoint(16, 3))]
                : [PlacedProp(prop: .sparkle, at: PixelPoint(15, 0)), PlacedProp(prop: .sparkleSmall, at: PixelPoint(1, 4))]
        case .error:
            return [PlacedProp(prop: .sweat, at: PixelPoint(16, even ? 4 : 6))]
        }
    }

    /// A 3×5 amber digit, 2 to 9; larger counts show 9.
    public static func digit(_ n: Int) -> PixelSprite {
        switch min(max(n, 2), 9) {
        case 2: PixelSprite(["aaa", "..a", "aaa", "a..", "aaa"])
        case 3: PixelSprite(["aaa", "..a", ".aa", "..a", "aaa"])
        case 4: PixelSprite(["a.a", "a.a", "aaa", "..a", "..a"])
        case 5: PixelSprite(["aaa", "a..", "aaa", "..a", "aaa"])
        case 6: PixelSprite(["aaa", "a..", "aaa", "a.a", "aaa"])
        case 7: PixelSprite(["aaa", "..a", "..a", ".a.", ".a."])
        case 8: PixelSprite(["aaa", "a.a", "aaa", "a.a", "aaa"])
        default: PixelSprite(["aaa", "a.a", "aaa", "..a", "aaa"])
        }
    }

    public static func prop(_ prop: PetProp) -> PixelSprite {
        switch prop {
        // The back of an open laptop's lid, its logo glowing.
        case .laptop: PixelSprite(["oooooooooooo", "owwwwggwwwwo", "owwwwwwwwwwo", "oooooooooooo"])
        case .bang: PixelSprite(["aa", "aa", "aa", "aa", "..", "aa"])
        case .sparkle: PixelSprite(["..w..", "..w..", "wwGww", "..w..", "..w.."])
        case .sparkleSmall: PixelSprite([".w.", "wGw", ".w."])
        case .sweat: PixelSprite([".c.", "ccc", "cwc", ".c."])
        case .z: PixelSprite(["zzzz", "..z.", ".z..", "zzzz"])
        case .zSmall: PixelSprite(["zzz", ".z.", "zzz"])
        }
    }

    // MARK: - Species

    private static let blob = [
        PetFrame(body: PixelSprite([
            "................",
            "......oooo......",
            "....oohhbboo....",
            "...ohhbbbbbbo...",
            "..ohbbbbbbbbbo..",
            "..obbbbbbbbbbo..",
            ".obbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            ".osbbbbbbbbbbso.",
            ".ossbbbbbbbbsso.",
            "..osssssssssso..",
            "...oooooooooo...",
        ]), eyes: [PixelPoint(5, 6), PixelPoint(9, 6)]),
        // Squashed: the bounce.
        PetFrame(body: PixelSprite([
            "................",
            "................",
            ".....oooooo.....",
            "...oohhbbbboo...",
            "..ohhbbbbbbbbo..",
            ".ohbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "osbbbbbbbbbbbbso",
            "ossbbbbbbbbbbsso",
            ".osssssssssssso.",
            "..oooooooooooo..",
        ]), eyes: [PixelPoint(5, 7), PixelPoint(9, 7)]),
    ]

    private static let crab = [
        PetFrame(body: PixelSprite([
            ".oo..........oo.",
            "obbo........obbo",
            "obbo........obbo",
            ".obo........obo.",
            "..o..oooooo..o..",
            "..o.obbbbbbo.o..",
            "..oobbbbbbbboo..",
            "...obhbbbbbbo...",
            "..obbbbbbbbbbo..",
            "..osbbbbbbbbso..",
            "...osssssssso...",
            "...o.o.oo.o.o...",
            "..o..o....o..o..",
        ]), eyes: [PixelPoint(5, 7), PixelPoint(9, 7)]),
        // Pincers open, legs mid-step.
        PetFrame(body: PixelSprite([
            "obo..........obo",
            "o.bo........ob.o",
            "obbo........obbo",
            ".obo........obo.",
            "..o..oooooo..o..",
            "..o.obbbbbbo.o..",
            "..oobbbbbbbboo..",
            "...obhbbbbbbo...",
            "..obbbbbbbbbbo..",
            "..osbbbbbbbbso..",
            "...osssssssso...",
            "..o.o.o..o.o.o..",
            "................",
        ]), eyes: [PixelPoint(5, 7), PixelPoint(9, 7)]),
    ]

    private static let cat = [
        // Tail curled up.
        PetFrame(body: PixelSprite([
            "..o..........o..",
            ".obo........obo.",
            ".obbo......obbo.",
            ".obbboooooobbbo.",
            ".obbbbbbbbbbbbo.",
            ".ohbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            ".obbbbbwwbbbbbo.",
            "..obbbbwwbbbbo..",
            "..osbbbbbbbbso.o",
            "..obbbbbbbbbbo.o",
            "..obsbbbbbbsbooo",
            "...oo.oooo.oo...",
        ]), eyes: [PixelPoint(4, 5), PixelPoint(10, 5)]),
        // Tail down.
        PetFrame(body: PixelSprite([
            "..o..........o..",
            ".obo........obo.",
            ".obbo......obbo.",
            ".obbboooooobbbo.",
            ".obbbbbbbbbbbbo.",
            ".ohbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            ".obbbbbwwbbbbbo.",
            "..obbbbwwbbbbo..",
            "..osbbbbbbbbso..",
            "..obbbbbbbbbbo..",
            "..obsbbbbbbsbooo",
            "...oo.oooo.oo...",
        ]), eyes: [PixelPoint(4, 5), PixelPoint(10, 5)]),
    ]
}
