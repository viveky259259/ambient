// Plays what goes to the Ambient speaker on another Mac. scripts/speaker-pipe.sh builds it, copies it to the other Mac
// and runs it; the app carries it as Contents/Helpers/ambient-speaker, and runs it with --app.
//
//   speaker-pipe send HOST [--udp] [--seconds N] [--app] [PLAY OPTIONS] [-- SSH COMMAND]   here: the loopback, to HOST
//   speaker-pipe play [--buffer MS] [--window S] [--fixed] [--quiet] [--check HZ]   there: standard input, out loud
//   speaker-pipe tone [--seconds N] [--hz HZ]               a test tone to the Ambient speaker
//
// The sound goes as it is, 48 kHz stereo floats, about 3 Mbit/s. Each packet carries its sample time and when it
// played here, and the player answers with how much it holds, so the sender can say how late the other Mac's speakers
// are. It tells the Ambient speaker, which reports that as its latency, so video on this Mac waits for its sound.
//
// The player starts once it holds --buffer (150 ms). After the network stalls it plays the late sound rather than
// skipping it, and holds that much from then on; it gets back down, toward the longest stall in the last --window
// seconds (120), by leaving out silence. --fixed holds --buffer and skips a backlog at once, the old way, to compare.
// --quiet plays silence; --check HZ checks a tone at HZ came through whole.
//
// With --udp the sound goes over UDP to the address ssh reaches HOST at, and ssh only starts, stops and carries ⏯. Each
// frame then has its place by sample time, and the player plays --buffer behind the quickest packets: one slower than
// that is too late, and its place plays as silence. So a stall costs a gap, not a delay from then on, and the delay
// stays where it is, for video to be kept in step with it. A datagram that doesn't come, the player asks for again,
// every 25 ms until it comes or its turn has passed, and the sender sends it again from the last 2.7 s it keeps.
// --no-resend turns that off, to compare. The player starts holding --buffer, and sets its hold from what comes: when a
// datagram comes after its turn, it holds that much more from then on, plus 20 ms, with one short silence. When the
// last minute shows it holds more than it needs, it holds less, by leaving out sound at a quiet moment. It holds 30 ms
// to 1 s, and a datagram later than that is an outage, not a reason to hold more. --fixed keeps --buffer, to compare.
// --window works only over ssh. --debug has the UDP player say what it decides each second, on standard error.
//
// The player is the other Mac's Now Playing, so its ⏯ (the keyboard's key, headphones, Control Center) comes back up
// the pipe, and the sender hands it to whatever is playing here. With --quiet it leaves Now Playing alone.
//
// The player plays only on a Mac whose own Ambient settings let other Macs play sound there (Settings › Voice & Sound ›
// Ambient Speaker › Play sound from other Macs). After `--`, an ssh command ending with HOST, the way a pairing reaches
// it, is used instead of plain ssh, so its port, key and jump hosts apply.
//
// --app is for the app that runs the sender. It also writes what happens as JSON lines on standard output (every line
// that starts with "{"), and stops once its standard input closes, so it never outlives the app.
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import MediaPlayer
import SystemConfiguration
import os

let speakerUID = "com.viveky259259.Ambient.speaker"
let loopbackUID = "com.viveky259259.Ambient.speaker.loopback"
let remotePath = "~/.ambient/speaker/speaker-pipe" // where scripts/speaker-pipe.sh copies it; the remote shell expands ~
let rate = 48_000.0
let channels = 2
let bytesPerFrame = channels * MemoryLayout<Float>.size
let magic: UInt32 = 0x414D_4231 // "AMB1"
let headerSize = 32 // magic, frames: UInt32; sample time: Int64; when it played, when it was sent: UInt64 ns
let maxFrames = 16384

/// Whether an app runs the sender: see --app.
var forApp = false

/// One JSON line for the app that runs the sender, when one does.
func tell(_ event: String, _ fields: [String: Any] = [:]) {
    guard forApp else { return }
    var all = fields
    all["event"] = event
    guard let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    tell("error", ["message": message])
    FileHandle.standardError.write(Data("speaker-pipe: \(message)\n".utf8))
    exit(1)
}

/// The receiving Mac's Ambient setting that lets other Macs play sound on it.
let receiveSetting = (domain: "com.viveky259259.Ambient", key: "speakerReceive")

let timebase: mach_timebase_info_data_t = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return timebase
}()
func nanos(_ ticks: UInt64) -> UInt64 { ticks * UInt64(timebase.numer) / UInt64(timebase.denom) }
func now() -> UInt64 { nanos(mach_absolute_time()) }
func ms(_ value: Double) -> String { String(format: "%.0f ms", value) }

func newLock() -> UnsafeMutablePointer<os_unfair_lock> {
    let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    return lock
}
func locked<T>(_ lock: UnsafeMutablePointer<os_unfair_lock>, _ body: () -> T) -> T {
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    return body()
}

// MARK: - Core Audio

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func device(uid: String) -> AudioObjectID? {
    var place = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var uid = uid as CFString
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &uid) { uid in
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place,
                                   UInt32(MemoryLayout<CFString>.size), uid, &size, &id)
    }
    return status == noErr && id != kAudioObjectUnknown ? id : nil
}

func name(_ id: AudioObjectID) -> String {
    var place = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &place, 0, nil, &size, &name) == noErr, let name else { return "?" }
    return name.takeRetainedValue() as String
}

func number(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
    var place = address(selector, scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &place, 0, nil, &size, &value) == noErr ? value : 0
}

/// The Ambient speaker's own property: how late the other Mac plays what it plays, in frames, as a CFNumber. The speaker
/// reports it as its latency. It goes back to none once nothing records the loopback.
let streamDelaySelector: AudioObjectPropertySelector = 0x6144_6C79 // 'aDly'

/// Frames, or nil from a speaker too old to have it.
func streamDelay(_ speaker: AudioObjectID) -> Int? {
    var place = address(streamDelaySelector)
    var value: Unmanaged<CFPropertyList>?
    var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
    guard AudioObjectGetPropertyData(speaker, &place, 0, nil, &size, &value) == noErr, let value else { return nil }
    return (value.takeRetainedValue() as? NSNumber)?.intValue
}

func setStreamDelay(_ speaker: AudioObjectID, frames: Int) -> Bool {
    var place = address(streamDelaySelector)
    let number = NSNumber(value: frames)
    var value = Unmanaged<CFPropertyList>.passUnretained(number) // the property's data is the reference itself
    return withExtendedLifetime(number) {
        AudioObjectSetPropertyData(speaker, &place, 0, nil, UInt32(MemoryLayout<CFPropertyList>.size), &value) == noErr
    }
}

func microphoneAllowed() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined:
        let answered = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .audio) { granted = $0; answered.signal() }
        answered.wait()
        return granted
    default: return false
    }
}

func writeAll(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Bool {
    var done = 0
    while done < count {
        let n = write(fd, bytes + done, count - done)
        if n < 0 {
            if errno == EINTR { continue }
            return false
        }
        done += n
    }
    return true
}

/// One line to the sender, on standard output, which is otherwise left alone. The stream and ⏯ both say things.
let sayLock = newLock()
func say(_ line: String) {
    let text = line + "\n"
    locked(sayLock) { _ = text.withCString { writeAll(1, $0, strlen($0)) } }
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
let mode = args.isEmpty ? "" : args.removeFirst()

func option(_ name: String) -> Double? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count, let value = Double(args[i + 1]), value >= 0 else { fail("\(name) takes a number") }
    args.removeSubrange(i...(i + 1))
    return value
}

func text(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) takes a value") }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func noMoreArguments() {
    if let extra = args.first { fail("unknown option \(extra)") }
}

// MARK: - Send

/// Hands play, pause or toggle to whatever is playing on this Mac, as its own ⏯ key would. MediaRemote is private, and
/// since macOS 15.4 it won't tell a process like this one what's playing, but it still takes commands from one.
typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
let mediaCommand: SendCommand? = {
    let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL),
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else { return nil }
    return unsafeBitCast(pointer, to: SendCommand.self)
}()
let mediaCommands: [String: UInt32] = ["play": 0, "pause": 1, "toggle": 2]

