import SwiftUI

@main
struct FlowLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(width: 760, height: 520)
        }
    }
}
