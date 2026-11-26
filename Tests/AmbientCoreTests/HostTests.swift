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

    @Test func appServerIsToldFromExecByItsSubcommand() {
        #expect(HostCapture.isAppServer(["codex", "app-server", "--analytics-default-enabled"]))
        #expect(HostCapture.isAppServer(["codex", "-c", "features.x=true", "app-server"]))
        #expect(!HostCapture.isAppServer(["codex", "exec", "--ephemeral", "app-server"]))
        #expect(!HostCapture.isAppServer(["codex", "resume"]))
        #expect(!HostCapture.isAppServer([]))
    }

    @Test func hostKeepsOnlyWhetherItsTheAppServer() {
        let chain: [ProcessTree.Entry] = [.init(pid: 9, name: "sh"), .init(pid: 8, name: "codex")]
        #expect(HostCapture.host(environment: [:], chain: chain, arguments: ["codex", "app-server"]).appServer == true)
        #expect(HostCapture.host(environment: [:], chain: chain, arguments: ["codex", "exec", "fix it"]).appServer == nil)
        #expect(HostCapture.host(environment: [:], chain: chain).appServer == nil)
    }

    @Test func readsARealProcessArguments() throws {
        let sleep = Process()
        sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleep.arguments = ["30"]
        try sleep.run()
        defer { sleep.terminate() }
        #expect(ProcessTree.arguments(of: sleep.processIdentifier) == ["/bin/sleep", "30"])
    }

    @Test func noArgumentsForAProcessThatIsGone() {
        #expect(ProcessTree.arguments(of: 99_999_999) == nil)
    }
}

@Suite struct HostCaptureDetailTests {
    private let chain: [ProcessTree.Entry] = [.init(pid: 9, name: "sh"), .init(pid: 8, name: "claude")]

    @Test func capturesReturnAddressesFromTheEnvironment() {
        let env = [
            "CLAUDE_CODE_HOST_SESSION_ID": "local_8cfe9451-cdf8-4279-8914-31861d028f4f",
            "TMUX": "/private/tmp/tmux-501/default,4242,0",
            "TMUX_PANE": "%3",
            "CMUX_WORKSPACE_ID": "ws-1",
            "CMUX_SURFACE_ID": "sf-2",
            "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
        ]
        let host = HostCapture.host(environment: env, chain: chain, tty: "/dev/ttys004")
        #expect(host.tty == "/dev/ttys004")
        #expect(host.hostSessionId == "local_8cfe9451-cdf8-4279-8914-31861d028f4f")
        #expect(host.tmuxSocket == "/private/tmp/tmux-501/default")
        #expect(host.tmuxPane == "%3")
        #expect(host.cmuxWorkspace == "ws-1")
        #expect(host.cmuxSurface == "sf-2")
        #expect(host.cmuxSocket == "/tmp/cmux.sock")
    }

    @Test func missingValuesStayNil() {
        let host = HostCapture.host(environment: ["TMUX": "", "TMUX_PANE": ""], chain: chain, tty: nil)
        #expect(host.tty == nil && host.hostSessionId == nil && host.tmuxSocket == nil && host.tmuxPane == nil)
    }

    @Test func olderHostInfoStillDecodes() throws {
        let json = #"{"bundleId":"com.apple.Terminal","pids":[1,2],"agentPid":2}"#
        let host = try JSONDecoder().decode(HostInfo.self, from: Data(json.utf8))
        #expect(host.bundleId == "com.apple.Terminal" && host.tty == nil)
    }

    @Test func ttyNamesComeFromDeviceNumbers() {
        #expect(ProcessTree.ttyName(device: -1) == nil)
        // Our own process may or may not have a terminal; either way the answer is a /dev path or nil.
        if let tty = ProcessTree.tty(of: getpid()) { #expect(tty.hasPrefix("/dev/")) }
    }
}