/// A word for the remote shell, which ssh hands the command line to.
func quoted(_ word: String) -> String { "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// MARK: - UDP

let udpMagic: UInt32 = 0x414D_5531 // "AMU1"
// magic, frames: UInt32; sample time: Int64; when it played, when it was sent, the token, its number: UInt64
let udpHeaderSize = 48
let udpFrames = 128 // 1 KB of sound, so each datagram fits whole in Tailscale's 1,280-byte packets

func inet(_ host: String, _ port: UInt16) -> sockaddr_in? {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    return inet_pton(AF_INET, host, &address.sin_addr) == 1 ? address : nil
}

func withSockaddr<T>(_ address: inout sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
}

/// The IPv4 address ssh reaches `host` at, with the transport's options, so the UDP goes the same way: over Tailscale,
/// its 100.x address.
func resolve(_ host: String, via transport: [String]) -> String? {
    let ssh = Process()
    ssh.executableURL = URL(fileURLWithPath: transport[0])
    ssh.arguments = Array(transport.dropFirst()) + ["-G", host]
    let out = Pipe()
    ssh.standardOutput = out
    ssh.standardError = FileHandle.nullDevice
    guard (try? ssh.run()) != nil else { return nil }
    let config = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    ssh.waitUntilExit()
    guard let line = config.split(separator: "\n").first(where: { $0.hasPrefix("hostname ") }) else { return nil }
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_DGRAM
    var found: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(String(line.dropFirst(9)), nil, &hints, &found) == 0, let found, let address = found.pointee.ai_addr
    else { return nil }
    defer { freeaddrinfo(found) }
    var ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &ip, &text, socklen_t(text.count)) != nil else { return nil }
    return String(cString: text)
}

