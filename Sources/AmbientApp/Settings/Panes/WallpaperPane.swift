import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var wallpaper: LivingWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PaneHeader(pane: .wallpaper)
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice)
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            Group {
                SettingsSection(header: "Scene") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                }
                SettingsSection(header: "Lock screen") {
                    SettingsToggleRow(title: "Show on the lock screen", subtitle: lockStatus?.text,
                                      subtitleStatus: lockStatus?.status ?? .neutral, isOn: $prefs.wallpaperOnLockScreen)
                    SettingsDivider()
                    SettingsToggleRow(title: "Show messages on the lock screen",
                                      subtitle: "Prompts, summaries, command hints and event titles. Anyone near your Mac can read them.",
                                      isOn: $prefs.wallpaperLockMessages)
                        .disabled(!prefs.wallpaperOnLockScreen)
                }
            }
            .disabled(!prefs.wallpaperEnabled)
        }
    }

    private var lockStatus: (text: String, status: Theme.Status)? {
        switch wallpaper.lockMode {
        case .off: nil
        case .live: (text: "Live above the lock screen", status: .success)
        case .swap: (text: "Shown as your wallpaper while locked, then put back", status: .neutral)
        case .unavailable: (text: "Not available on this Mac", status: .warning)
        }
    }
}
