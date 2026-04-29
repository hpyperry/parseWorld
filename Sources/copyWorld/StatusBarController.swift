import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let contextMenu: NSMenu
    private let monitor: ClipboardMonitor
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(appState: AppState) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.contextMenu = NSMenu()
        self.monitor = appState.monitor
        super.init()

        configurePopover(appState: appState)
        configureStatusButton()
        configureContextMenu()
    }

    private func configurePopover(appState: AppState) {
        popover.delegate = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                historyStore: appState.historyStore,
                launchAtLoginManager: appState.launchAtLoginManager,
                monitor: appState.monitor,
                storage: appState.storage
            )
        )
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: String(localized: "copyWorld"))
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureContextMenu() {
        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            monitor.setCaptureSuspended(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitors()
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            closePopover()
        }
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func startEventMonitors() {
        guard localEventMonitor == nil, globalEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleOutsideClick(event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleOutsideClick(event)
        }
    }

    private func stopEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard popover.isShown else { return }

        if let statusWindow = statusItem.button?.window, event.window == statusWindow {
            return
        }

        if let popoverWindow = popover.contentViewController?.view.window, event.window == popoverWindow {
            return
        }

        // Defer close by one runloop to avoid competing with NSMenu tracking animations.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    private func closePopover() {
        clearPreviewSelectionState()
        popover.performClose(nil)
        stopEventMonitors()
        monitor.setCaptureSuspended(false)
    }

    private func clearPreviewSelectionState() {
        guard
            let contentView = popover.contentViewController?.view,
            let popoverWindow = contentView.window
        else {
            return
        }

        if let textView = findTextView(in: contentView) {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        popoverWindow.makeFirstResponder(nil)
    }

    private func findTextView(in rootView: NSView) -> NSTextView? {
        if let textView = rootView as? NSTextView {
            return textView
        }

        for subview in rootView.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopEventMonitors()
        monitor.setCaptureSuspended(false)
    }
}
