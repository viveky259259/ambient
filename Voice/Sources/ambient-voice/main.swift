import AmbientCore
import Foundation
import KokoroSwift
import MLX

// ambient-voice <pack folder>
//
// Reads VoiceWire requests on stdin, one JSON line each, and answers each on stdout with a header line and float32
// PCM frames. Loads the model once. Exits when stdin closes.

struct HelperError: Error, CustomStringConvertible {
    let description: String
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: ambient-voice <pack folder>\n".utf8))
    exit(64)
}
// The protocol gets its own copy of stdout, and fd 1 is pointed at stderr, so a print() anywhere in the libraries
// lands in the log instead of corrupting the audio stream.
let protocolFD = dup(STDOUT_FILENO)
guard protocolFD >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { exit(71) }
let out = FileHandle(fileDescriptor: protocolFD, closeOnDealloc: true)
let pack = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let tts = KokoroTTS(modelPath: pack.appendingPathComponent("kokoro-v1_0.safetensors"))
var voices: [String: MLXArray] = [:]

/// Top-level code runs on the main actor, and so does this, since it caches into the top-level `voices`.
@MainActor func voice(_ id: String) throws -> MLXArray {
    if let v = voices[id] { return v }
    guard id.range(of: "^[a-z]{2}_[a-z]{1,20}$", options: .regularExpression) != nil else {
        throw HelperError(description: "unknown voice \(id)")
    }
    let arrays = try MLX.loadArrays(url: pack.appendingPathComponent("voices/\(id).safetensors"))
    guard let v = arrays.values.first else { throw HelperError(description: "voice \(id) is empty") }
    voices[id] = v
    return v
}

while let line = readLine(strippingNewline: true) {
    guard let request = VoiceWire.request(from: Data(line.utf8)) else { continue }
    do {
        let language: Language = request.voice.hasPrefix("b") ? .enGB : .enUS
        let (samples, _) = try tts.generateAudio(voice: try voice(request.voice), language: language,
                                                 text: request.text, speed: Float(request.speed))
        out.write(VoiceWire.line(VoiceWire.Header(id: request.id, sampleRate: KokoroTTS.Constants.samplingRate)))
        var i = 0
        while i < samples.count {
            let end = min(i + KokoroTTS.Constants.samplingRate, samples.count)
            out.write(VoiceWire.frame(Array(samples[i..<end])))
            i = end
        }
        out.write(VoiceWire.end)
    } catch {
        out.write(VoiceWire.line(VoiceWire.Header(id: request.id, error: "\(error)")))
    }
}