func send(to host: String) -> Never {
    // The pairing's ssh command, after `--`, without its host: its options come first, ours after them.
    var transport = ["/usr/bin/ssh"]
    if let dash = args.firstIndex(of: "--") {
        let given = Array(args[(dash + 1)...])
        args.removeSubrange(dash...)
        guard given.count >= 2, URL(fileURLWithPath: given[0]).lastPathComponent == "ssh", given.last == host else {
            fail("-- takes an ssh command that ends with \(host)")
        }
        transport = Array(given.dropLast())
        if !transport[0].hasPrefix("/") { transport[0] = "/usr/bin/ssh" }
    }
    let seconds = option("--seconds")
    // Where the player is on the other Mac. The app names its copy by its contents, so it never overwrites a player
    // that's running.
    let playerPath = text("--remote-path") ?? remotePath
    let here = SCDynamicStoreCopyComputerName(nil, nil).map { $0 as String } ?? "the other Mac"
    var forwarded = ["--from", quoted(here)]
    if let buffer = option("--buffer") { forwarded += ["--buffer", String(buffer)] }
    if let window = option("--window") { forwarded += ["--window", String(window)] }
    if flag("--fixed") { forwarded.append("--fixed") }
    if flag("--quiet") { forwarded.append("--quiet") }
    if let hz = option("--check") { forwarded += ["--check", String(hz)] }
    let udp = flag("--udp")
    if flag("--debug") { forwarded.append("--debug") }
    if flag("--no-resend") { forwarded.append("--no-resend") }
    forApp = flag("--app")
    noMoreArguments()
    if udp, let extra = forwarded.first(where: { $0 == "--window" }) {
        fail("\(extra) works only over ssh")
    }
    if !udp, forwarded.contains("--no-resend") { fail("--no-resend goes with --udp") }
    guard let loopback = device(uid: loopbackUID) else {
        fail("Core Audio has no Ambient speaker. Install it: scripts/install-speaker.sh")
    }
    guard microphoneAllowed() else {
        fail("this app can't record the loopback: allow it in System Settings › Privacy & Security › Microphone")
    }
    signal(SIGPIPE, SIG_IGN)
    // Where to say how late the other Mac plays.
    let speaker = device(uid: speakerUID).flatMap { streamDelay($0) != nil ? $0 : nil }
    if speaker == nil {
        print("This Ambient speaker can't tell macOS how late \(host) plays, so video won't wait for it. Reinstall it: "
              + "scripts/build-speaker.sh, then scripts/install-speaker.sh")
    }

    // Over UDP, the player listens on the address we send to, and keeps only datagrams that carry this run's token.
    var udpSocket: Int32 = -1, udpAddress = sockaddr_in(), token: UInt64 = 0
    if udp {
        guard let address = resolve(host, via: transport), let destination = inet(address, 0) else {
            fail("couldn't find the address ssh reaches \(host) at")
        }
        udpAddress = destination
        token = UInt64.random(in: 1...UInt64.max)
        forwarded += ["--listen", address, "--token", String(token)]
        udpSocket = socket(AF_INET, SOCK_DGRAM, 0)
        var size: Int32 = 1 << 20
        setsockopt(udpSocket, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
    }

    let ssh = Process()
    ssh.executableURL = URL(fileURLWithPath: transport[0])
    ssh.arguments = Array(transport.dropFirst())
        + ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no",
           "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes", host, playerPath, "play"] + forwarded
    let toPlayer = Pipe(), fromPlayer = Pipe()
    ssh.standardInput = toPlayer
    ssh.standardOutput = fromPlayer
    do { try ssh.run() } catch { fail("couldn't run ssh: \(error.localizedDescription)") }
    let pipe = toPlayer.fileHandleForWriting.fileDescriptor

    // Core Audio hands each buffer to a queue, and a thread of ours writes it, so a slow network never holds up the IO.
    let slots = 64, slotFrames = 4096
    let queue = UnsafeMutablePointer<Float>.allocate(capacity: slots * slotFrames * channels)
    var info = [(frames: Int, sampleTime: Int64, played: UInt64)](repeating: (0, 0, 0), count: slots)
    var head = 0, queued = 0, lost = 0, stopping = false
    let lock = newLock()
    let ready = DispatchSemaphore(value: 0)
    let written = DispatchSemaphore(value: 0) // the writer has sent everything and closed the pipe
    let playerReady = DispatchSemaphore(value: 0)

    // What the player says, and what we know: when a frame played here to when it went into the pipe.
    var player = (name: host, outputMs: 0.0, roundTripMs: 0.0, heldMs: 0.0, goalMs: 0.0, gaps: 0, trims: 0,
                  shrunk: 0.0)
    // Over UDP: what the player says it missed and got again, and what we couldn't send, sent again, or no longer had.
    var overUDP = (missingMs: 0.0, lost: 0, late: 0, resyncs: 0, recovered: 0, unsent: 0, resent: 0, gone: 0,
                   holdMs: 0.0, raises: 0, lowers: 0)
    var hereMs = 0.0, sentBytes = 0
    var since: UInt64 = 0 // when recording started: the first 3 seconds, while it settles, aren't counted
    var lates: [Double] = [] // how late the other Mac played it, at each of its answers
    var recent: [Double] = [] // the last 3 s of them
    let stats = newLock()

    /// How late the other Mac plays it, at one of its answers. With `stats` locked.
    func measure() {
        guard since > 0, now() &- since > 3_000_000_000 else { return }
        let late = hereMs + player.roundTripMs / 2 + player.heldMs + player.outputMs
        lates.append(late)
        recent.append(late)
        if recent.count > 6 { recent.removeFirst() }
    }

    var recording: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(&recording, loopback, nil) { _, input, time, _, _ in
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, buffer.mNumberChannels == UInt32(channels),
              let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let frames = min(Int(buffer.mDataByteSize) / bytesPerFrame, slotFrames)
        os_unfair_lock_lock(lock)
        if queued == slots {
            lost += 1
        } else {
            let slot = (head + queued) % slots
            (queue + slot * slotFrames * channels).update(from: data, count: frames * channels)
            info[slot] = (frames, Int64(time.pointee.mSampleTime), nanos(time.pointee.mHostTime))
            queued += 1
        }
        os_unfair_lock_unlock(lock)
        ready.signal()
    }
    guard status == noErr, let recording else { ssh.terminate(); fail("couldn't record from the loopback: \(status)") }

    let packet = UnsafeMutableRawPointer.allocate(byteCount: headerSize + slotFrames * bytesPerFrame, alignment: 16)
    let datagram = UnsafeMutableRawPointer.allocate(byteCount: udpHeaderSize + udpFrames * bytesPerFrame, alignment: 16)
    var number: UInt64 = 0
    // The last datagrams sent, to send again when the player asks: 1,024 of them, 2.7 s.
    let historySize = 1024, datagramSize = udpHeaderSize + udpFrames * bytesPerFrame
    let history = UnsafeMutableRawPointer.allocate(byteCount: historySize * datagramSize, alignment: 16)
    var historyNumbers = [UInt64](repeating: .max, count: historySize)
    let historyLock = newLock()

    /// Sends one buffer as datagrams of `udpFrames`, numbered so the player can tell what never came.
    func sendDatagrams(_ next: (frames: Int, sampleTime: Int64, played: UInt64)) {
        var offset = 0
        while offset < next.frames {
            let frames = min(udpFrames, next.frames - offset)
            let size = udpHeaderSize + frames * bytesPerFrame
            let played = next.played + UInt64(Double(offset) / rate * 1e9), sent = now()
            datagram.storeBytes(of: udpMagic, toByteOffset: 0, as: UInt32.self)
            datagram.storeBytes(of: UInt32(frames), toByteOffset: 4, as: UInt32.self)
            datagram.storeBytes(of: next.sampleTime + Int64(offset), toByteOffset: 8, as: Int64.self)
            datagram.storeBytes(of: played, toByteOffset: 16, as: UInt64.self)
            datagram.storeBytes(of: sent, toByteOffset: 24, as: UInt64.self)
            datagram.storeBytes(of: token, toByteOffset: 32, as: UInt64.self)
            datagram.storeBytes(of: number, toByteOffset: 40, as: UInt64.self)
            (datagram + udpHeaderSize).copyMemory(from: packet + headerSize + offset * bytesPerFrame,
                                                  byteCount: frames * bytesPerFrame)
            locked(historyLock) {
                let at = Int(number % UInt64(historySize))
                (history + at * datagramSize).copyMemory(from: datagram, byteCount: size)
                historyNumbers[at] = number
            }
            number += 1
            let delivered = Foundation.send(udpSocket, datagram, size, 0) == size
            locked(stats) {
                hereMs = Double(sent &- played) / 1e6
                if delivered { sentBytes += size } else { overUDP.unsent += 1 }
            }
            offset += frames
        }
    }

    Thread {
        while true {
            ready.wait()
            while true {
                os_unfair_lock_lock(lock)
                if queued == 0, stopping { // the end goes right after the last sound, so the player doesn't run dry first
                    os_unfair_lock_unlock(lock)
                    toPlayer.fileHandleForWriting.closeFile()
                    written.signal()
                    return
                }
                guard queued > 0 else { os_unfair_lock_unlock(lock); break }
                let slot = head, next = info[slot]
                (packet + headerSize).copyMemory(from: queue + slot * slotFrames * channels,
                                                 byteCount: next.frames * bytesPerFrame)
                head = (head + 1) % slots
                queued -= 1
                os_unfair_lock_unlock(lock)
                if udp {
                    sendDatagrams(next)
                    continue
                }
                let sent = now()
                packet.storeBytes(of: magic, toByteOffset: 0, as: UInt32.self)
                packet.storeBytes(of: UInt32(next.frames), toByteOffset: 4, as: UInt32.self)
                packet.storeBytes(of: next.sampleTime, toByteOffset: 8, as: Int64.self)
                packet.storeBytes(of: next.played, toByteOffset: 16, as: UInt64.self)
                packet.storeBytes(of: sent, toByteOffset: 24, as: UInt64.self)
                let size = headerSize + next.frames * bytesPerFrame
                guard writeAll(pipe, packet, size) else { return }
                locked(stats) {
                    hereMs = Double(sent &- next.played) / 1e6
                    sentBytes += size
                }
            }
        }
    }.start()

    /// Sends again the datagrams the player asks for (`FIRST-LAST` or `NUMBER`), if they're still kept, with the top
    /// bit of their frame count set so it can tell them apart.
    func resend(_ ranges: ArraySlice<String>) {
        let again = UnsafeMutableRawPointer.allocate(byteCount: datagramSize, alignment: 16)
        defer { again.deallocate() }
        for range in ranges {
            let ends = range.split(separator: "-").compactMap { UInt64($0) }
            guard let first = ends.first, let last = ends.last, last >= first, last - first < UInt64(historySize)
            else { continue }
            for wanted in first...last {
                let at = Int(wanted % UInt64(historySize))
                let size: Int? = locked(historyLock) {
                    guard historyNumbers[at] == wanted else { return nil }
                    let kept = history + at * datagramSize
                    let size = udpHeaderSize + Int(kept.load(fromByteOffset: 4, as: UInt32.self)) * bytesPerFrame
                    again.copyMemory(from: kept, byteCount: size)
                    return size
                }
                guard let size else {
                    locked(stats) { overUDP.gone += 1 }
                    continue
                }
                let frames = UInt32((size - udpHeaderSize) / bytesPerFrame)
                again.storeBytes(of: frames | 0x8000_0000, toByteOffset: 4, as: UInt32.self)
                let delivered = Foundation.send(udpSocket, again, size, 0) == size
                locked(stats) {
                    if delivered {
                        overUDP.resent += 1
                        sentBytes += size
                    } else {
                        overUDP.unsent += 1
                    }
                }
            }
        }
    }

    /// Answers from the player over UDP, as they come.
    func hearOverUDP() {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
        while true {
            let n = recv(udpSocket, buffer, 511, 0)
            if n < 0 {
                if errno == EINTR { continue }
                if errno == ECONNREFUSED { // the player isn't listening yet, or any more
                    usleep(10_000)
                    continue
                }
                return
            }
            buffer[n] = 0
            hear(String(cString: buffer))
        }
    }

    /// One line from the player, over ssh or UDP.
    func hear(_ text: String) {
        let words = text.split(separator: " ", maxSplits: text.hasPrefix("ready ") ? 3 : .max).map(String.init)
        switch words.first {
        case "udp" where words.count == 2 && udp: // udp PORT: where the player listens, which it says before ready
            udpAddress.sin_port = (UInt16(words[1]) ?? 0).bigEndian
            guard withSockaddr(&udpAddress, { connect(udpSocket, $0, $1) }) == 0 else {
                print("couldn't reach \(host) over UDP: \(String(cString: strerror(errno)))")
                ssh.terminate()
                return
            }
            Thread { hearOverUDP() }.start()
        case "nack" where words.count > 1: // nack FIRST-LAST NUMBER ...: datagrams the player is missing
            resend(words.dropFirst())
            return
        case "uecho" where words.count == 11: // uecho SENT-NS HELD-MS MISSING-MS LOST LATE RESYNCS RECOVERED HOLD-MS
                                               // RAISES LOWERS
            let sent = UInt64(words[1]) ?? 0
            locked(stats) {
                player.roundTripMs = Double(now() &- sent) / 1e6
                player.heldMs = Double(words[2]) ?? 0
                overUDP.missingMs = Double(words[3]) ?? 0
                overUDP.lost = Int(words[4]) ?? 0
                overUDP.late = Int(words[5]) ?? 0
                overUDP.resyncs = Int(words[6]) ?? 0
                overUDP.recovered = Int(words[7]) ?? 0
                overUDP.holdMs = Double(words[8]) ?? 0
                overUDP.raises = Int(words[9]) ?? 0
                overUDP.lowers = Int(words[10]) ?? 0
                measure()
            }
        case "udone" where words.count == 15: // udone PLAYED-S MISSING-MS LOST LATE RESYNCS RECOVERED NEED-MS AT 50, 90,
                                              // 99, 99.9 AND 100%, HOLD-MS RAISES LOWERS
            let (resent, gone) = locked(stats) { (overUDP.resent, overUDP.gone) }
            print("\(host) played \(words[1]) s of sound. \(words[2]) ms of it was missing: \(words[3]) datagrams "
                  + "never came and \(words[4]) came too late, and it moved \(words[5]) times. \(words[6]) came again in "
                  + "time, of \(resent) sent again (\(gone) asked for were no longer kept). To be in time, half of them "
                  + "needed holding \(words[7]) ms or less, 90% \(words[8]) ms, 99% \(words[9]) ms, 99.9% \(words[10]) ms, "
                  + "and all of them \(words[11]) ms. It ended holding \(words[12]) ms, having held more \(words[13]) "
                  + "times and less \(words[14]) times")
        case "ready" where words.count == 4: // ready RATE OUTPUT-MS DEVICE NAME
            locked(stats) {
                player.outputMs = Double(words[2]) ?? 0
                player.name = "\(host)'s \(words[3])"
            }
            print("Playing on \(host)'s \(words[3]), at \(words[1]) Hz")
            tell("playing", ["device": words[3], "rate": Int(words[1]) ?? 0])
            playerReady.signal()
        case "echo" where words.count == 7: // echo SENT-NS HELD-MS GAPS TRIMS GOAL-MS SHRUNK-S
            let sent = UInt64(words[1]) ?? 0
            locked(stats) {
                player.roundTripMs = Double(now() &- sent) / 1e6
                player.heldMs = Double(words[2]) ?? 0
                player.gaps = Int(words[3]) ?? 0
                player.trims = Int(words[4]) ?? 0
                player.goalMs = Double(words[5]) ?? 0
                player.shrunk = Double(words[6]) ?? 0
                measure()
            }
        case "refused" where words.count == 1: // the other Mac's settings don't let other Macs play sound on it
            fail("\(host) doesn't let other Macs play sound on it. On \(host), turn on Settings › Voice & Sound › Ambient Speaker › "
                 + "Play sound from other Macs")
        case "key" where words.count == 2: // key play|pause|toggle: someone pressed ⏯ there
            if let command = mediaCommands[words[1]], let mediaCommand, mediaCommand(command, nil) {
                print("⏯ \(words[1]) on \(host), passed to what's playing here")
            } else {
                print("⏯ \(words[1]) on \(host), but it couldn't be passed on")
            }
        case "done" where words.count == 5: // done SECONDS-PLAYED GAPS TRIMS SHRUNK-S
            print("\(host) played \(words[1]) s of sound, with \(words[2]) dropouts and \(words[3]) skips, "
                  + "and left out \(words[4]) s of silence")
        default:
            print(text)
        }
        fflush(stdout)
    }

    let finished = DispatchSemaphore(value: 0)
    Thread {
        let file = fdopen(fromPlayer.fileHandleForReading.fileDescriptor, "r")
        var line: UnsafeMutablePointer<CChar>?
        var capacity = 0
        while getline(&line, &capacity, file) > 0 {
            hear(String(cString: line!).trimmingCharacters(in: .newlines))
        }
        finished.signal()
    }.start()

    func report(_ mbit: Double) -> String {
        let lostHere = locked(lock) { lost }
        return locked(stats) {
            let network = player.roundTripMs / 2
            let late = hereMs + network + player.heldMs + player.outputMs
            if udp {
                return "\(player.name) plays it \(ms(late)) late: \(ms(hereMs)) here, \(ms(network)) on the network, "
                    + "\(ms(player.heldMs)) held (holding \(ms(overUDP.holdMs)), more \(overUDP.raises) and less "
                    + "\(overUDP.lowers) times), \(ms(player.outputMs)) in its speakers · "
                    + String(format: "%.1f Mbit/s", mbit) + " over UDP · \(lostHere) lost here, \(overUDP.unsent) unsent, "
                    + "\(ms(overUDP.missingMs)) missing there (\(overUDP.lost) never came, \(overUDP.recovered) came again "
                    + "in time, \(overUDP.late) too late), \(overUDP.resyncs) moves · \(overUDP.resent) sent again"
                    + (speaker != nil ? " · video waits \(ms(reportedMs))" : "")
            }
            return "\(player.name) plays it \(ms(late)) late: \(ms(hereMs)) here, \(ms(network)) on the network, "
                + "\(ms(player.heldMs)) held (aiming for \(ms(player.goalMs))), \(ms(player.outputMs)) in its speakers · "
                + String(format: "%.1f Mbit/s", mbit) + " · \(lostHere) lost here, \(player.gaps) dropouts, "
                + "\(player.trims) skips there" + (speaker != nil ? " · video waits \(ms(reportedMs))" : "")
        }
    }

    /// Tells the speaker how late the other Mac plays, the median of the last 3 s, when what it reports is 30 ms or more
    /// off. Lip sync looks wrong past about 45 ms, and each change costs about 90 ms of silence: the speaker restarts
    /// so players already playing follow it, and their picture holds or skips by the change.
    var reportedMs = 0.0
    func reportDelay(to speaker: AudioObjectID) {
        let sorted = locked(stats) { recent.sorted() }
        guard sorted.count >= 3 else { return }
        let late = sorted[sorted.count / 2]
        reportedMs = Double(streamDelay(speaker) ?? 0) / rate * 1000
        guard abs(late - reportedMs) >= 30 else { return }
        if setStreamDelay(speaker, frames: Int((late / 1000 * rate).rounded())) {
            reportedMs = late
            print("Ambient now tells macOS it plays \(ms(late)) late, so video here waits for it")
        } else {
            print("Ambient couldn't tell macOS it plays \(ms(late)) late")
        }
    }

    func summary(_ seconds: Double) -> String {
        locked(stats) {
            let sorted = lates.sorted()
            func at(_ share: Double) -> Double {
                sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * share))]
            }
            return "Over \(Int(seconds)) s, \(player.name) played it \(ms(at(0.5))) late at the median, "
                + "\(ms(at(0.95))) or less 95% of the time and \(ms(sorted.last ?? 0)) at most"
        }
    }

    // Recording starts once the player is listening, so what's recorded while ssh connects doesn't arrive in a burst.
    while playerReady.wait(timeout: .now() + 0.1) == .timedOut {
        guard ssh.isRunning else {
            _ = finished.wait(timeout: .now() + 1)
            fail("couldn't start the player on \(host) (\(ssh.terminationStatus))")
        }
    }
    guard AudioDeviceStart(loopback, recording) == noErr else { ssh.terminate(); fail("couldn't start the loopback") }
    locked(stats) { since = now() }
    print("Sending what plays to Ambient to \(host)\(udp ? " over UDP" : ""). Pick \"Ambient\" in Sound settings and "
          + "play something; ⌃C stops.")
    fflush(stdout)
    // Run by the app, it stops when the app does: its standard input closes then, even if the app crashed.
    var appGone = false
    if forApp {
        Thread {
            var byte: UInt8 = 0
            while read(0, &byte, 1) > 0 {}
            locked(stats) { appGone = true }
        }.start()
    }
    let started = Date()
    var lastReport = Date(), lastBytes = 0, lastDelay = Date()
    while ssh.isRunning {
        if let seconds, Date().timeIntervalSince(started) >= seconds { break }
        if locked(stats, { appGone }) { break }
        Thread.sleep(forTimeInterval: 0.1)
        if let speaker, Date().timeIntervalSince(lastDelay) >= 1 {
            reportDelay(to: speaker)
            lastDelay = Date()
        }
        let elapsed = Date().timeIntervalSince(lastReport)
        if elapsed >= 2 {
            let bytes = locked(stats) { sentBytes }
            let mbit = Double(bytes - lastBytes) * 8 / elapsed / 1e6
            print(report(mbit))
            fflush(stdout)
            if forApp {
                var fields: [String: Any] = locked(stats) {
                    let network = player.roundTripMs / 2
                    return ["lateMs": (hereMs + network + player.heldMs + player.outputMs).rounded(),
                            "networkMs": network.rounded(), "heldMs": player.heldMs.rounded(),
                            "outputMs": player.outputMs.rounded(), "missingMs": overUDP.missingMs.rounded(),
                            "mbit": (mbit * 10).rounded() / 10]
                }
                if speaker != nil { fields["videoWaitsMs"] = reportedMs.rounded() }
                tell("status", fields)
            }
            lastBytes = bytes
            lastReport = Date()
        }
    }
    let closedByUs = ssh.isRunning
    let streamed = Date().timeIntervalSince(started)
    AudioDeviceStop(loopback, recording)
    if let speaker { _ = setStreamDelay(speaker, frames: 0) } // it plays here again
    locked(lock) { stopping = true }
    ready.signal()
    _ = written.wait(timeout: .now() + 2) // then the player plays what it holds, and stops
    ssh.waitUntilExit()
    _ = finished.wait(timeout: .now() + 3)
    print(summary(streamed))
    guard closedByUs else { fail("the connection to \(host) closed (\(ssh.terminationStatus))") }
    exit(ssh.terminationStatus == 0 ? 0 : 1)
}

