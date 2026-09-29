import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .wallpaper)
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice)
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            SettingsSection(header: "Scene") {
                ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
            }
            .disabled(!prefs.wallpaperEnabled)
        }
    }
}
