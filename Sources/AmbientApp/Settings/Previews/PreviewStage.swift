import SwiftUI

/// A patch of desktop for a live preview, veiled with "Off" while the feature is disabled.
struct PreviewStage<Content: View>: View {
    var enabled = true
    var alignment: Alignment = .top
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        ZStack(alignment: alignment) {
            Theme.Colors.wallpaper(scheme)
            content
                .opacity(enabled ? 1 : 0.35)
                .saturation(enabled ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Layout.previewHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        .overlay(alignment: .bottomLeading) {
            if !enabled {
                Text("Off")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(Theme.Space.sm)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: enabled)
    }
}