// MARK: - Play

/// What the player holds: filled from standard input, emptied by this Mac's speakers.
///
/// It starts once it holds `floor`, and again after it runs dry. It never skips sound that arrives late: after the
/// network stalls, the sound plays as late as the stall made it, so the next stall that long doesn't break it up. It
/// gets back down toward `goal`, the longest the network has stalled lately, by leaving out stretches of silence.
/// With `fixed` it works the old way instead, to compare: it holds `floor`, and skips a backlog down to it at once.
final class Held {
    let capacity = Int(rate * 2)
    let samples: UnsafeMutablePointer<Float>
    let lock = newLock()
    let margin = Int(0.02 * rate) // above `goal` before it shrinks
    var start = 0, count = 0
    var floor = 0, goal = 0, slack = 0
    var fixed = false, playing = false, ending = false, quiet = false
    var played = 0, gaps = 0, trims = 0, shrunk = 0 // shrunk: frames of silence left out

    init() {
        samples = .allocate(capacity: capacity * channels)
        samples.initialize(repeating: 0, count: capacity * channels)
    }

    /// Adds frames, and says how many were already waiting to play ahead of them.
    func push(_ data: UnsafeRawPointer, frames: Int) -> Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let ahead = count
        if count + frames > capacity { // full: drop the oldest
            let over = count + frames - capacity
            start = (start + over) % capacity
            count -= over
            trims += 1
        }
        var i = 0
        while i < frames {
            let at = (start + count + i) % capacity
            let piece = min(frames - i, capacity - at)
            UnsafeMutableRawPointer(samples + at * channels).copyMemory(from: data + i * bytesPerFrame,
                                                                        byteCount: piece * bytesPerFrame)
            i += piece
        }
        count += frames
        return ahead
    }

    /// Whether the next `frames` frames held are silence, at −60 dBFS or below.
    private func silent(_ frames: Int) -> Bool {
        for i in 0..<(frames * channels) where abs(samples[(start * channels + i) % (capacity * channels)]) > 1e-3 {
            return false
        }
        return true
    }

    /// Fills `out` for the speakers.
    func pull(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        var copied = 0
        os_unfair_lock_lock(lock)
        // After running dry it waits to hold as much as the stall it just saw, so a slow catch-up breaks once, not again.
        if !playing, count >= (fixed ? floor : max(floor, goal)) || (ending && count > 0) { playing = true }
        if playing, !ending, fixed, count > floor + slack {
            let skip = count - floor
            start = (start + skip) % capacity
            count -= skip
            trims += 1
        }
        if playing, !ending, !fixed {
            var dropped = 0
            while dropped < 4 * frames, count - frames > goal + margin, silent(frames) {
                start = (start + frames) % capacity
                count -= frames
                shrunk += frames
                dropped += frames
            }
        }
        if playing {
            copied = min(frames, count)
            var i = 0
            while i < copied {
                let piece = min(copied - i, capacity - start)
                if !quiet { (out + i * channels).update(from: samples + start * channels, count: piece * channels) }
                start = (start + piece) % capacity
                i += piece
            }
            count -= copied
            played += copied
            if copied < frames {
                playing = false
                if !ending { gaps += 1 }
            }
        }
        os_unfair_lock_unlock(lock)
        let silentFrom = quiet ? 0 : copied
        (out + silentFrom * channels).update(repeating: 0, count: (frames - silentFrom) * channels)
    }
}

