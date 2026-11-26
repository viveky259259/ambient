// Checks the installed Ambient speaker: that macOS lists it and hides its loopback, and that a tone played to it comes
// back out of the loopback exactly, frame for frame. It plays straight to the speaker, so the Mac's own output doesn't
// change, and it drives both devices with Core Audio IOProcs, so nothing converts the sound on the way. (AVAudioEngine's
// input node can't be pointed at the loopback on a Mac with no default input: it keeps a made-up 44.1 kHz and records
// nothing.)
//
//   swift scripts/speaker-check.swift
//
// Recording needs the microphone permission, so run it from an app that has it or can ask for it.
import AVFoundation // for the microphone permission only
import CoreAudio
import Foundation

let speakerUID = "com.viveky259259.Ambient.speaker"
let loopbackUID = "com.viveky259259.Ambient.speaker.loopback"
let rate = 48_000.0
let tones = [997.0, 1499.0] // left, right
let amplitude: Float = 0.5
let toneFrames = Int(rate * 2)
let silenceFrames = Int(rate * 0.2) // after the tone, which should come back as silence too

var failed = false
func check(_ ok: Bool, _ message: String) {
    print(ok ? "ok    \(message)" : "FAIL  \(message)")
    if !ok { failed = true }
}

func finish() -> Never {
    print(failed ? "\nThe Ambient speaker isn't working yet." : "\nThe Ambient speaker works.")
    exit(failed ? 1 : 0)
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

let system = AudioObjectID(kAudioObjectSystemObject)

func device(uid: String) -> AudioObjectID? {
    var place = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var uid = uid as CFString
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(system, &place, UInt32(MemoryLayout<CFString>.size), &uid, &size, &id)
    return status == noErr && id != kAudioObjectUnknown ? id : nil
}

func listedDevices() -> [AudioObjectID] {
    var place = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &place, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &place, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func name(_ id: AudioObjectID) -> String {
    var place = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &place, 0, nil, &size, &name) == noErr, let name else { return "?" }
    return name.takeRetainedValue() as String
}

func volume(_ id: AudioObjectID) -> Float32? {
    var place = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput)
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(id, &place, 0, nil, &size, &value) == noErr ? value : nil
}

func muted(_ id: AudioObjectID) -> Bool {
    var place = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &place, 0, nil, &size, &value) == noErr && value != 0
}

