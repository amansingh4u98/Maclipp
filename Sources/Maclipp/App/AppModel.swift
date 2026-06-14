import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private static let shortcutDefaultsKey = "historyKeyboardShortcut"

    let repository: ClipboardRepository
    private let monitor: ClipboardMonitor

    @Published private(set) var isPaused = false
    @Published private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var serviceError: String?
    @Published private(set) var historyPresentationID = 0
    @Published private(set) var keyboardShortcut: KeyboardShortcut
    @Published private(set) var shortcutError: String?

    private var hotKeyManager: GlobalHotKeyManager?
    private var menuBarController: MenuBarController?
    private var previousApplication: NSRunningApplication?
    private var hasStarted = false

    private init() {
        repository = ClipboardRepository()
        monitor = ClipboardMonitor(repository: repository)
        keyboardShortcut = Self.loadKeyboardShortcut()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.start()
        menuBarController = MenuBarController(
            model: self,
            onChoose: { [weak self] item in self?.restore(item) }
        )
        hotKeyManager = GlobalHotKeyManager { [weak self] in
            Task { @MainActor in
                self?.toggleHistory()
            }
        }
        if hotKeyManager?.register(keyboardShortcut) != true {
            keyboardShortcut = .default
            _ = hotKeyManager?.register(.default)
            persistKeyboardShortcut()
            shortcutError = "The saved shortcut was unavailable, so Maclipp reset it to ⌥Space."
        }
    }

    func showHistory() {
        let currentApplication = NSRunningApplication.current
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != currentApplication.processIdentifier {
            previousApplication = frontmostApplication
        }
        menuBarController?.showHistory()
    }

    func toggleHistory() {
        if menuBarController?.isPresented == true {
            hideHistory()
        } else {
            showHistory()
        }
    }

    func hideHistory() {
        menuBarController?.hideHistory()
    }

    func historyDidOpen() {
        historyPresentationID &+= 1
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            serviceError = nil
        } catch {
            serviceError = error.localizedDescription
        }
    }

    @discardableResult
    func updateKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        guard hotKeyManager?.register(shortcut) == true else {
            shortcutError = "That shortcut is already in use by macOS or another application."
            return false
        }

        keyboardShortcut = shortcut
        shortcutError = nil
        persistKeyboardShortcut()
        return true
    }

    func resetKeyboardShortcut() {
        _ = updateKeyboardShortcut(.default)
    }

    private func restore(_ item: ClipboardItem) {
        guard ClipboardWriter.restore(item, from: repository) else { return }
        monitor.synchronizeChangeCount()
        menuBarController?.hideHistory()
        previousApplication?.activateForMaclipp()
        previousApplication = nil
    }

    private static func loadKeyboardShortcut() -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
            return .default
        }
        return shortcut
    }

    private func persistKeyboardShortcut() {
        guard let data = try? JSONEncoder().encode(keyboardShortcut) else { return }
        UserDefaults.standard.set(data, forKey: Self.shortcutDefaultsKey)
    }
}

private extension NSRunningApplication {
    func activateForMaclipp() {
        if #available(macOS 14.0, *) {
            activate(options: [.activateAllWindows])
        } else {
            activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}
