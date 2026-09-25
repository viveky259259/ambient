import AmbientCore
import AppKit
import QuartzCore
import SwiftUI

/// The island's heartbeat: an orb whose color and motion say what the agent is doing.
/// Motion runs as Core Animation on the render server, so a glyph that pulses for hours costs
/// the app nothing per frame.
struct StateGlyph: View {
    let mood: Mood
    let color: RGB
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch mood {
            case .done: badge("checkmark")
            case .error: badge("exclamationmark")
            case .idle: Circle().fill(color.color.opacity(0.6)).frame(width: size * 0.5, height: size * 0.5)
            case .working, .waiting: OrbView(mood: mood, color: color, size: size)
            }
        }
        .frame(width: size + 6, height: size + 6)
        .accessibilityLabel(Text(Describe.mood(mood)))
    }

    private func badge(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(color.color).frame(width: size, height: size)
                .shadow(color: color.color.opacity(0.6), radius: 4)
            Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(.black.opacity(0.85))
        }
    }
}

private struct OrbView: NSViewRepresentable {
    let mood: Mood
    let color: RGB
    let size: CGFloat

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }

    func updateNSView(_ view: OrbLayerView, context: Context) {
        view.configure(mood: mood, color: color.nsColor, size: size)
    }
}

final class OrbLayerView: NSView {
    private let orb = CALayer()
    private let ring = CAShapeLayer()
    private var current: (Mood, NSColor, CGFloat)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(ring)
        layer?.addSublayer(orb)
        ring.fillColor = nil
        ring.lineCap = .round
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if let (mood, color, size) = current { build(mood: mood, color: color, size: size) }
    }

    func configure(mood: Mood, color: NSColor, size: CGFloat) {
        if let c = current, c.0 == mood, c.1 == color, c.2 == size { return }
        current = (mood, color, size)
        build(mood: mood, color: color, size: size)
    }

    private func build(mood: Mood, color: NSColor, size: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let d = size * 0.68
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orb.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        orb.position = center
        orb.cornerRadius = d / 2
        orb.backgroundColor = color.cgColor
        orb.shadowColor = color.cgColor
        orb.shadowOffset = .zero
        orb.shadowRadius = 4
        orb.shadowOpacity = 0.6

        let r = size + 5
        ring.bounds = CGRect(x: 0, y: 0, width: r, height: r)
        ring.position = center
        ring.strokeColor = color.withAlphaComponent(0.9).cgColor
        ring.lineWidth = mood == .working ? 1.6 : 1.4
        if mood == .working {
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            ring.strokeStart = 0
            ring.strokeEnd = 0.28
        } else {
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: r * 0.2, dy: r * 0.2), transform: nil)
            ring.strokeStart = 0
            ring.strokeEnd = 1
        }
        CATransaction.commit()

        orb.removeAllAnimations()
        ring.removeAllAnimations()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            ring.opacity = mood == .working ? 1 : 0
            return
        }

        let period = mood == .waiting ? 1.2 : 3.2
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.9
        breathe.toValue = 1.08
        breathe.duration = period / 2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        orb.add(breathe, forKey: "breathe")

        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 0.35
        glow.toValue = 0.9
        glow.duration = period / 2
        glow.autoreverses = true
        glow.repeatCount = .infinity
        orb.add(glow, forKey: "glow")

        if mood == .working {
            ring.opacity = 1
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 1.4
            spin.repeatCount = .infinity
            ring.add(spin, forKey: "spin")
        } else {
            // A ripple leaving the orb, once per pulse.
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.7
            grow.toValue = 1.35
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0
            let ripple = CAAnimationGroup()
            ripple.animations = [grow, fade]
            ripple.duration = period
            ripple.repeatCount = .infinity
            ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(ripple, forKey: "ripple")
        }
    }
}
