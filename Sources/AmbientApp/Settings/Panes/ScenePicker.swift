import AmbientCore
import SwiftUI

private struct SceneOption: Identifiable {
    let id: String
    let title: String
    /// Nil for "A new one each day".
    let kind: SceneKind?

    static let all: [SceneOption] = SceneKind.allCases.map { SceneOption(id: $0.rawValue, title: $0.displayName, kind: $0) }
        + [SceneOption(id: SceneChoice.daily.rawValue, title: "A new one each day", kind: nil)]
}

/// A card per world, and one for "A new one each day".
struct ScenePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            ForEach(SceneOption.all) { option in
                let selected = option.id == selection
                Button { selection = option.id } label: {
                    VStack(spacing: 6) {
                        thumbnail(option.kind)
                            .frame(height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Theme.Colors.hairline, lineWidth: selected ? 2 : 0.5))
                        Text(option.title)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func thumbnail(_ kind: SceneKind?) -> some View {
        if let kind {
            SceneView(state: WallpaperPreview.scenery(kind), showsText: false, animated: false)
        } else {
            HStack(spacing: 0) {
                ForEach(SceneKind.allCases, id: \.self) { kind in
                    SceneView(state: WallpaperPreview.scenery(kind), showsText: false, animated: false)
                }
            }
        }
    }
}
