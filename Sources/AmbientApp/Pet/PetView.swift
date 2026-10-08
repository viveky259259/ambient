import AmbientCore
import SwiftUI

/// Everything in the pet's panel: the pet, its speech bubble or session list, and click bursts.
struct PetView: View {
    @ObservedObject var model: PetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let space = "pet"

    var body: some View {
        if model.visible { panel }
    }

    private var panel: some View {
        let pet = model.petRect
        return ZStack(alignment: .topLeading) {
            if let rect = model.contentRect {
                content
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    // Each kind of content is its own view, so switching removes one and adds the other
                    // rather than stretching the bubble into the list.
                    .id(model.contentKind)
                    .transition(swap)
            }
            VStack(spacing: 0) {
                PetFigure(species: model.species, pose: model.pose, tint: model.tint, waiting: model.waiting,
                          reaction: model.reaction, reactionCount: model.reactionCount)
                PetPips(pips: model.pips)
                    .frame(height: PetViewModel.pipStrip)
            }
                .frame(width: pet.width, height: pet.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.onDrag(.changed) }
                    .onEnded { _ in model.onDrag(.ended) })
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(model.peekPinned ? "Hides your agent sessions" : "Shows all your agent sessions")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.tapPet() }
                .accessibilityAction(named: "Show sessions and actions") { model.onShowList() }
                .offset(x: pet.minX, y: pet.minY)
            PetBurstLayer(bursts: model.bursts)
        }
        .frame(width: PetViewModel.panelSize.width, height: PetViewModel.panelSize.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .animation(Self.motion(opening: model.expanded), value: model.expanded)
        .animation(Self.motion(opening: model.peekPinned), value: model.peekPinned)
        .animation(Self.motion(opening: true), value: model.primary?.id)
        .environment(\.colorScheme, .dark)
    }

    /// Opening and closing the bubble stays quiet: a short ease with no overshoot, and closing faster than opening,
    /// so hovering past the pet never makes a show of it.
    private static func motion(opening: Bool) -> Animation {
        opening ? .easeOut(duration: 0.18) : .easeIn(duration: 0.12)
    }

    /// The old content fades out quickly; the new one fades in just after, drifting 4 pt from the pet (only fading
    /// with Reduce Motion).
    private var swap: AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : (model.opensUp ? 4 : -4)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: drift)).animation(.easeOut(duration: 0.18).delay(0.07)),
            removal: .opacity.animation(.easeIn(duration: 0.1)))
    }

    @ViewBuilder private var content: some View {
        let shape = BubbleShape(tailX: model.tailX, tail: PetViewModel.tail, tailOnTop: !model.opensUp,
                                radius: model.expanded ? 16 : 14)
        Group {
            if model.expanded {
                PetSessionList(model: model)
            } else if model.peekPinned {
                PetPeekList(model: model)
            } else if let s = model.primary {
                PetBubble(session: s, badge: model.badge, urgentBadge: model.badge?.hasSuffix("needs you") == true)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .named(Self.space)) { model.tapSession(s, at: $0) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(HostActivator.appName(for: s.host).map { "Opens \($0)" } ?? "Opens the session")
                    .accessibilityAction { model.tapSession(s, at: nil) }
            }
        }
        .padding(model.opensUp ? .bottom : .top, PetViewModel.tail)
        .background(PetGlass(shape: shape))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private var accessibilityLabel: String {
        guard let s = model.primary else { return "Ambient pet, asleep. No agent needs you." }
        let lead = model.summary.map { "Ambient pet. \($0). Most urgent" } ?? "Ambient pet, \(Describe.mood(s.mood))"
        return "\(lead): \(Describe.title(s)), \(Describe.activity(s.activity))"
    }
}

/// The speech bubble: the most urgent session at a glance.
struct PetBubble: View {
    let session: Session
    /// "+2", or "+1 needs you" in amber when another session needs you too.
    let badge: String?
    var urgentBadge = false

    var body: some View {
        HStack(spacing: 8) {
            StateGlyph(mood: session.activity.rawMood, color: session.tint, size: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(Describe.title(session))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(urgentBadge ? Palette.waiting.mixed(with: RGB(r: 1, g: 1, b: 1), 0.35).color : .white.opacity(0.8))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(urgentBadge ? Palette.waiting.color.opacity(0.24) : .white.opacity(0.14)))
                    }
                }
                Text(Describe.activity(session.activity))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Describe.clock(session, now: ctx.date, compact: true) ?? "")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The open bubble: the sessions worth your attention, and the island's actions.
private struct PetSessionList: View {
    @ObservedObject var model: PetViewModel

