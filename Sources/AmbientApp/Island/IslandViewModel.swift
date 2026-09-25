import AmbientCore
import Combine
import SwiftUI

/// What the island is showing and how big it is.
final class IslandViewModel: ObservableObject {
    enum Presentation: Equatable {
        case hidden
        case collapsed
        /// Announcing a transition of one session.
        case bloom(String)
        /// Hovered: every session.
        case expanded
    }

    @Published var presentation: Presentation = .hidden
    @Published var sessions: [Session] = []
    @Published var geometry: IslandGeometry
    @Published var quiet = false

    var onOpen: (Session) -> Void = { _ in }
    var onAcknowledgeAll: () -> Void = {}
    var onToggleQuiet: () -> Void = {}
    var onSettings: () -> Void = {}

    static let wing: CGFloat = 42
    static let maxRows = 5

    init(geometry: IslandGeometry) {
        self.geometry = geometry
    }

    var primary: Session? { IslandPolicy.primary(sessions) }

    var bloomSession: Session? {
        guard case let .bloom(id) = presentation else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Sessions worth listing when expanded: everything but long-idle noise.
    var listed: [Session] { Array(sessions.prefix(Self.maxRows)) }

    func size(for p: Presentation) -> CGSize {
        let h = geometry.notchHeight
        let collapsed = geometry.notchWidth + 2 * Self.wing
        switch p {
        case .hidden: return CGSize(width: geometry.notchWidth, height: h)
        case .collapsed: return CGSize(width: collapsed, height: h)
        case .bloom: return CGSize(width: max(collapsed, 400), height: h + 74)
        case .expanded:
            let rows = CGFloat(max(1, listed.count))
            return CGSize(width: max(collapsed, 440), height: h + 12 + rows * 52 + 44)
        }
    }

    var currentSize: CGSize { size(for: presentation) }
}