func format(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> AudioStreamBasicDescription? {
    var place = address(kAudioDevicePropertyStreamFormat, scope)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    return AudioObjectGetPropertyData(id, &place, 0, nil, &size, &format) == noErr ? format : nil
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

/// What the speaker plays on `channel`, `frame` frames into the tone: silence before and after it.
func tone(_ channel: Int, _ frame: Int) -> Float {
    guard channel < tones.count, (0..<toneFrames).contains(frame) else { return 0 }
    return amplitude * Float(sin(2 * .pi * tones[channel] * Double(frame) / rate))
}

// MARK: - Listed

guard let speaker = device(uid: speakerUID) else {
    check(false, "Core Audio has no Ambient speaker. Install it: scripts/install-speaker.sh")
    finish()
}
let listed = listedDevices()
check(listed.contains(speaker) && name(speaker) == "Ambient", "Sound settings lists \"\(name(speaker))\"")
guard let loopback = device(uid: loopbackUID) else {
    check(false, "the Ambient speaker has no loopback")
    finish()
}
check(!listed.contains(loopback), "its loopback is hidden")
let recording = format(loopback, kAudioObjectPropertyScopeInput)
check(recording?.mSampleRate == rate && recording?.mChannelsPerFrame == 2,
      "the loopback records at \(Int(recording?.mSampleRate ?? 0)) Hz in \(recording?.mChannelsPerFrame ?? 0) channels")
let level = volume(speaker) ?? 1
let gain: Float = muted(speaker) ? 0 : level * level
print("      its volume is \(String(format: "%.2f", level))\(muted(speaker) ? ", muted" : "")")
guard gain > 0.01 else {
    check(false, "Ambient is muted or turned all the way down: turn it up in Sound settings and run this again")
    finish()
}

// MARK: - Played and recorded

guard microphoneAllowed() else {
    check(false, "this app can't record: allow it in System Settings › Privacy & Security › Microphone")
    finish()
}

// Both devices keep one timeline, so the frame the loopback records at sample time t is the one the speaker played at t.
let lock = NSLock()
var toneStart: Int64? // the speaker's sample time for the tone's first frame
var recordStart: Int64? // the loopback's sample time for the first frame it recorded
var skips = 0 // times the loopback's sample time jumped
var recordEnd: Int64 = 0
let capacity = Int(rate * 5)
let heard = (0..<2).map { _ in
    let channel = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
    channel.initialize(repeating: .nan, count: capacity) // never written stays NaN, so a lost frame can't pass
    return channel
}

var playing: AudioDeviceIOProcID?
var status = AudioDeviceCreateIOProcIDWithBlock(&playing, speaker, nil) { _, _, _, output, time in
    lock.lock()
    defer { lock.unlock() }
    let now = Int64(time.pointee.mSampleTime)
    let start = toneStart ?? now
    toneStart = start
    var channel = 0
    for buffer in UnsafeMutableAudioBufferListPointer(output) {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let channels = Int(buffer.mNumberChannels)
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(channels, 1)
        for f in 0..<frames {
            for c in 0..<channels { data[f * channels + c] = tone(channel + c, Int(now - start) + f) }
        }
        channel += channels
    }
}
guard status == noErr, let playing else {
    check(false, "couldn't play to the Ambient speaker: \(status)")
    finish()
}

var recorder: AudioDeviceIOProcID?
status = AudioDeviceCreateIOProcIDWithBlock(&recorder, loopback, nil) { _, input, time, _, _ in
    lock.lock()
    defer { lock.unlock() }
    let now = Int64(time.pointee.mSampleTime)
    let start = recordStart ?? now
    if recordStart != nil, now != recordEnd { skips += 1 }
    recordStart = start
    var channel = 0
    var frames = 0
    for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let channels = Int(buffer.mNumberChannels)
        frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(channels, 1)
        for f in 0..<frames {
            let i = Int(now - start) + f
            guard i < capacity else { break }
            for c in 0..<channels where channel + c < 2 { heard[channel + c][i] = data[f * channels + c] }
        }
        channel += channels
    }
    recordEnd = now + Int64(frames)
}
guard status == noErr, let recorder else {
    check(false, "couldn't record from the loopback: \(status)")
    finish()
}

let recordingStarted = AudioDeviceStart(loopback, recorder)
let playingStarted = AudioDeviceStart(speaker, playing)
guard recordingStarted == noErr, playingStarted == noErr else {
    check(false, "couldn't start recording (\(recordingStarted)) and playing (\(playingStarted))")
    finish()
}
RunLoop.current.run(until: Date().addingTimeInterval(Double(toneFrames + silenceFrames) / rate + 0.5))
AudioDeviceStop(speaker, playing)
AudioDeviceStop(loopback, recorder)

// MARK: - Heard

lock.lock()
defer { lock.unlock() }
guard let toneStart, let recordStart else {
    check(false, toneStart == nil ? "the speaker never asked for sound" : "the loopback never recorded")
    finish()
}
check(skips == 0, "the loopback kept time with the speaker" + (skips == 0 ? "" : ": its clock jumped \(skips) times"))
let first = Int(toneStart - recordStart)
let span = toneFrames + silenceFrames
guard first >= 0, first + span <= Int(recordEnd - recordStart) else {
    check(false, "the loopback recorded \(Int(recordEnd - recordStart)) frames, which don't cover the tone")
    finish()
}
for c in 0..<2 {
    let side = c == 0 ? "left" : "right"
    var lost = 0, wrong = 0, worst: Float = 0, firstWrong: Int?
    for k in 0..<span {
        let got = heard[c][first + k]
        if got.isNaN { lost += 1; continue }
        let error = abs(got - tone(c, k) * gain)
        worst = max(worst, error)
        if error > 1e-6 { wrong += 1; firstWrong = firstWrong ?? k }
    }
    check(lost == 0, "\(side): heard all \(span) frames" + (lost == 0 ? "" : ", but lost \(lost)"))
    check(wrong == 0, "\(side): each came back as the \(Int(tones[c])) Hz tone played, then silence"
          + (wrong == 0 ? "" : ", but \(wrong) didn't, from frame \(firstWrong!) (worst \(worst) off). "
             + "Is something else playing to Ambient?"))
}
finish()
