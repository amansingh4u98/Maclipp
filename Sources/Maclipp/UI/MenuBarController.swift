import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let shortcutAnchorWindow: NSWindow
    private let shortcutAnchorView: NSView

    private(set) var isPresented = false

    init(model: AppModel, onChoose: @escaping (ClipboardItem) -> Void) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        shortcutAnchorView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        shortcutAnchorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        super.init()

        shortcutAnchorWindow.contentView = shortcutAnchorView
        shortcutAnchorWindow.isOpaque = false
        shortcutAnchorWindow.backgroundColor = .clear
        shortcutAnchorWindow.alphaValue = 0.01
        shortcutAnchorWindow.hasShadow = false
        shortcutAnchorWindow.ignoresMouseEvents = true
        shortcutAnchorWindow.level = .statusBar
        shortcutAnchorWindow.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.on.square",
                accessibilityDescription: "Maclipp"
            )
            button.toolTip = "Maclipp Clipboard History"
            button.target = self
            button.action = #selector(toggleFromStatusItem)
            button.sendAction(on: [.leftMouseUp])
        }

        let rootView = ClipboardPanelView(
            model: model,
            onChoose: onChoose,
            onClose: { [weak self] in self?.hideHistory() }
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
        popover.contentSize = NSSize(width: 460, height: 540)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    @objc private func toggleFromStatusItem() {
        if isPresented {
            hideHistory()
        } else {
            showHistory(activateApplication: false)
        }
    }

    func showHistory() {
        showHistory(activateApplication: true)
    }

    func hideHistory() {
        isPresented = false
        popover.performClose(nil)
        shortcutAnchorWindow.orderOut(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        isPresented = false
    }

    private func showHistory(activateApplication: Bool) {
        guard let button = statusItem.button else { return }
        isPresented = true

        if activateApplication {
            activateCurrentApplication()
        }

        if activateApplication, let targetScreen = screenContainingPointer() {
            showFromShortcutAnchor(on: targetScreen, statusButton: button)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }

        if activateApplication {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented else { return }
                self.popover.contentViewController?.view.window?.makeKey()
            }
        }

        model.historyDidOpen()
    }

    private func showFromShortcutAnchor(on screen: NSScreen, statusButton: NSStatusBarButton) {
        let trailingInset = statusButton.window.map { window in
            let buttonScreen = window.screen ?? NSScreen.main
            return max(12, (buttonScreen?.frame.maxX ?? window.frame.maxX) - window.frame.midX)
        } ?? 24

        let anchorX = min(
            max(screen.frame.maxX - trailingInset, screen.frame.minX + 12),
            screen.frame.maxX - 12
        )
        let anchorY = screen.frame.maxY - 1

        shortcutAnchorWindow.setFrameOrigin(NSPoint(x: anchorX, y: anchorY))
        shortcutAnchorWindow.orderFrontRegardless()
        popover.show(
            relativeTo: shortcutAnchorView.bounds,
            of: shortcutAnchorView,
            preferredEdge: .minY
        )
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main
    }

    private func activateCurrentApplication() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        } else {
            NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
        }
    }
}
