import SwiftUI

@main
struct XYLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("小火箭启动器", id: "main") {
            LauncherRootView(viewModel: appDelegate.viewModel)
                .onAppear {
                    appDelegate.bindMainWindowIfNeeded()
                    appDelegate.showMainWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
