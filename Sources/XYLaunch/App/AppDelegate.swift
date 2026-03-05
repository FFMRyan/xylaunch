import AppKit
import Carbon.HIToolbox
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = LauncherViewModel()

    private var statusItem: NSStatusItem?
    private var hotKeyCenter: GlobalHotKeyCenter?
    private var singleInstanceLock: SingleInstanceLock?
    private var panelController: LauncherPanelController?
    private var isTerminatingApp = false
    private var allowTerminateRequest = false
    private var suppressAutoShowOnNextActivate = false
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        let runningUnderDebugger = isRunningUnderDebugger()
        if runningUnderDebugger {
            terminateOtherInstancesForDebug()
        } else {
            guard acquireSingleInstanceLock() else {
                return
            }

            guard ensureSingleInstance() else {
                return
            }
        }

        NSApp.setActivationPolicy(.regular)

        panelController = LauncherPanelController(viewModel: viewModel)
        viewModel.closePanelAction = { [weak self] in
            self?.minimizeMainWindow()
        }

        configureStatusItem()
        configureHotKey()
        configureQuitShortcut()
        viewModel.refreshApplications()

        // Surface launcher immediately.
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = otherInstances.first else {
            return true
        }

        existing.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        allowTerminateRequest = true
        isTerminatingApp = true
        NSApp.terminate(nil)
        return false
    }

    private func terminateOtherInstancesForDebug() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        for app in otherInstances {
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        if isRunningUnderDebugger() {
            return true
        }

        guard let bundleID = Bundle.main.bundleIdentifier else {
            return true
        }

        let lock = SingleInstanceLock(bundleIdentifier: bundleID)
        guard lock.acquire() else {
            allowTerminateRequest = true
            isTerminatingApp = true
            NSApp.terminate(nil)
            return false
        }
        singleInstanceLock = lock
        return true
    }

    private func isRunningUnderDebugger() -> Bool {
        if ProcessInfo.processInfo.environment["XYLAUNCH_DEBUG_NO_SINGLE_INSTANCE"] == "1" {
            return true
        }

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else {
            return false
        }

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter?.unregister()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: 24)
        let icon = makeStatusBarTemplateIcon()
        icon.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.title = ""
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.target = self
        statusItem.button?.action = #selector(onStatusItemClicked)
        self.statusItem = statusItem
    }

    private func makeStatusBarTemplateIcon() -> NSImage {
        if let symbolImage = NSImage(
            systemSymbolName: "rocket.fill",
            accessibilityDescription: "小火箭启动器"
        ) {
            let configured = symbolImage.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            ) ?? symbolImage
            configured.isTemplate = true
            configured.size = NSSize(width: 14, height: 14)
            return configured
        }

        let fallback = NSImage(named: NSImage.applicationIconName) ?? NSImage()
        fallback.isTemplate = true
        fallback.size = NSSize(width: 14, height: 14)
        return fallback
    }

    private func configureHotKey() {
        let center = GlobalHotKeyCenter { [weak self] in
            Task { @MainActor in
                self?.toggleMainWindow()
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
            toggleMainWindow()
            return
        }

        if event.type == .rightMouseUp {
            openStatusMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func openStatusMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开启动台", action: #selector(openLauncher), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        let refreshItem = NSMenuItem(title: "刷新应用", action: #selector(refreshApps), keyEquivalent: "r")
        let quitItem = NSMenuItem(title: "退出 小火箭启动器", action: #selector(quitApp), keyEquivalent: "q")
        openItem.target = self
        settingsItem.target = self
        refreshItem.target = self
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(settingsItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openLauncher() {
        showMainWindow()
    }

    @objc private func refreshApps() {
        viewModel.refreshApplications()
    }

    @objc private func openSettings() {
        showMainWindow()
        viewModel.requestOpenSettings()
    }

    @objc private func quitApp() {
        allowTerminateRequest = true
        isTerminatingApp = true
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isTerminatingApp else {
            return false
        }

        if hasVisibleAppWindows {
            suppressAutoShowOnNextActivate = true
            hideAllAppWindows()
        } else {
            showMainWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isTerminatingApp else {
            return
        }
        if suppressAutoShowOnNextActivate {
            suppressAutoShowOnNextActivate = false
            return
        }
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowTerminateRequest else {
            minimizeMainWindow()
            return .terminateCancel
        }
        isTerminatingApp = true
        return .terminateNow
    }

    private func toggleMainWindow() {
        guard !isTerminatingApp else {
            return
        }
        let visible = panelController?.isVisible == true
        visible ? minimizeMainWindow() : showMainWindow()
    }

    func showMainWindow() {
        panelController?.show()
    }

    private func hideMainWindow() {
        panelController?.hide()
    }

    private func minimizeMainWindow() {
        panelController?.hide()
    }

    private var hasVisibleAppWindows: Bool {
        NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized
        }
    }

    private func hideAllAppWindows() {
        panelController?.hide()
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
    }

    private func configureQuitShortcut() {
        guard localKeyMonitor == nil else {
            return
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                !self.isTerminatingApp,
                event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "q"
            else {
                return event
            }
            self.allowTerminateRequest = true
            self.isTerminatingApp = true
            NSApp.terminate(nil)
            return nil
        }
    }
}

private final class SingleInstanceLock {
    private var fileDescriptor: Int32 = -1
    private let lockFilePath: String

    init(bundleIdentifier: String) {
        lockFilePath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(bundleIdentifier).instance.lock")
    }

    func acquire() -> Bool {
        guard fileDescriptor == -1 else {
            return true
        }

        fileDescriptor = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor != -1 else {
            return false
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        close(fileDescriptor)
        fileDescriptor = -1
        return false
    }

    deinit {
        guard fileDescriptor != -1 else {
            return
        }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
