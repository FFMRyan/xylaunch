import SwiftUI

@main
struct XYLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .frame(width: 420, height: 260)
        }
    }
}
