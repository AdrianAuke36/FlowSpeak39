import SwiftUI

@main
struct FlowLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("FlowSpeak Beta", id: "home") {
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
