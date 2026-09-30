import AmbientCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Performance: what Ambient costs this Mac, over the last hour or day, and a report to share by hand.
struct PerformancePane: View {
    @ObservedObject var monitor: PerfMonitor
    @State private var window: Window = .hour
    @State private var copied = false

    enum Window: String, CaseIterable, Identifiable {
        case hour = "Last hour", day = "Last 24 hours"
        var id: Self { self }
        var seconds: TimeInterval { self == .hour ? 3_600 : 86_400 }
    }

    var body: some View {
        let _ = monitor.revision
        let s = monitor.summary(over: window.seconds)
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .performance)
            Picker("Period", selection: $window) {
                ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            SettingsSection(header: "Ambient") {
                value("CPU", s.cpuPeak == 0 ? "Measuring…" : "\(one(s.cpuAverage))% average · \(one(s.cpuPeak))% peak")
                SettingsDivider()
                value("Memory", s.memoryPeakMB == 0 ? "Measuring…" : "\(mb(s.memoryNowMB)) now · \(mb(s.memoryPeakMB)) peak")
            }
            SettingsSection(header: "Drawing",
                            footer: "Time to draw each frame. A slow frame missed a 60 fps display's budget of 16.7 ms.") {
                frames("Living wallpaper", s.scene)
                SettingsDivider()
                frames("Notch effect", s.effect)
            }
            SettingsSection(header: "Agents", footer: "From the moment a hook sends an event to the moment Ambient has it.") {
                value("Hook events", s.hooks.events == 0 ? "None yet"
                      : "\(s.hooks.events) · \(ms(s.hooks.medianMs)) median · \(ms(s.hooks.p95Ms)) p95")
            }
            SettingsSection(footer: "Measured on this Mac and kept in memory while Ambient runs; it starts over when Ambient quits. Nothing is sent anywhere. To share it, copy or save a report yourself.") {
                SettingsRow(title: "Report") {
                    HStack(spacing: Theme.Space.sm) {
                        Button(copied ? "Copied" : "Copy report", action: copy).buttonStyle(.pill)
                        Button("Save report…", action: save).buttonStyle(.pill)
                    }
                }
            }
        }
    }

    private func value(_ title: String, _ text: String) -> some View {
        SettingsRow(title: title) {
            Text(text).font(Theme.Fonts.row).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func frames(_ title: String, _ f: PerfLog.Frames) -> some View {
        value(title, f.frames == 0 ? "No frames drawn"
              : "\(f.frames) frames · \(String(format: "%.1f", f.averageMs)) ms average · \(Int((f.slowShare * 100).rounded()))% slow")
    }

    private func one(_ x: Double) -> String { String(format: "%.1f", x) }
    private func mb(_ x: Double) -> String { "\(Int(x.rounded())) MB" }
    private func ms(_ x: Double) -> String { "\(Int(x.rounded())) ms" }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(monitor.report(), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func save() {
        let panel = NSSavePanel()
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Ambient performance \(day).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let report = monitor.report()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
