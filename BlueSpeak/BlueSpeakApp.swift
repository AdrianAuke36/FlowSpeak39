import SwiftUI

@main
struct BlueSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("BlueSpeak Beta", id: "home") {
            HomeView()
        }
        .defaultSize(width: 1160, height: 760)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .frame(minWidth: 860, minHeight: 620)
        }
    }
}
