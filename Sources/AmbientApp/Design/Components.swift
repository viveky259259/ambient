import SwiftUI

// MARK: - Glass

/// Liquid Glass on macOS 26 and later; a material with a hairline edge before it, or a solid
/// surface when the user asks for less transparency.
private struct GlassBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = Theme.Radius.panel) -> some View {
        modifier(GlassBackground(radius: radius))
    }

    /// The padding every settings row shares.
    func settingsRowPadding() -> some View {
        padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 9)
            .frame(minHeight: Theme.Layout.rowMinHeight)
    }
}

// MARK: - Sections and rows

/// A titled group of rows on a card, with an optional footnote. Footers read Markdown.
struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(Theme.Fonts.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Space.sm)
                    .accessibilityAddTraits(.isHeader)
            }
            SettingsCard { content }
            if let footer {
                Text(LocalizedStringKey(footer))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.sm)
            }
        }
    }
}

/// Rows on a rounded card.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 0) { content }
            .background(Theme.Colors.card, in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.hairline.opacity(0.6), lineWidth: 0.5))
    }
}

/// A hairline between rows, inset like the system's.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 0.5)
            .padding(.leading, Theme.Space.sm)
    }
}

/// A title, an optional subtitle, and a control on the trailing edge.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleStatus: Theme.Status = .neutral
    @ViewBuilder var accessory: Accessory
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.row)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(subtitleStatus.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            Spacer(minLength: Theme.Space.sm)
            accessory
        }
        .settingsRowPadding()
    }
}

/// A row whose control is a switch.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var subtitleStatus: Theme.Status = .neutral
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, subtitleStatus: subtitleStatus) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - Status

/// A dot and a word: Connected, Needs update, Allowed.
struct StatusBadge: View {
    let text: String
    let status: Theme.Status

    init(_ text: String, _ status: Theme.Status) {
        self.text = text
        self.status = status
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(text).font(Theme.Fonts.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// Capsule buttons: `.pill` for most actions, `.pillProminent` for the one that moves you forward.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case plain, prominent }
    var kind: Kind = .plain
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind, large: large)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let prominent = kind == .prominent
        configuration.label
            .font(large ? .system(size: 13, weight: .semibold) : Theme.Fonts.button)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, large ? 22 : 12)
            .padding(.vertical, large ? 8 : 4)
            .background(Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(hovered ? 0.11 : 0.07)))
            .overlay(Capsule().fill(Color.black.opacity(prominent && hovered ? 0.08 : 0)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(kind: .prominent) }
    static var pillProminentLarge: PillButtonStyle { PillButtonStyle(kind: .prominent, large: true) }
}

// MARK: - Sidebar

/// A sidebar row with a soft pill behind the selection.
struct SidebarItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.hover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
