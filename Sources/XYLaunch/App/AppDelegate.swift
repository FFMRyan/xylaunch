import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = LauncherViewModel()

    private var statusItem: NSStatusItem?
    private var panelController: LauncherPanelController?
    private var hotKeyCenter: GlobalHotKeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = LauncherPanelController(viewModel: viewModel)
        self.panelController = panelController
        viewModel.closePanelAction = { [weak panelController] in
            panelController?.hide()
        }

        configureStatusItem()
        configureHotKey()
        viewModel.refreshApplications()

        // Make first launch behavior explicit for status bar style apps.
        // Without this, users may think the app didn't open.
        DispatchQueue.main.async { [weak self] in
            self?.panelController?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter?.unregister()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2.fill",
            accessibilityDescription: "XYLaunch"
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.target = self
        statusItem.button?.action = #selector(onStatusItemClicked)
        self.statusItem = statusItem
    }

    private func configureHotKey() {
        let center = GlobalHotKeyCenter { [weak self] in
            Task { @MainActor in
                self?.panelController?.toggle()
            }
        }
        center.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | optionKey)
        )
        hotKeyCenter = center
    }

    @objc private func onStatusItemClicked() {
        guard let event = NSApp.currentEvent else {
            panelController?.toggle()
            return
        }

        if event.type == .rightMouseUp {
            openStatusMenu()
        } else {
            panelController?.toggle()
        }
    }

    private func openStatusMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开启动台", action: #selector(openLauncher), keyEquivalent: "")
        let refreshItem = NSMenuItem(title: "刷新应用", action: #selector(refreshApps), keyEquivalent: "r")
        let quitItem = NSMenuItem(title: "退出 XYLaunch", action: #selector(quitApp), keyEquivalent: "q")
        openItem.target = self
        refreshItem.target = self
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openLauncher() {
        panelController?.show()
    }

    @objc private func refreshApps() {
        viewModel.refreshApplications()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }
}
