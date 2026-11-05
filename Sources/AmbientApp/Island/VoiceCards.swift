import AmbientCore
import SwiftUI

/// Under the notch: a voice being recorded here, one that just arrived from another Mac, or a short note about either.
struct VoiceCard: View {
    @ObservedObject var voice: VoiceSyncController

    var body: some View {
        if let outgoing = voice.outgoing {
            RecordingCard(outgoing: outgoing, level: voice.level, onCancel: voice.cancel, onSend: voice.send)
        } else if let arrival = voice.arrival {
            ArrivalCard(arrival: arrival, playing: voice.playing == arrival.record.id, copied: voice.copied,
                        onPlay: { voice.togglePlay(arrival.record) }, onCopyText: { voice.copyText(arrival.record) },
                        onCopyAudio: { voice.copyAudio(arrival.record) }, onDismiss: voice.dismissArrival)
        } else if let notice = voice.notice {
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(.white).accessibilityHidden(true)
                Text(notice)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    /// How far the card reaches below the notch.
    static func height(for voice: VoiceSyncController) -> CGFloat {
        if voice.outgoing != nil { return 66 }
        if let arrival = voice.arrival { return arrival.record.text == nil ? 84 : 116 }
        return 52
    }
}

/// While another Mac records for this one: a moving waveform and how long it's been going. There's nothing to answer.
struct VoiceIncomingWings: View {
    let incoming: VoiceSyncController.Incoming
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.waiting.color)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(width: IslandViewModel.wing + 6)
            Spacer(minLength: notchWidth - 12)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(VoiceFormat.clock(ctx.date.timeIntervalSince(incoming.since)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.waiting.color)
            }
            .frame(width: IslandViewModel.wing + 6)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(incoming.from.label) is recording a voice for you"))
    }
}

/// Recording here: where it's going, how long, the level, the words so far, and Cancel or Send.
private struct RecordingCard: View {
    let outgoing: VoiceSyncController.Outgoing
    let level: Float
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Palette.error.color).frame(width: 8, height: 8)
                    .opacity(outgoing.sending ? 0.4 : 1)
                    .accessibilityHidden(true)
                Text(verbatim: outgoing.sending ? "Sending to \(outgoing.destination.label)…" : "For \(outgoing.destination.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(VoiceFormat.clock(ctx.date.timeIntervalSince(outgoing.startedAt)))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                LevelMeter(level: outgoing.sending ? 0 : level)
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("Cancel the voice")
                CardButton(title: "Send", prominent: true, action: onSend)
            }
            .disabled(outgoing.stage != .recording)
            Text(outgoing.text.isEmpty ? "Listening…" : outgoing.text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(outgoing.text.isEmpty ? 0.45 : 0.75))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A voice from another Mac: what was said, and a minute to copy it.
private struct ArrivalCard: View {
    let arrival: VoiceSyncController.Arrival
    let playing: Bool
    let copied: VoiceSyncController.Copied?
    let onPlay: () -> Void
    let onCopyText: () -> Void
    let onCopyAudio: () -> Void
    let onDismiss: () -> Void

    private var record: VoiceRecord { arrival.record }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.waiting.color)
                    .accessibilityHidden(true)
                Text(verbatim: "Voice from \(record.peer.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(VoiceFormat.clock(record.seconds))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(max(0, Int(arrival.until.timeIntervalSince(ctx.date).rounded(.up))))s")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityLabel("Dismiss")
            }
            // Plain text from another Mac: never a link, never Markdown.
            if let text = record.text {
                Text(verbatim: text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                Spacer()
                CardButton(title: copied == .audio(record.id) ? "Copied" : "Copy Audio", prominent: record.text == nil,
                           action: onCopyAudio)
                if record.text != nil {
                    CardButton(title: copied == .text(record.id) ? "Copied" : "Copy Text", prominent: true, action: onCopyText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum VoiceFormat {
    /// 0:07, 1:42, 12:05.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
