import Foundation
import Testing
@testable import AmbientCore

@Suite struct HostTests {
    @Test func agentIsTheFirstNonShellAncestor() {
        let chain: [ProcessTree.Entry] = [.init(pid: 50, name: "bash"), .init(pid: 40, name: "claude"), .init(pid: 30, name: "zsh")]
        #expect(HostCapture.agentPid(in: chain) == 40)
    }

    @Test func execFormHooksHaveTheAgentAsParent() {
        let chain: [ProcessTree.Entry] = [.init(pid: 40, name: "node"), .init(pid: 30, name: "zsh")]
        #expect(HostCapture.agentPid(in: chain) == 40)
    }

    @Test func noAgentWhenOnlyShells() {
        #expect(HostCapture.agentPid(in: [.init(pid: 3, name: "sh"), .init(pid: 1, name: "launchd")]) == nil)
        #expect(HostCapture.agentPid(in: []) == nil)
    }

    @Test func hostComesFromEnvironment() {
        let chain: [ProcessTree.Entry] = [.init(pid: 9, name: "sh"), .init(pid: 8, name: "codex")]
        let host = HostCapture.host(environment: ["__CFBundleIdentifier": "com.mitchellh.ghostty", "TERM_PROGRAM": "ghostty"], chain: chain)
        #expect(host == HostInfo(bundleId: "com.mitchellh.ghostty", termProgram: "ghostty", pids: [9, 8], agentPid: 8))
    }

    @Test func realProcessTreeStartsAtOurParent() {
        let chain = ProcessTree.ancestors(of: getpid())
        #expect(chain.first?.pid == getppid())
        #expect(chain.count >= 1)
        #expect(chain.allSatisfy { !$0.name.isEmpty })
    }
}
