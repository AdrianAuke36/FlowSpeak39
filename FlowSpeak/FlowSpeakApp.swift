import SwiftUI

@main
struct FlowLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("FlowSpeak Beta", id: "home") {
            HomeView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .frame(width: 760, height: 520)
        }
    }
}
