import AmbientCore
import AppKit
import Combine

/// What the desktop pet shows, where things sit inside its panel, and the effects in flight.
/// Panel-local rects are SwiftUI's: origin top-left.
final class PetViewModel: ObservableObject {
    /// A burst of pixels from a click, in panel coordinates.
    struct Burst: Identifiable {
        let id: UInt64
        let origin: CGPoint
        let color: RGB
        let start: Date
        let particles: [PetBurst.Particle]
    }

    enum DragPhase { case changed, ended }

    @Published var sessions: [Session] = [] {
        didSet { primaryID = PetPolicy.primary(sessions, current: primaryID)?.id }
    }
    /// The session in the bubble, held steady while others of the same urgency churn.
    @Published private(set) var primaryID: String?
    @Published var species: PetSpecies = .blob
    /// Off while the pet is hidden, so nothing in its window keeps drawing or holding memory.
    @Published var visible = false
    /// Hovered: the full list with the island's actions.
    @Published var expanded = false
    /// Clicked: a compact look at every session, titles only, until clicked again.
    @Published var peekPinned = false
    @Published var quiet = false
    @Published var placement: PetLayout.Placement
    @Published private(set) var bursts: [Burst] = []
    /// The latest reaction, and a counter that replays it each time it changes.
    @Published private(set) var reaction: PetReaction = .hop
    @Published private(set) var reactionCount = 0

    var onOpen: (Session) -> Void = { _ in }
    var onAcknowledgeAll: () -> Void = {}
    var onToggleQuiet: () -> Void = {}
    var onSettings: () -> Void = {}
    var onHide: () -> Void = {}
    /// Opens the list without hovering, for VoiceOver.
    var onShowList: () -> Void = {}
    var onDrag: (DragPhase) -> Void = { _ in }
    /// A click on the pet, or VoiceOver's default action; the controller settles hover state, then calls `tapPet`.
    var onTap: () -> Void = {}

    /// Points per pixel of art.
    static let pixel: CGFloat = 4
    /// The pixel art's canvas.
    static let figureSize = CGSize(width: CGFloat(PetArt.canvasSize.width) * pixel, height: CGFloat(PetArt.canvasSize.height) * pixel)
    /// Under the pet, the row of session pips.
    static let pipStrip: CGFloat = 16
    /// The pet and its pips: what you click and drag. Room for the pips is kept even when there are none, so the
    /// pet never jumps when a second session starts.
    static let petSize = CGSize(width: figureSize.width, height: figureSize.height + pipStrip)
    /// The panel is big enough for the open list and never resizes; it ignores the mouse outside what it shows.
    static let panelSize = CGSize(width: 304, height: 430)
    static let bubbleSize = CGSize(width: 240, height: 46)
    static let listWidth: CGFloat = 292
    static let rowHeight: CGFloat = 44
    static let footerHeight: CGFloat = 34
    static let moreHeight: CGFloat = 20
    static let summaryHeight: CGFloat = 22
    static let peekWidth: CGFloat = 228
    static let peekRowHeight: CGFloat = 26
    static let tail: CGFloat = 6
    /// Between the pet and the bubble's tail below it. Above, the canvas's headroom for props is gap enough.
    static let gapBelow: CGFloat = 5

    private var nextBurst: UInt64 = 1

    init(placement: PetLayout.Placement) {
        self.placement = placement
    }

    var pose: PetPose { PetPolicy.pose(sessions) }
    var primary: Session? { primaryID.flatMap { id in sessions.first { $0.id == id } } }
    var badge: String? { PetPolicy.badge(sessions, primary: primaryID) }
    var waiting: Int { PetPolicy.waitingCount(sessions) }
    var listed: (shown: [Session], more: Int) { PetPolicy.listed(sessions) }
    var summary: String? { PetPolicy.summary(sessions) }
    var peek: (shown: [Session], more: Int) { PetPolicy.peek(sessions) }
    var pips: (shown: [Session], more: Int) { PetPolicy.pips(sessions) }

    /// The body takes the color of the agent it's acting out; grey while it sleeps.
    var tint: RGB { primary.map { Palette.agent($0.agent) } ?? Palette.idle }

    var opensUp: Bool { placement.opensUp }

    var petRect: CGRect {
        let size = Self.petSize
        return CGRect(x: placement.petInPanel.x, y: Self.panelSize.height - placement.petInPanel.y - size.height,
                      width: size.width, height: size.height)
    }

    /// The bubble or the list, tail included; nil when there's nothing to say.
    var contentRect: CGRect? {
        let size: CGSize
        if expanded {
            let list = listed
            let rows = CGFloat(max(1, list.shown.count))
            size = CGSize(width: Self.listWidth,
                          height: 12 + rows * Self.rowHeight + (list.more > 0 ? Self.moreHeight : 0)
                              + (summary != nil ? Self.summaryHeight : 0) + Self.footerHeight + Self.tail)
        } else if peekPinned {
            let p = peek
            let lines = CGFloat(max(1, p.shown.count)) * Self.peekRowHeight + (p.more > 0 ? Self.moreHeight : 0)
            size = CGSize(width: Self.peekWidth, height: 14 + lines + Self.tail)
        } else if primary != nil {
            size = CGSize(width: Self.bubbleSize.width, height: Self.bubbleSize.height + Self.tail)
        } else {
            return nil
        }
        let pet = petRect
        let midX = PetLayout.bubbleCenterX(petMidX: pet.midX, width: size.width, panelWidth: Self.panelSize.width)
        let y = opensUp ? pet.minY - size.height : pet.maxY + Self.gapBelow
        return CGRect(x: midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    /// Which content is showing; a change swaps one view for another.
    var contentKind: String {
        if expanded { return "list" }
        if peekPinned { return "peek" }
        return "bubble:\(primaryID ?? "")"
    }

    /// Where the tail points, from the content's leading edge.
    var tailX: CGFloat {
        guard let content = contentRect else { return 0 }
        return min(max(petRect.midX - content.minX, 18), content.width - 18)
    }

    // MARK: - Actions

    func tapPet() {
        let pose = self.pose
        react(PetPolicy.reaction(to: pose))
        let color = primary?.moodTint ?? tint
        burst(at: CGPoint(x: petRect.midX, y: petRect.minY + Self.figureSize.height - 26), color: color)
        expanded = false
        peekPinned.toggle()
    }

    /// Opens a session; a click bursts from where it landed, VoiceOver and keyboard opens don't.
    func tapSession(_ s: Session, at point: CGPoint?) {
        if let point { burst(at: point, color: s.tint) }
        onOpen(s)
    }

    func react(_ r: PetReaction) {
        reaction = r
        reactionCount += 1
    }

    func clearBursts() { bursts = [] }

    private func burst(at point: CGPoint, color: RGB) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let id = nextBurst
        nextBurst += 1
        bursts.append(Burst(id: id, origin: point, color: color, start: Date(), particles: PetBurst.particles(seed: id &* 2_654_435_761)))
        DispatchQueue.main.asyncAfter(deadline: .now() + PetBurst.lifetime + 0.05) { [weak self] in
            self?.bursts.removeAll { $0.id == id }
        }
    }
}