let held = Held()

/// What the player holds over UDP: each frame in its place by sample time, so sound can come out of order, late, or not
/// at all. It plays `target` behind the quickest datagrams. One that comes later than that has missed its turn, and its
/// place plays as silence.
final class Placed {
    let capacity = Int(rate * 4)
    let samples: UnsafeMutablePointer<Float>
    let stamps: UnsafeMutablePointer<Int64> // the sample time of the frame each place holds
    let lock = newLock()
    var target: Int // how far ahead of their turn the quickest datagrams come: what it holds
    var quiet = false, ending = false, started = false
    var check: ToneCheck? // hears what plays, silence included
    let silence = UnsafeMutablePointer<Float>.allocate(capacity: channels)
    var playhead: Int64? // the sample time to play next
    var newest = Int64.min // where the latest sound to arrive ends
    var nudge = 0 // frames to skip (+) or play twice (−), one a callback, as the two Macs' clocks drift apart
    var hold = 0 // frames of silence to play before moving on, after stepping back
    var lower = 0, lowerSince: UInt64 = 0 // frames to leave out, to hold less: at a quiet moment, or after 10 s
    var played = 0, missing = 0, late = 0, resyncs = 0, raises = 0, lowers = 0

    init(target: Int) {
        self.target = target
        samples = .allocate(capacity: capacity * channels)
        samples.initialize(repeating: 0, count: capacity * channels)
        stamps = .allocate(capacity: capacity)
        stamps.initialize(repeating: -1, count: capacity)
        silence.initialize(repeating: 0, count: channels)
    }

    private func place(_ time: Int64) -> Int {
        let capacity = Int64(capacity)
        return Int((time % capacity + capacity) % capacity)
    }

    /// Puts a datagram's sound in its place. Says how many frames before its turn it came, counting silence still to
    /// play after a raise, and whether any of it came in time.
    func put(_ data: UnsafeRawPointer, at sampleTime: Int64, frames: Int) -> (ahead: Int64, inTime: Bool) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let end = sampleTime + Int64(frames)
        if let playhead, end - playhead > Int64(capacity) { // further ahead than it can hold: start again from here
            resyncs += 1
            self.playhead = nil
        }
        if playhead == nil { playhead = sampleTime - Int64(target) }
        let playhead = self.playhead!
        let ahead = sampleTime - playhead + Int64(hold)
        guard end > playhead else {
            late += 1
            return (ahead, false)
        }
        for i in 0..<frames where sampleTime + Int64(i) >= playhead {
            let at = place(sampleTime + Int64(i))
            (samples + at * channels).update(from: (data + i * bytesPerFrame).assumingMemoryBound(to: Float.self),
                                             count: channels)
            stamps[at] = sampleTime + Int64(i)
        }
        newest = max(newest, end)
        return (ahead, true)
    }

    /// Holds `frames` more from now on, by playing that much silence first.
    func raise(by frames: Int) {
        locked(lock) {
            target += frames
            hold += frames
            lower = 0
            raises += 1
        }
    }

    /// Holds `frames` less, by leaving out that much sound: at the next quiet moment, or after 10 s if none comes.
    func lower(by frames: Int) {
        locked(lock) {
            guard lower == 0 else { return }
            lower = frames
            lowerSince = now()
        }
    }

    /// Whether the `frames` from `time` on are silent, or not there.
    private func quiet(from time: Int64, frames: Int) -> Bool {
        for i in 0..<frames {
            let at = place(time + Int64(i))
            guard stamps[at] == time + Int64(i) else { continue }
            for c in 0..<channels where abs(samples[at * channels + c]) > 1e-3 { return false }
        }
        return true
    }

    /// Moves the playhead at once: forward skips sound, and back plays silence first. Either is one short break.
    func step(_ frames: Int, counted: Bool) {
        locked(lock) {
            if frames > 0 { playhead? += Int64(frames) } else { hold -= frames }
            nudge = 0
            if counted { resyncs += 1 }
        }
    }

    /// Fills `out` for the speakers, from the playhead on.
    func pull(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard var time = playhead else {
            out.update(repeating: 0, count: frames * channels)
            return
        }
        if nudge > 0 {
            time += 1
            nudge -= 1
        }
        if lower > 0, quiet(from: time, frames: lower) || now() &- lowerSince > 10_000_000_000 {
            time += Int64(lower)
            target -= lower
            lowers += 1
            lower = 0
        }
        for i in 0..<frames {
            let frame = out + i * channels
            if hold > 0 {
                hold -= 1
                frame.update(repeating: 0, count: channels)
                continue
            }
            let at = place(time)
            if stamps[at] == time {
                if quiet { frame.update(repeating: 0, count: channels) } else { frame.update(from: samples + at * channels, count: channels) }
                played += 1
                started = true
                check?.feed(samples + at * channels, frames: 1)
            } else {
                frame.update(repeating: 0, count: channels)
                if started, !ending { missing += 1 }
                if started { check?.feed(silence, frames: 1) }
            }
            if i == 0, nudge < 0 { nudge += 1 } else { time += 1 } // the next frame plays this one again
        }
        playhead = time
    }
}

