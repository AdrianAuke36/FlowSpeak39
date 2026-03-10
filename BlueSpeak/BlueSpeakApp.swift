import SwiftUI

@main
struct BlueSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("BlueSpeak Beta", id: "home") {
            HomeView()
                .environment(\.locale, Locale(identifier: settings.interfaceLanguage.localeIdentifier))
        }
        .defaultSize(width: 1160, height: 760)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .frame(minWidth: 860, minHeight: 620)
                .environment(\.locale, Locale(identifier: settings.interfaceLanguage.localeIdentifier))
        }
    }
}
