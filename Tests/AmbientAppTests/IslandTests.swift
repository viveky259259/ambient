@testable import AmbientApp
@testable import AmbientCore
import Foundation
import Testing

private let geometry = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), hasNotch: true,
                                      notchWidth: 200, notchHeight: 32, centerX: 756)

@MainActor @Suite struct IslandViewModelTests {
    @Test func sizesForEveryPresentation() {
        let vm = IslandViewModel(geometry: geometry)
        let collapsed: CGFloat = 200 + 2 * IslandViewModel.wing
        #expect(vm.size(for: .hidden) == CGSize(width: 200, height: 32))
        #expect(vm.size(for: .collapsed) == CGSize(width: collapsed, height: 32))
        #expect(vm.size(for: .bloom("x")) == CGSize(width: 400, height: 106))
        #expect(vm.size(for: .speech) == CGSize(width: 360, height: 80))
        #expect(vm.size(for: .voice) == CGSize(width: 440, height: 84))
        #expect(vm.size(for: .voiceIncoming) == CGSize(width: collapsed, height: 32))
        #expect(vm.size(for: .permission("p")) == CGSize(width: 440, height: 147))
        #expect(vm.size(for: .expanded) == CGSize(width: 440, height: 32 + 12 + 52 + 44))
    }

    @Test func aWideNotchKeepsTheCollapsedWidth() {
        let wide = IslandGeometry(screenFrame: geometry.screenFrame, hasNotch: true, notchWidth: 500, notchHeight: 32,
                                  centerX: 756)
        let vm = IslandViewModel(geometry: wide)
        let collapsed = 500 + 2 * IslandViewModel.wing
        for p: IslandViewModel.Presentation in [.bloom("x"), .speech, .voice, .permission("p"), .expanded] {
            #expect(vm.size(for: p).width == collapsed)
        }
    }

    @Test func permissionCardGrowsWithItsHint() {
        let vm = IslandViewModel(geometry: geometry)
        let ask = PermissionAsk(event: event(.needsInput(reason: "permission", message: nil)), toolName: "Bash",
                                hint: String(repeating: "long command ", count: 30))
        vm.permission = PermissionQueue.Entry(ask: ask, deadline: testNow)
        #expect(vm.size(for: .permission(ask.id)).height == 32 + 100 + CGFloat(ask.hintLines) * 15)
    }

    @Test func expandedListShowsAFewRowsUntilAskedForAll() {
        let vm = IslandViewModel(geometry: geometry)
        vm.sessions = (0..<12).map { makeSession("s\($0)") }
        #expect(vm.listed.count == IslandViewModel.maxRows)
        #expect(vm.hasMore)
        let fiveRows: CGFloat = 32 + 12 + 5 * 52 + 44
        #expect(vm.size(for: .expanded).height == fiveRows)
        vm.showingAll = true
        #expect(vm.listed.count == 12)
        let tenRows: CGFloat = 32 + 12 + CGFloat(IslandViewModel.maxAllRows) * 52 + 44
        #expect(vm.size(for: .expanded).height == tenRows)
    }

    @Test func noMoreWhenEverySessionFits() {
        let vm = IslandViewModel(geometry: geometry)
        vm.sessions = (0..<5).map { makeSession("s\($0)") }
        #expect(!vm.hasMore)
    }

    @Test func bloomSessionFollowsThePresentation() {
        let vm = IslandViewModel(geometry: geometry)
        let a = makeSession("a"), b = makeSession("b")
        vm.sessions = [a, b]
        #expect(vm.bloomSession == nil)
        vm.presentation = .bloom(b.id)
        #expect(vm.bloomSession?.id == b.id)
        vm.presentation = .bloom("gone")
        #expect(vm.bloomSession == nil)
        vm.presentation = .expanded
        #expect(vm.bloomSession == nil)
    }

    @Test func primaryIsTheFirstSessionThatWantsAttention() {
        let vm = IslandViewModel(geometry: geometry)
        vm.sessions = [makeSession("idle", activity: .idle), makeSession("busy")]
        #expect(vm.primary?.sessionId == "busy")
        vm.sessions = [makeSession("idle", activity: .idle)]
        #expect(vm.primary == nil)
    }

    @Test func currentSizeTracksThePresentation() {
        let vm = IslandViewModel(geometry: geometry)
        #expect(vm.currentSize == vm.size(for: .hidden))
        vm.presentation = .speech
        #expect(vm.currentSize == vm.size(for: .speech))
    }
}

@Suite struct IslandGeometryTests {
    @Test func panelHangsFromTheTopCenter() {
        let f = geometry.panelFrame
        #expect(f.size == IslandGeometry.panelSize)
        #expect(f.midX == geometry.centerX)
        #expect(f.maxY == geometry.screenFrame.maxY)
    }

    @Test func screenRectIsCenteredUnderTheNotch() {
        let r = geometry.screenRect(for: CGSize(width: 300, height: 80))
        #expect(r == CGRect(x: 606, y: 902, width: 300, height: 80))
    }

    @Test func worksOnASecondDisplayOffsetInGlobalSpace() {
        let g = IslandGeometry(screenFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080), hasNotch: false,
                               notchWidth: 120, notchHeight: 24, centerX: -960)
        #expect(g.screenRect(for: CGSize(width: 120, height: 24)) == CGRect(x: -1020, y: 1256, width: 120, height: 24))
        #expect(g.panelFrame.minX == -960 - IslandGeometry.panelSize.width / 2)
    }
}
