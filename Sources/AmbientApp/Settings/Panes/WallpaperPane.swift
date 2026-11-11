import AmbientCore
import SwiftUI

struct WallpaperPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var wallpaper: LivingWallpaper
    @ObservedObject var calendar: CalendarSource

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            WallpaperPreview(enabled: prefs.wallpaperEnabled, choice: prefs.sceneChoice, look: prefs.sceneLook)
            if wallpaper.restorePending {
                SettingsSection(footer: "Ambient showed the scene as your wallpaper while the Mac was locked and hasn't put yours back yet.") {
                    SettingsRow(title: "Restore my wallpaper") {
                        Button("Restore") { wallpaper.restoreWallpaper() }.buttonStyle(.pillProminent)
                    }
                }
            }
            SettingsSection(footer: "Drawn above your wallpaper and below your desktop icons. Turn it off and your own wallpaper is simply there.") {
                SettingsToggleRow(title: "Living wallpaper", isOn: $prefs.wallpaperEnabled)
            }
            Group {
                SettingsSection(header: "Scene",
                                footer: "When you open the notch, the Solar System's planets orbit; the other scenes can form a black hole at the notch.") {
                    ScenePicker(selection: $prefs.wallpaperScene).settingsRowPadding()
                    SettingsDivider()
                    SettingsRow(title: "Look", subtitle: "Automatic is light by day and dark at night.") {
                        Picker("Look", selection: $prefs.wallpaperLook) {
                            ForEach(SceneLook.allCases, id: \.self) { look in
                                Text(look.displayName).tag(look.rawValue)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsToggleRow(title: "Black hole when the notch opens", isOn: $prefs.wallpaperIslandEffect)
                        .disabled(prefs.sceneChoice == .fixed(.solar))
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
                SettingsSection(header: "On the scene") {
                    SettingsToggleRow(title: "Next calendar event", subtitle: "Only your next timed event today, read on this Mac.",
                                      isOn: $prefs.wallpaperCalendar)
                    if prefs.wallpaperCalendar && !calendar.hasAccess {
                        SettingsDivider()
                        SettingsRow(title: "Calendar access",
                                    subtitle: calendar.canAsk ? nil : "Turned off for Ambient in Privacy & Security.",
                                    subtitleStatus: .warning) {
                            PermissionControl(allowed: calendar.canAsk ? nil : false, ask: { calendar.requestAccess() },
                                              openSettings: { PermissionControl.openPrivacy("Privacy_Calendars") })
                        }
                    }
                    SettingsDivider()
                    SettingsToggleRow(title: "Task board", subtitle: "What's in progress or blocked, as soft cues on the desk scene.",
                                      isOn: $prefs.wallpaperShowBoard)
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