var placed: Placed?
var debugging = false // --debug: the player says what it decides, once a second, on standard error

/// What came over UDP and what didn't: for asking again, for the answers, and for the summary at the end.
final class Arrivals {
    let lock = newLock()
    var next: UInt64? // the number after the highest so far
    var wanted: [UInt64: (turn: UInt64, asked: UInt64)] = [:] // missing, by number: when its turn comes, when asked
    var lost = 0, recovered = 0
    var needs: [Float] = [] // how long each datagram needed holding to be in time, in ms, once settled in

    init() { needs.reserveCapacity(400 * 900) }

    /// Notes a datagram that came `ahead` frames before its turn, and what it shows is missing. Each datagram before it
    /// is `udpFrames` earlier, so its turn is that much sooner, and one whose turn has passed is lost without asking.
    func note(_ number: UInt64, resent: Bool, ahead: Int64, inTime: Bool, at time: UInt64, needMs: Float?) {
        locked(lock) {
            guard let next else {
                self.next = number + 1
                return
            }
            if number >= next {
                let from = number - next > 2048 ? number - 2048 : next // after a long silence, only the last 2048
                lost += Int(from - next)
                for missing in from..<number {
                    let turn = ahead - Int64(number - missing) * Int64(udpFrames)
                    if turn > 0 { wanted[missing] = (time + UInt64(Double(turn) / rate * 1e9), 0) } else { lost += 1 }
                }
                self.next = number + 1
            } else if wanted.removeValue(forKey: number) != nil, resent, inTime {
                recovered += 1
            }
            if let needMs { needs.append(needMs) }
        }
    }

    /// What to ask for again: what's missing and wasn't asked for in the last 25 ms, as `nack` and ranges. What has
    /// missed its turn is lost.
    func due(at time: UInt64, asking: Bool) -> String? {
        locked(lock) {
            var numbers: [UInt64] = []
            for (number, when) in wanted {
                if time > when.turn {
                    wanted[number] = nil
                    lost += 1
                } else if asking, when.asked == 0 || time &- when.asked > 25_000_000 {
                    numbers.append(number)
                }
            }
            guard !numbers.isEmpty else { return nil }
            var text = "nack"
            for number in numbers.sorted() {
                if let last = text.split(separator: " ").last, last != "nack" {
                    let ends = last.split(separator: "-")
                    if let end = UInt64(ends.last!), end + 1 == number {
                        text = text.dropLast(last.count) + "\(ends.first!)-\(number)"
                        wanted[number]?.asked = time
                        continue
                    }
                }
                guard text.utf8.count < 460 else { break }
                text += " \(number)"
                wanted[number]?.asked = time
            }
            return text
        }
    }

    var lostSoFar: Int { locked(lock) { lost } }
    var recoveredSoFar: Int { locked(lock) { recovered } }
}

/// Reads datagrams into `placed` for as long as the player runs, answering the sender twice a second. Once a second it
/// checks how far ahead of their turn the quickest datagrams came, and keeps that at `target`. While settling in, it
/// moves there at once. After that, a small difference is the two Macs' clocks drifting apart, so it closes it a frame
/// at a time. A large one for 3 seconds is a new route, so it moves there at once, which is one short break. With
/// `adapting`, it also sets the hold: see the top of this file.
func hearUDP(_ fd: Int32, token: UInt64, placed: Placed, arrivals: Arrivals, resending: Bool, adapting: Bool) {
    let datagram = UnsafeMutableRawPointer.allocate(byteCount: 2048, alignment: 16)
    var timeout = timeval(tv_sec: 0, tv_usec: 10_000) // to ask again even while nothing comes
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var connected = false
    func ask() {
        guard connected, let line = arrivals.due(at: now(), asking: resending) else { return }
        _ = line.withCString { send(fd, $0, strlen($0), 0) }
    }
    let began = now()
    var lastEcho: UInt64 = 0, second: UInt64 = 0, quickest = Int64.min, off = 0
    // Datagrams come 128 frames apart, and the speakers take 512 or more at a time, so how far ahead the quickest come
    // moves in steps of 2.7 ms or more: within 3 ms is as close as it gets, or the playhead would be nudged to and fro.
    let tolerance = Int(0.04 * rate), closeEnough = Int(0.003 * rate)
    // How much later than the quickest the latest datagram came, each second of the last minute: what the hold covers.
    var latest: [Int] = [], latestThisSecond = Int.min, lastChange = began
    let margin = Int(0.02 * rate), least = Int(0.03 * rate), most = Int(rate)
    while true {
        var from = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, datagram, 2048, 0, $0, &length) }
        }
        if n < 0 {
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                ask()
                continue
            }
            return
        }
        guard n >= udpHeaderSize, datagram.load(as: UInt32.self) == udpMagic,
              datagram.load(fromByteOffset: 32, as: UInt64.self) == token else { continue }
        let count = datagram.load(fromByteOffset: 4, as: UInt32.self)
        let resent = count & 0x8000_0000 != 0, frames = Int(count & 0x7FFF_FFFF)
        guard frames <= udpFrames, n == udpHeaderSize + frames * bytesPerFrame else { continue }
        if !connected { connected = withSockaddr(&from) { connect(fd, $0, $1) } == 0 } // from now on, only the sender
        let sampleTime = datagram.load(fromByteOffset: 8, as: Int64.self)
        let sent = datagram.load(fromByteOffset: 24, as: UInt64.self)
        let (ahead, inTime) = placed.put(datagram + udpHeaderSize, at: sampleTime, frames: frames)
        let arrived = now()
        let settled = arrived &- began > 3_000_000_000
        let target = locked(placed.lock) { placed.target }
        let need = target - Int(ahead) // how much later than the quickest it came
        arrivals.note(datagram.load(fromByteOffset: 40, as: UInt64.self), resent: resent,
                      ahead: ahead, inTime: inTime, at: arrived,
                      needMs: settled && !resent ? Float(need) / Float(rate) * 1000 : nil)
        ask()
        guard !resent else { continue } // sent long ago: not a guide to the route, or to how late things are
        if settled {
            latestThisSecond = max(latestThisSecond, need)
            if adapting, need > target, need + margin <= most { // too late: hold enough for it from now on
                placed.raise(by: need + margin - target)
                lastChange = arrived
            }
        }

        if arrived / 1_000_000_000 != second {
            if debugging, quickest != Int64.min {
                let (playhead, newest, nudge, hold, played, missing) = locked(placed.lock) {
                    (placed.playhead ?? 0, placed.newest, placed.nudge, placed.hold, placed.played, placed.missing)
                }
                FileHandle.standardError.write(Data(("quickest \(quickest) error \(Int(quickest) - target) hold \(target) "
                    + "nudge \(nudge) hold \(hold) playhead \(playhead) newest \(newest) ahead-of-playhead "
                    + "\(newest - playhead) played \(played) missing \(missing) breaks \(placed.check?.breaks ?? [])\n").utf8))
            }
            if quickest != Int64.min {
                let error = Int(quickest) - target
                if !settled {
                    if abs(error) > closeEnough { placed.step(error, counted: false) }
                } else if abs(error) > tolerance {
                    off += 1
                    if off >= 3 {
                        placed.step(error, counted: true)
                        off = 0
                    }
                } else {
                    off = 0
                    let nudge = abs(error) > closeEnough ? max(-48, min(48, error)) : 0
                    locked(placed.lock) { placed.nudge = nudge }
                }
            }
            if settled, latestThisSecond != Int.min {
                latest.append(latestThisSecond)
                if latest.count > 60 { latest.removeFirst() }
                // Hold less, when the last minute shows it holds more than it needs: 200 ms at most at a time.
                if adapting, latest.count >= 15, arrived &- lastChange > 30_000_000_000, let highest = latest.max() {
                    let enough = min(most, max(least, highest + margin))
                    if enough < target - margin {
                        placed.lower(by: min(target - enough, Int(0.2 * rate)))
                        lastChange = arrived
                    }
                }
            }
            latestThisSecond = Int.min
            second = arrived / 1_000_000_000
            quickest = ahead
        } else {
            quickest = max(quickest, ahead)
        }

        if connected, arrived &- lastEcho > 500_000_000 {
            lastEcho = arrived
            let (missing, late, resyncs, hold, raises, lowers) = locked(placed.lock) {
                (placed.missing, placed.late, placed.resyncs, placed.target, placed.raises, placed.lowers)
            }
            let line = "uecho \(sent) \(String(format: "%.1f", Double(ahead) / rate * 1000)) "
                + "\(String(format: "%.1f", Double(missing) / rate * 1000)) \(arrivals.lostSoFar) \(late) \(resyncs) "
                + "\(arrivals.recoveredSoFar) \(String(format: "%.1f", Double(hold) / rate * 1000)) \(raises) \(lowers)"
            _ = line.withCString { send(fd, $0, strlen($0), 0) }
        }
    }
}

