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
    private var launcherWindow: NSWindow?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var isTransitioningWindow = false
    private var isTerminatingApp = false
    private var allowTerminateRequest = false
    private var localKeyMonitor: Any?
    private var launchRecoveryWorkItem: DispatchWorkItem?

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

        viewModel.closePanelAction = { [weak self] in
            self?.minimizeMainWindow()
        }

        configureStatusItem()
        configureHotKey()
        configureQuitShortcut()
        viewModel.refreshApplications()

        // Surface launcher immediately, then run one lightweight recovery check.
        DispatchQueue.main.async { [weak self] in
            self?.bindMainWindowIfNeeded()
            self?.showMainWindow()
        }
        scheduleLaunchRecovery()
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
        launchRecoveryWorkItem?.cancel()
        launchRecoveryWorkItem = nil
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
        showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isTerminatingApp else {
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
        let visible = launcherWindow?.isVisible == true
        visible ? minimizeMainWindow() : showMainWindow()
    }

    func showMainWindow() {
        bindMainWindowIfNeeded()
        guard let window = launcherWindow else {
            return
        }
        guard !isTransitioningWindow else {
            return
        }

        if window.isVisible, window.alphaValue >= 0.98 {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        fit(window: window)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        restoreTrafficLightButtons(for: window)
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        animateWindowAlpha(window, to: 1.0, duration: 0.1)
    }

    private func hideMainWindow() {
        launcherWindow?.orderOut(nil)
    }

    private func minimizeMainWindow() {
        guard let window = launcherWindow else {
            return
        }
        guard !isTransitioningWindow else {
            return
        }

        animateWindowAlpha(window, to: 0, duration: 0.08) {
            window.orderOut(nil)
            window.alphaValue = 1
        }
        exitLauncherPresentationMode()
    }

    private func scheduleLaunchRecovery() {
        launchRecoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recoverMainWindowIfNeeded()
        }
        launchRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func fit(window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? window.screen ?? NSScreen.main
        guard let screen else {
            return
        }
        let visible = screen.visibleFrame
        let minWidth: CGFloat = 760
        let minHeight: CGFloat = 520
        let maxWidth = max(minWidth, visible.width * 0.95)
        let maxHeight = max(minHeight, visible.height * 0.95)

        var frame = window.frame
        if frame.width <= 0 || frame.height <= 0 {
            frame.size = CGSize(width: maxWidth * 0.86, height: maxHeight * 0.86)
        } else {
            frame.size.width = min(max(frame.width, minWidth), maxWidth)
            frame.size.height = min(max(frame.height, minHeight), maxHeight)
        }

        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)

        if !visible.intersects(frame) {
            frame.origin = CGPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
        }

        window.setFrame(frame, display: true, animate: false)
    }

    func bindMainWindowIfNeeded() {
        if let bound = launcherWindow, NSApp.windows.contains(bound) {
            return
        }

        guard let window = NSApp.windows.first ?? createFallbackWindow() else {
            return
        }

        launcherWindow = window
        configureMainWindowAppearance(window)
    }

    private func createFallbackWindow() -> NSWindow? {
        let rootView = LauncherRootView(viewModel: viewModel)
        let host = NSHostingController(rootView: rootView)
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.addWindowsItem(window, title: "小火箭启动器", filename: false)
        return window
    }

    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .fullScreenDisallowsTiling]
        window.level = .mainMenu
        window.isMovable = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        restoreTrafficLightButtons(for: window)
    }

    private func enterLauncherPresentationMode() {
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions = []
    }

    private func exitLauncherPresentationMode() {
        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        } else {
            NSApp.presentationOptions = []
        }
    }

    private func restoreTrafficLightButtons(for window: NSWindow) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttons {
            guard let button = window.standardWindowButton(type) else {
                continue
            }
            button.isHidden = false
            button.isEnabled = true
            button.alphaValue = 1
        }
    }

    private func animateWindowAlpha(
        _ window: NSWindow,
        to target: CGFloat,
        duration: TimeInterval,
        completion: (@MainActor () -> Void)? = nil
    ) {
        isTransitioningWindow = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = target
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.isTransitioningWindow = false
                completion?()
            }
        })
    }

    private func recoverMainWindowIfNeeded() {
        guard !isTerminatingApp else {
            return
        }
        bindMainWindowIfNeeded()
        guard let window = launcherWindow else {
            return
        }

        let notVisible = !window.isVisible || !window.occlusionState.contains(.visible)
        guard notVisible else {
            return
        }

        showMainWindow()
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
