import AmbientCore
import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandViewModel

    private var size: CGSize { model.currentSize }
    private var expandedLike: Bool {
        switch model.presentation {
        case .bloom, .expanded: true
        default: false
        }
    }

    var body: some View {
        let shape = NotchShape(topRadius: expandedLike ? 10 : 6, bottomRadius: expandedLike ? 22 : 10)
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(expandedLike ? 0.45 : 0), radius: 18, y: 8)
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .opacity(!model.geometry.hasNotch && model.presentation == .hidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.presentation)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.sessions.count)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.presentation {
        case .hidden:
            Color.clear
        case .collapsed:
            wings
        case .bloom:
            VStack(spacing: 0) {
                Color.clear.frame(height: model.geometry.notchHeight)
                if let s = model.bloomSession { BloomCard(session: s).onTapGesture { model.onOpen(s) } }
            }
            .transition(.opacity)
        case .expanded:
            VStack(spacing: 0) {
                Color.clear.frame(height: model.geometry.notchHeight)
                ExpandedList(model: model)
            }
            .transition(.opacity)
        }
    }

    /// The glyph and label that flank the notch.
    private var wings: some View {
        HStack(spacing: 0) {
            if let s = model.primary {
                StateGlyph(mood: s.mood, color: s.moodTint, size: 13)
                    .frame(width: IslandViewModel.wing + 6)
                Spacer(minLength: model.geometry.notchWidth - 12)
                WingLabel(primary: s, active: model.sessions.filter { $0.mood != .idle })
                    .frame(width: IslandViewModel.wing + 6)
            } else {
                Spacer()
            }
        }
        .frame(height: model.geometry.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture { if let s = model.primary { model.onOpen(s) } }
    }
}

/// Right wing: with one active session, how long it has been at it (or what it needs);
/// with several, a dot per session in its color.
private struct WingLabel: View {
    let primary: Session
    let active: [Session]

    var body: some View {
        if active.count > 1 {
            HStack(spacing: 4) {
                ForEach(active.prefix(4)) { s in
                    Circle().fill(s.moodTint.color).frame(width: 6, height: 6)
                }
            }
        } else {
            Group {
                switch primary.mood {
                case .waiting: Image(systemName: "hand.raised.fill")
                case .error: Image(systemName: "exclamationmark.triangle.fill")
                case .working, .idle, .done:
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(compact(primary.elapsed(now: ctx.date) ?? 0)).monospacedDigit()
                    }
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(primary.moodTint.color)
        }
    }

    private func compact(_ t: TimeInterval) -> String {
        t >= 3_600 ? "\(Int(t / 3_600))h" : Describe.duration(t)
    }
}

private struct AgentTag: View {
    let agent: AgentKind

    var body: some View {
        Text(agent.displayName.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Palette.agent(agent).color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.agent(agent).color.opacity(0.16)))
    }
}

/// The card that drops out of the notch when something happens.
private struct BloomCard: View {
    let session: Session

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StateGlyph(mood: session.activity.rawMood, color: session.tint, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Describe.title(session))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    AgentTag(agent: session.agent)
                }
                Text(Describe.activity(session.activity))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let e = session.elapsed(now: Date()) {
                    Text(Describe.duration(e)).font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                if let app = HostActivator.appName(for: session.host) {
                    Text("Open \(app)").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(session.tint.color.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct ExpandedList: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            if model.listed.isEmpty {
                Text("No agent sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            ForEach(model.listed) { s in
                SessionRow(session: s) { model.onOpen(s) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                FooterButton(title: model.quiet ? "Resume alerts" : "Quiet 1h",
                             symbol: model.quiet ? "bell" : "bell.slash", action: model.onToggleQuiet)
                FooterButton(title: "Mark all seen", symbol: "checkmark.circle", action: model.onAcknowledgeAll)
                Spacer()
                FooterButton(title: "Settings", symbol: "gearshape", action: model.onSettings)
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
        }
        .padding(.top, 8)
    }
}

private struct SessionRow: View {
    let session: Session
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                StateGlyph(mood: session.activity.rawMood, color: session.tint, size: 15)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Describe.title(session)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        AgentTag(agent: session.agent)
                        if session.subagents > 0 {
                            Text("+\(session.subagents) agents").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Text(Describe.activity(session.activity))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(session.elapsed(now: ctx.date).map(Describe.duration) ?? "")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(hovered ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .onHover { hovered = $0 }
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