    var body: some View {
        let list = model.listed
        VStack(spacing: 0) {
            if list.shown.isEmpty {
                VStack(spacing: 2) {
                    Text("All quiet").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    Text("No agent needs you right now.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: PetViewModel.rowHeight)
                .accessibilityElement(children: .combine)
            }
            ForEach(list.shown) { s in
                PetSessionRow(session: s) { model.tapSession(s, at: $0) }
            }
            if list.more > 0 {
                Text("+\(list.more) more in the menu bar")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: PetViewModel.moreHeight)
            }
            Spacer(minLength: 0)
            if let summary = model.summary {
                Text(summary)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: PetViewModel.summaryHeight)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 12) }
            }
            HStack(spacing: 12) {
                PetFooterButton(title: model.quiet ? "Resume alerts" : "Quiet 1h",
                                symbol: model.quiet ? "bell" : "bell.slash", action: model.onToggleQuiet)
                PetFooterButton(title: "Mark all seen", symbol: "checkmark.circle", action: model.onAcknowledgeAll)
                Spacer()
                PetFooterButton(title: "Hide pet", symbol: "eye.slash", iconOnly: true, action: model.onHide)
                PetFooterButton(title: "Settings", symbol: "gearshape", iconOnly: true, action: model.onSettings)
            }
            .padding(.horizontal, 14)
            .frame(height: PetViewModel.footerHeight)
        }
        .padding(.vertical, 6)
    }
}

/// Clicking the pet: every session at a glance, titles only, most urgent first.
private struct PetPeekList: View {
    @ObservedObject var model: PetViewModel

    var body: some View {
        let peek = model.peek
        VStack(alignment: .leading, spacing: 0) {
            if peek.shown.isEmpty {
                Text("All quiet. No agent needs you right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .frame(height: PetViewModel.peekRowHeight)
            }
            ForEach(peek.shown) { s in
                PetPeekRow(session: s) { model.tapSession(s, at: $0) }
            }
            if peek.more > 0 {
                note("+\(peek.more) more — hover the pet for the list")
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 12)
            .frame(height: PetViewModel.moreHeight)
    }
}

private struct PetPeekRow: View {
    let session: Session
    let action: (CGPoint?) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            PetPip(session: session)
            Text(Describe.title(session))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Describe.clock(session, now: ctx.date, compact: true) ?? "")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PetViewModel.peekRowHeight - 2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hovered ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named(PetView.space)) { action($0) }
        .onHover { hovered = $0 }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(Describe.title(session)), \(Describe.mood(session.mood))")
        .accessibilityAction { action(nil) }
    }
}

/// The row of markers under the pet: one per session, in the order of the list, holding still.
private struct PetPips: View {
    let pips: (shown: [Session], more: Int)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pips.shown) { PetPip(session: $0) }
            if pips.more > 0 {
                Text("+\(pips.more)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .frame(height: 10)
                    .background(Capsule().fill(Color(red: 0.08, green: 0.09, blue: 0.11)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A session's marker: its mood's color, and a shape so it doesn't rely on color — "!" needs you, a check when
/// done, a cross when failed, plain in the agent's color while working.
struct PetPip: View {
    let session: Session

    var body: some View {
        let symbol: String? = switch session.mood {
        case .waiting: "exclamationmark"
        case .done: "checkmark"
        case .error: "xmark"
        case .working, .idle: nil
        }
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(session.moodTint.color)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(Color(red: 0.08, green: 0.09, blue: 0.11), lineWidth: 1)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
            }
        }
        .frame(width: 10, height: 10)
    }
}

private struct PetSessionRow: View {
    let session: Session
    let action: (CGPoint?) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            StateGlyph(mood: session.activity.rawMood, color: session.tint, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Describe.title(session))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    AgentTag(agent: session.agent)
                }
                Text(Describe.activity(session.activity))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Describe.clock(session, now: ctx.date) ?? "")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PetViewModel.rowHeight - 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovered ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named(PetView.space)) { action($0) }
        .onHover { hovered = $0 }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(HostActivator.appName(for: session.host).map { "Opens \($0)" } ?? "Opens the session")
        .accessibilityAction { action(nil) }
    }
}

private struct PetFooterButton: View {
    let title: String
    let symbol: String
    var iconOnly = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Image(systemName: symbol).frame(width: 20, height: 20)
                } else {
                    Label(title, systemImage: symbol)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovered = $0 }
    }
}

/// A rounded bubble with a tail pointing at the pet, above or below.
struct BubbleShape: Shape {
    var tailX: CGFloat
    var tail: CGFloat
    var tailOnTop: Bool
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = tailOnTop ? CGRect(x: rect.minX, y: rect.minY + tail, width: rect.width, height: rect.height - tail)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        let x = rect.minX + tailX, half = tail + 1
        var tip = Path()
        if tailOnTop {
            tip.move(to: CGPoint(x: x - half, y: body.minY + 0.5))
            tip.addLine(to: CGPoint(x: x, y: rect.minY))
            tip.addLine(to: CGPoint(x: x + half, y: body.minY + 0.5))
        } else {
            tip.move(to: CGPoint(x: x - half, y: body.maxY - 0.5))
            tip.addLine(to: CGPoint(x: x, y: rect.maxY))
            tip.addLine(to: CGPoint(x: x + half, y: body.maxY - 0.5))
        }
        tip.closeSubpath()
        p.addPath(tip)
        return p
    }
}

/// Dark frosted glass, so the bubble's white text reads over any window. The system's behind-window blur is drawn by
/// the window server; Liquid Glass would render its refraction in the app with Metal every time the bubble opens or
/// closes, holding some 60 MB for a bubble that is mostly a dark scrim anyway.
private struct PetGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            FrostedBackdrop()
            shape.fill(Color.black.opacity(0.62))
        }
        .clipShape(shape)
    }
}
