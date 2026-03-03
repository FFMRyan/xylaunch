import AppKit
import SwiftUI

private final class FullscreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
    private let panel: NSWindow
    private let viewModel: LauncherViewModel
    private var suppressAutoHideUntil = Date.distantPast
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var localKeyMonitor: Any?

    init(viewModel: LauncherViewModel) {
        self.viewModel = viewModel
        let rootView = LauncherRootView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        panel = FullscreenWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "小火箭启动器"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentViewController = hostingController
        configureKeyMonitor()
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        fitToCurrentScreen()
        suppressAutoHideUntil = Date().addingTimeInterval(2.0)
        enterLauncherPresentationMode()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        for retry in 1 ... 3 {
            let delay = 0.16 * Double(retry)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else {
                    return
                }
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
                NSApp.activate(ignoringOtherApps: true)
                self.panel.orderFrontRegardless()
                self.panel.makeKeyAndOrderFront(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.ensurePanelVisible()
        }
    }

    func hide() {
        exitLauncherPresentationMode()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep panel visible; close actions are handled explicitly via ESC/hotkey/menu.
    }

    private func fitToCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? panel.screen
            ?? NSScreen.main

        guard let targetScreen else {
            return
        }

        panel.setFrame(targetScreen.frame, display: true, animate: false)
    }

    private func enterLauncherPresentationMode() {
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
    }

    private func exitLauncherPresentationMode() {
        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        } else {
            NSApp.presentationOptions = []
        }
    }

    private func configureKeyMonitor() {
        guard localKeyMonitor == nil else {
            return
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            let isTargetPanel = event.window == panel
            guard panel.isVisible, isTargetPanel else {
                return event
            }

            if event.keyCode == 53 {
                hide()
                return nil
            }

            return event
        }
    }

    private func ensurePanelVisible() {
        if panel.isVisible, panel.occlusionState.contains(.visible) {
            return
        }

        // Recovery path for edge cases where borderless windows fail to surface.
        let screen = panel.screen ?? NSScreen.main
        if let screen {
            panel.setFrame(screen.frame, display: true, animate: false)
        }

        panel.level = .mainMenu
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        // Final fallback: rebuild content controller if window surfaced without content.
        if panel.contentViewController == nil {
            panel.contentViewController = NSHostingController(rootView: LauncherRootView(viewModel: viewModel))
        }
    }
}