let render: AURenderCallback = { _, _, _, _, frames, data in
    guard let data, let out = UnsafeMutableAudioBufferListPointer(data).first?.mData?.assumingMemoryBound(to: Float.self)
    else { return noErr }
    if let placed { placed.pull(out, frames: Int(frames)) } else { held.pull(out, frames: Int(frames)) }
    return noErr
}

/// Checks a tone came through whole: a sine satisfies x[n] = 2cos(ω)·x[n-1] − x[n-2], so a lost, repeated or changed
/// sample breaks it. Its start and its end break it too, up to three times on each side.
final class ToneCheck {
    let hz: Double, twoCos: Double
    var last = [(0.0, 0.0), (0.0, 0.0)]
    var breaks = [0, 0]
    var frame = 0, first: Int?, lastHeard = 0

    init(hz: Double) {
        self.hz = hz
        twoCos = 2 * cos(2 * .pi * hz / rate)
    }

    func feed(_ data: UnsafeRawPointer, frames: Int) {
        for f in 0..<frames {
            for c in 0..<channels {
                let x = Double(data.load(fromByteOffset: (f * channels + c) * MemoryLayout<Float>.size, as: Float.self))
                let (x1, x2) = last[c]
                if max(abs(x), abs(x1), abs(x2)) > 1e-3, abs(x - twoCos * x1 + x2) > 1e-4 { breaks[c] += 1 }
                last[c] = (x, x1)
                if c == 0, abs(x) > 1e-3 {
                    first = first ?? frame
                    lastHeard = frame
                }
            }
            frame += 1
        }
    }

    var summary: String {
        let heard = first.map { Double(lastHeard - $0 + 1) / rate } ?? 0
        return String(format: "check: heard %.0f Hz for %.2f s, with %d and %d breaks in the left and right "
                      + "(up to 3 each are its start and end)", hz, heard, breaks[0], breaks[1])
    }
}

/// Claims this Mac's Now Playing for the sound from `source`, and sends each ⏯ back to the sender as `key WORD`. Its
/// targets run on the main queue. It can't see the other Mac's player paused or played some other way, so it shows
/// what was last pressed here: at worst, one press does nothing.
func passPlayPause(from source: String) {
    var playing = true
    func show() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: source, MPMediaItemPropertyArtist: "Ambient speaker",
                                 MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        center.playbackState = playing ? .playing : .paused
    }
    let commands = MPRemoteCommandCenter.shared()
    for (command, word) in [(commands.togglePlayPauseCommand, "toggle"), (commands.playCommand, "play"),
                            (commands.pauseCommand, "pause")] {
        command.isEnabled = true
        command.addTarget { _ in
            playing = word == "toggle" ? !playing : word == "play"
            show()
            say("key \(word)")
            return .success
        }
    }
    show()
}

func play() -> Never {
    let bufferMs = option("--buffer") ?? 150 // over Daily's Wi-Fi, 80 ran dry about once in 30 seconds; 150 never did
    let window = Int(option("--window") ?? 120)
    held.fixed = flag("--fixed")
    held.quiet = flag("--quiet")
    let check = option("--check").map(ToneCheck.init)
    let source = text("--from") ?? "Another Mac"
    let listen = text("--listen"), token = text("--token").flatMap { UInt64($0) } ?? 0
    debugging = flag("--debug")
    let resending = !flag("--no-resend")
    // Older senders asked for the check below; it's made always now.
    _ = flag("--only-if-allowed")
    noMoreArguments()
    // Sound from another Mac plays here only if this Mac's Ambient settings say it may, whatever the sender asks.
    if UserDefaults(suiteName: receiveSetting.domain)?.bool(forKey: receiveSetting.key) != true {
        say("refused")
        exit(0)
    }
    held.floor = Int(bufferMs / 1000 * rate)
    held.goal = held.floor
    held.slack = max(Int(0.04 * rate), held.floor / 2)

    // Over UDP: listen where the sender will send, on a port of the system's choosing, which the sender hears first.
    var udpSocket: Int32 = -1
    if let listen {
        udpSocket = socket(AF_INET, SOCK_DGRAM, 0)
        var size: Int32 = 4 << 20
        setsockopt(udpSocket, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        guard var address = inet(listen, 0), withSockaddr(&address, { bind(udpSocket, $0, $1) }) == 0 else {
            fail("couldn't listen on \(listen): \(String(cString: strerror(errno)))")
        }
        var bound = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(udpSocket, $0, &length) }
        }
        let made = Placed(target: held.floor)
        made.quiet = held.quiet
        made.check = check
        placed = made
        say("udp \(UInt16(bigEndian: bound.sin_port))")
    }

    var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                componentSubType: kAudioUnitSubType_DefaultOutput,
                                                componentManufacturer: kAudioUnitManufacturer_Apple,
                                                componentFlags: 0, componentFlagsMask: 0)
    var made: AudioUnit?
    guard let component = AudioComponentFindNext(nil, &description),
          AudioComponentInstanceNew(component, &made) == noErr, let unit = made else { fail("no default output") }
    var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                             mBytesPerPacket: UInt32(bytesPerFrame), mFramesPerPacket: 1,
                                             mBytesPerFrame: UInt32(bytesPerFrame), mChannelsPerFrame: UInt32(channels),
                                             mBitsPerChannel: 32, mReserved: 0)
    var callback = AURenderCallbackStruct(inputProc: render, inputProcRefCon: nil)
    guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format,
                               UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr,
          AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                               UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr,
          AudioUnitInitialize(unit) == noErr, AudioOutputUnitStart(unit) == noErr
    else { fail("couldn't open this Mac's speakers") }

    // How long the speakers take to play what we hand them: the device's latencies, its buffer, and any resampling.
    var output = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &output, &size)
    let outputScope = kAudioObjectPropertyScopeOutput
    var frames = number(output, kAudioDevicePropertyLatency, outputScope)
        + number(output, kAudioDevicePropertySafetyOffset, outputScope)
        + number(output, kAudioDevicePropertyBufferFrameSize)
    var place = address(kAudioDevicePropertyStreams, outputScope)
    var stream = AudioStreamID(0)
    size = UInt32(MemoryLayout<AudioStreamID>.size)
    if AudioObjectGetPropertyData(output, &place, 0, nil, &size, &stream) == noErr, size > 0 {
        frames += number(stream, kAudioStreamPropertyLatency)
    }
    var deviceRate = 0.0
    place = address(kAudioDevicePropertyNominalSampleRate)
    size = UInt32(MemoryLayout<Double>.size)
    AudioObjectGetPropertyData(output, &place, 0, nil, &size, &deviceRate)
    var resampling = 0.0
    size = UInt32(MemoryLayout<Double>.size)
    AudioUnitGetProperty(unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &resampling, &size)
    let outputMs = (deviceRate > 0 ? Double(frames) / deviceRate : 0) * 1000 + resampling * 1000
    say("ready \(Int(deviceRate)) \(String(format: "%.1f", outputMs)) \(name(output))")
    if !held.quiet { passPlayPause(from: source) }

    // Over UDP, the sound comes on a thread of its own, and the end comes as ssh's input closing.
    if let placed {
        let arrivals = Arrivals()
        Thread { hearUDP(udpSocket, token: token, placed: placed, arrivals: arrivals, resending: resending,
                            adapting: !held.fixed) }.start()
        Thread {
            let sink = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 16)
            while true {
                let n = read(0, sink, 4096)
                if n < 0, errno == EINTR { continue }
                if n <= 0 { break }
            }
            locked(placed.lock) { placed.ending = true }
            let deadline = Date().addingTimeInterval(1 + bufferMs / 1000)
            while locked(placed.lock, { (placed.playhead ?? .max) < placed.newest }), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            Thread.sleep(forTimeInterval: outputMs / 1000 + 0.05)
            AudioOutputUnitStop(unit)
            let (needs, lost, recovered) = locked(arrivals.lock) {
                (arrivals.needs.sorted(), arrivals.lost + arrivals.wanted.count, arrivals.recovered)
            }
            func at(_ share: Double) -> String {
                String(format: "%.0f", needs.isEmpty ? 0 : needs[min(needs.count - 1, Int(Double(needs.count - 1) * share))])
            }
            if let check = placed.check { say(check.summary) }
            let (played, missing, late, resyncs, hold, raises, lowers) = locked(placed.lock) {
                (placed.played, placed.missing, placed.late, placed.resyncs, placed.target, placed.raises, placed.lowers)
            }
            say("udone \(String(format: "%.2f", Double(played) / rate)) \(String(format: "%.0f", Double(missing) / rate * 1000)) "
                + "\(lost) \(late) \(resyncs) \(recovered) \(at(0.5)) \(at(0.9)) \(at(0.99)) \(at(0.999)) \(at(1)) "
                + "\(String(format: "%.0f", Double(hold) / rate * 1000)) \(raises) \(lowers)")
            exit(0)
        }.start()
        dispatchMain()
    }

    // The stream is read on a thread of its own, and the main queue is left for ⏯.
    Thread {
        receive(window: window, check: check)
        // The sender has stopped: play what's held, and let the speakers finish before closing them.
        locked(held.lock) { held.ending = true }
        let deadline = Date().addingTimeInterval(1 + bufferMs / 1000)
        while locked(held.lock, { held.count }) > 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        Thread.sleep(forTimeInterval: outputMs / 1000 + 0.05)
        AudioOutputUnitStop(unit)
        let (played, gaps, trims, shrunk) = locked(held.lock) { (held.played, held.gaps, held.trims, held.shrunk) }
        say("done \(String(format: "%.2f", Double(played) / rate)) \(gaps) \(trims) \(String(format: "%.2f", Double(shrunk) / rate))")
        exit(0)
    }.start()
    dispatchMain()
}

