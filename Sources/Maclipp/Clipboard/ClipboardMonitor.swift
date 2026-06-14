import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    var isPaused = false

    private let repository: ClipboardRepository
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init(repository: ClipboardRepository) {
        self.repository = repository
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func synchronizeChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }
        guard ClipboardSecurityPolicy.shouldCapture(types: pasteboard.types ?? []) else { return }

        let sourceApplication = NSWorkspace.shared.frontmostApplication?.localizedName

        if let image = ClipboardImageReader.image(from: pasteboard) {
            repository.recordImage(image, sourceApplication: sourceApplication)
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            repository.recordText(text, sourceApplication: sourceApplication)
        }
    }
}
