@testable import AmbientApp
@testable import AmbientCore
import Foundation
import Testing

private func ask(_ session: String = "s1") -> PermissionAsk {
    PermissionAsk(event: event(.needsInput(reason: "permission", message: "rm -rf build"), session: session),
                  toolName: "Bash", hint: "rm -rf build")
}

/// `answer(for:)` blocks its caller until the main thread settles the prompt, so it is always called off the main
/// thread here, while the main actor awaits it.
@MainActor @Suite(.serialized) struct PermissionDeskTests {
    @Test func settlingAnUnknownPromptReturnsNil() throws {
        let box = try AppSandbox()
        let desk = PermissionDesk(model: AppModel(prefs: box.preferences(), stateURL: nil), prefs: box.preferences())
        #expect(desk.settle("nope", with: .allow) == nil)
        #expect(desk.current == nil && desk.count == 0)
    }

    @Test func promptsGoBackToTheAgentWhenAnsweringIsOff() async throws {
        let box = try AppSandbox()
        let prefs = box.preferences()
        prefs.answerPermissions = false
        let desk = PermissionDesk(model: AppModel(prefs: prefs, stateURL: nil), prefs: prefs)
        let a = ask()
        let answer = await Task.detached { desk.answer(for: a) }.value
        #expect(answer == .ask)
        #expect(desk.count == 0)
    }

    @Test func promptsGoBackWhenTheIslandIsOff() async throws {
        let box = try AppSandbox()
        let prefs = box.preferences()
        prefs.answerPermissions = true
        prefs.islandEnabled = false
        let desk = PermissionDesk(model: AppModel(prefs: prefs, stateURL: nil), prefs: prefs)
        let a = ask()
        #expect(await Task.detached { desk.answer(for: a) }.value == .ask)
    }

    @Test func aClickAnswersTheWaitingHook() async throws {
        let box = try AppSandbox()
        let prefs = box.preferences()
        prefs.answerPermissions = true
        prefs.islandEnabled = true
        prefs.permissionWait = 30
        let desk = PermissionDesk(model: AppModel(prefs: prefs, stateURL: nil), prefs: prefs)
        let a = ask()
        let waiting = Task.detached { desk.answer(for: a) }
        // Let the main thread queue it, then click.
        for _ in 0..<50 where desk.current == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(desk.current?.ask.id == a.id)
        #expect(desk.count == 1)
        #expect(desk.settle(a.id, with: .allow)?.id == a.id)
        #expect(await waiting.value == .allow)
        #expect(desk.current == nil && desk.count == 0)
        #expect(desk.settle(a.id, with: .deny) == nil)
    }

    @Test func theAgentMovingOnWithdrawsItsPrompt() async throws {
        let box = try AppSandbox()
        let prefs = box.preferences()
        prefs.answerPermissions = true
        prefs.islandEnabled = true
        let model = AppModel(prefs: prefs, stateURL: nil)
        let desk = PermissionDesk(model: model, prefs: prefs)
        model.apply(event(.promptSubmitted))
        let a = ask()
        let waiting = Task.detached { desk.answer(for: a) }
        for _ in 0..<50 where desk.current == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(desk.count == 1)
        model.apply(event(.toolStarted(name: "Read", detail: "a.swift"), at: 1))
        model.apply(event(.turnCompleted(summary: nil), at: 2))
        #expect(await waiting.value == .ask)
        #expect(desk.count == 0)
    }
}