/// Reads packets from standard input into `held` until the sender stops, answering with how much is held.
func receive(window: Int, check: ToneCheck?) {
    let capacity = 1 << 20
    let input = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
    var have = 0, lastEcho: UInt64 = 0
    var lastSampleTime: Int64?, lastFrames = 0, streamGaps = 0
    // How late each packet arrives, against when it played on the other Mac: the two clocks' offset plus the trip. Its
    // spread over the last `window` seconds, kept per second, is the longest the network has stalled lately.
    var delays: [(low: Int64, high: Int64)] = []
    var second: UInt64 = 0
    reading: while true {
        let n = read(0, input + have, capacity - have)
        if n < 0, errno == EINTR { continue }
        if n <= 0 { break }
        have += n
        var at = 0
        while have - at >= headerSize {
            let packet = input + at
            let frames = Int(packet.load(fromByteOffset: 4, as: UInt32.self))
            guard packet.load(as: UInt32.self) == magic, frames <= maxFrames else { say("the stream is garbled"); break reading }
            let size = headerSize + frames * bytesPerFrame
            guard have - at >= size else { break }
            let sampleTime = packet.load(fromByteOffset: 8, as: Int64.self)
            let playedThere = packet.load(fromByteOffset: 16, as: UInt64.self)
            let sent = packet.load(fromByteOffset: 24, as: UInt64.self)
            if let lastSampleTime, sampleTime != lastSampleTime + Int64(lastFrames) { streamGaps += 1 }
            lastSampleTime = sampleTime
            lastFrames = frames
            check?.feed(packet + headerSize, frames: frames)
            let ahead = held.push(packet + headerSize, frames: frames)

            let arrived = now()
            let delay = Int64(bitPattern: arrived &- playedThere)
            if arrived / 1_000_000_000 != second || delays.isEmpty {
                second = arrived / 1_000_000_000
                delays.append((delay, delay))
                if delays.count > window { delays.removeFirst() }
            } else {
                delays[delays.count - 1].low = min(delays[delays.count - 1].low, delay)
                delays[delays.count - 1].high = max(delays[delays.count - 1].high, delay)
            }
            var low = Int64.max, high = Int64.min // every packet, so a stall's size is known as its sound arrives
            for bucket in delays {
                low = min(low, bucket.low)
                high = max(high, bucket.high)
            }
            let goal = min(Int(rate * 1.5), max(held.floor, Int(Double(high - low) / 1e9 * rate)))
            locked(held.lock) { held.goal = goal }

            if arrived &- lastEcho > 500_000_000 {
                lastEcho = arrived
                let (gaps, trims, goal, shrunk) = locked(held.lock) { (held.gaps, held.trims, held.goal, held.shrunk) }
                say("echo \(sent) \(String(format: "%.1f", Double(ahead) / rate * 1000)) \(gaps) \(trims) "
                    + "\(String(format: "%.1f", Double(goal) / rate * 1000)) \(String(format: "%.2f", Double(shrunk) / rate))")
            }
            at += size
        }
        memmove(input, input + at, have - at)
        have -= at
    }
    if let check { say(check.summary + ", and \(streamGaps) gaps in the stream") }
}

// MARK: - Tone

func tone() -> Never {
    let seconds = option("--seconds") ?? 5
    let hz = option("--hz") ?? 997
    noMoreArguments()
    guard let speaker = device(uid: speakerUID) else {
        fail("Core Audio has no Ambient speaker. Install it: scripts/install-speaker.sh")
    }
    let total = Int(seconds * rate)
    var at = 0
    var playing: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(&playing, speaker, nil) { _, _, _, output, _ in
        guard let buffer = UnsafeMutableAudioBufferListPointer(output).first,
              let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let count = Int(buffer.mNumberChannels)
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(count, 1)
        for f in 0..<frames {
            let value: Float = at + f < total ? 0.25 * Float(sin(2 * .pi * hz * Double(at + f) / rate)) : 0
            for c in 0..<count { data[f * count + c] = value }
        }
        at += frames
    }
    guard status == noErr, let playing, AudioDeviceStart(speaker, playing) == noErr else {
        fail("couldn't play to the Ambient speaker")
    }
    Thread.sleep(forTimeInterval: seconds + 0.2)
    AudioDeviceStop(speaker, playing)
    print(String(format: "Played %.0f Hz for %.1f s to the Ambient speaker", hz, seconds))
    exit(0)
}

switch mode {
case "send" where !args.isEmpty: send(to: args.removeFirst())
case "play": play()
case "tone": tone()
default: fail("usage: speaker-pipe send HOST [--seconds N] [--buffer MS] [--quiet] [--check HZ] | play | tone")
}
