import AmbientCore
import AppKit
import SwiftUI

/// Asked once, the first time the shortcut is used: which voice reads aloud.
final class VoiceChooser {
    private let prefs: Preferences
    private let voicePack: VoicePackInstaller
    private let speech: SpeechController
    private var window: NSWindow?
    private var completion: ((Bool) -> Void)?

    init(prefs: Preferences, voicePack: VoicePackInstaller, speech: SpeechController) {
        self.prefs = prefs
        self.voicePack = voicePack
        self.speech = speech
    }

    func show(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        if window == nil {
            let view = VoiceChooserView(prefs: prefs, voicePack: voicePack,
                                        onPreview: { [weak self] in self?.speech.preview($0) },
                                        onPlay: { [weak self] kind in self?.finish(kind) },
                                        onCancel: { [weak self] in self?.finish(nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Choose a Voice"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                   queue: .main) { [weak self] _ in
                self?.speech.stop()
                self?.completion?(false)
                self?.completion = nil
            }
            self.window = window
        }
        voicePack.refresh()
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(_ kind: SpeechEngineKind?) {
        if let kind { prefs.speechEngine = kind.rawValue }
        let done = completion
        completion = nil
        window?.close()
        done?(kind != nil)
    }
}

private struct VoiceChooserView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var voicePack: VoicePackInstaller
    let onPreview: (SpeechEngineKind) -> Void
    let onPlay: (SpeechEngineKind) -> Void
    let onCancel: () -> Void

    @State private var kind: SpeechEngineKind = .mac
    @State private var apiKey = ""
    @State private var loadedKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How should Ambient read aloud?").font(.title2.weight(.semibold))
            Picker("Voice", selection: $kind) {
                ForEach(SpeechEngineKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            EngineSection(kind: kind, prefs: prefs, voicePack: voicePack, apiKey: $apiKey, loadedKey: $loadedKey)
                .frame(minHeight: 120, alignment: .topLeading)
            HStack {
                Button("Preview") {
                    EngineSection.saveKey(apiKey, loaded: $loadedKey, prefs: prefs)
                    onPreview(kind)
                }
                .disabled(!ready)
                Spacer()
                Text("You can change this in Settings › Voice.").font(.caption).foregroundStyle(.secondary)
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Play") {
                    EngineSection.saveKey(apiKey, loaded: $loadedKey, prefs: prefs)
                    onPlay(kind)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { EngineSection.loadKey(prefs: prefs, into: $apiKey, loaded: $loadedKey) }
    }

    private var ready: Bool { EngineSection.ready(kind, prefs: prefs, voicePack: voicePack, apiKey: apiKey) }
}
