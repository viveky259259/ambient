@testable import AmbientApp
@testable import AmbientCore
import Foundation
import Testing

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func placement(at pet: CGPoint) -> PetLayout.Placement {
    PetLayout.place(pet: pet, petSize: PetViewModel.petSize, panel: PetViewModel.panelSize, in: screen)
}

@MainActor @Suite struct PetViewModelTests {
    @Test func nothingToSayWithoutSessions() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        #expect(vm.contentRect == nil)
        #expect(vm.primaryID == nil)
        #expect(vm.pose == .sleeping)
        #expect(vm.tint == Palette.idle)
        #expect(vm.tailX == 0)
        #expect(vm.contentKind == "bubble:")
    }

    @Test func petRectSitsInsideThePanel() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        let r = vm.petRect
        #expect(r.size == PetViewModel.petSize)
        let panel = CGRect(origin: .zero, size: PetViewModel.panelSize)
        #expect(panel.contains(r))
    }

    @Test func aSessionGetsABubbleOnTheRoomierSide() throws {
        let low = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        low.sessions = [makeSession("a")]
        #expect(low.opensUp)
        let bubble = try #require(low.contentRect)
        #expect(bubble.size == CGSize(width: PetViewModel.bubbleSize.width,
                                      height: PetViewModel.bubbleSize.height + PetViewModel.tail))
        #expect(bubble.maxY == low.petRect.minY)

        let high = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 700)))
        high.sessions = [makeSession("a")]
        #expect(!high.opensUp)
        let below = try #require(high.contentRect)
        #expect(below.minY == high.petRect.maxY + PetViewModel.gapBelow)
    }

    /// Sessions arrive sorted most urgent first, as `SessionStore` publishes them; the pet takes the first.
    @Test func primaryFollowsTheMostUrgentSessionAndTintsThePet() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.sessions = [makeSession("q", agent: .gemini, activity: .waiting(reason: "permission", message: nil)),
                       makeSession("w", agent: .codex)]
        #expect(vm.primary?.sessionId == "q")
        #expect(vm.pose == .waiting)
        #expect(vm.tint == Palette.agent(.gemini))
        #expect(vm.contentKind == "bubble:\(vm.primaryID ?? "")")
        #expect(vm.badge != nil)
    }

    @Test func primaryIsHeldSteadyWhileOthersOfTheSameUrgencyChurn() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.sessions = [makeSession("a"), makeSession("b")]
        let first = vm.primaryID
        vm.sessions = [makeSession("b"), makeSession("a")]
        #expect(vm.primaryID == first)
        vm.sessions = [makeSession("c", activity: .error(message: nil)), makeSession("a")]
        #expect(vm.primary?.sessionId == "c")
        vm.sessions = [makeSession("idle", activity: .idle)]
        #expect(vm.primaryID == nil)
    }

    @Test func expandedListGrowsWithItsRows() throws {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.sessions = [makeSession("a")]
        vm.expanded = true
        let one = try #require(vm.contentRect)
        #expect(one.width == PetViewModel.listWidth)
        #expect(vm.contentKind == "list")
        vm.sessions = [makeSession("a"), makeSession("b"), makeSession("c")]
        let three = try #require(vm.contentRect)
        #expect(three.height > one.height)
    }

    @Test func tappingThePetTogglesThePeekAndReacts() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.sessions = [makeSession("a", activity: .done(summary: nil))]
        vm.expanded = true
        let before = vm.reactionCount
        vm.tapPet()
        #expect(vm.peekPinned)
        #expect(!vm.expanded)
        #expect(vm.reactionCount == before + 1)
        #expect(vm.reaction == PetPolicy.reaction(to: .done))
        #expect(vm.contentKind == "peek")
        #expect(vm.contentRect?.width == PetViewModel.peekWidth)
        vm.tapPet()
        #expect(!vm.peekPinned)
    }

    @Test func burstsCanBeCleared() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.tapPet()
        vm.clearBursts()
        #expect(vm.bursts.isEmpty)
    }

    @Test func tappingASessionOpensIt() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        var opened: [String] = []
        vm.onOpen = { opened.append($0.sessionId) }
        vm.tapSession(makeSession("a"), at: nil)
        vm.tapSession(makeSession("b"), at: CGPoint(x: 10, y: 10))
        #expect(opened == ["a", "b"])
    }

    @Test func speakingShowsTheBubbleEvenWithoutSessions() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.speaking = true
        #expect(vm.contentRect != nil)
        #expect(vm.contentKind == "speaking")
    }

    @Test func reactCountsEveryReaction() {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: 600, y: 100)))
        vm.react(.wave)
        vm.react(.wave)
        #expect(vm.reaction == .wave)
        #expect(vm.reactionCount == 2)
    }

    @Test(arguments: [CGFloat(0), 200, 600, 1_300])
    func tailStaysOnTheBubble(x: CGFloat) throws {
        let vm = PetViewModel(placement: placement(at: CGPoint(x: x, y: 100)))
        vm.sessions = [makeSession("a")]
        let content = try #require(vm.contentRect)
        #expect(vm.tailX >= 18 && vm.tailX <= content.width - 18)
        #expect(content.minX >= 0 && content.maxX <= PetViewModel.panelSize.width)
    }
}
