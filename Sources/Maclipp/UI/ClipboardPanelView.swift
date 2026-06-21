import AppKit
import Combine
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var repository: ClipboardRepository
    let onChoose: (ClipboardItem) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection: UUID?
    @State private var isShowingShortcutSettings = false
    @FocusState private var searchIsFocused: Bool

    init(
        model: AppModel,
        onChoose: @escaping (ClipboardItem) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        repository = model.repository
        self.onChoose = onChoose
        self.onClose = onClose
    }

    // Preserve repository's sort order: pinned first, then most-recent first.
    // (Previously re-sorted by createdAt only, silently dropping pin ordering.)
    private var filteredItems: [ClipboardItem] {
        repository.items.filter { $0.matches(query) }
    }

    private var pinnedItems: [ClipboardItem] { filteredItems.filter(\.isPinned) }
    private var recentItems: [ClipboardItem] { filteredItems.filter { !$0.isPinned } }

    private func shortcutNumber(for item: ClipboardItem) -> Int? {
        guard let index = filteredItems.firstIndex(where: { $0.id == item.id }),
              index < 5 else { return nil }
        return index + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { scrollProxy in
                    List(selection: $selection) {
                        if !pinnedItems.isEmpty {
                            Section {
                                ForEach(pinnedItems) { item in
                                    row(for: item)
                                }
                            } header: {
                                Label("Pinned", systemImage: "pin.fill")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                                    .padding(.top, 2)
                            }
                        }

                        if !recentItems.isEmpty {
                            Section {
                                ForEach(recentItems) { item in
                                    row(for: item)
                                }
                            } header: {
                                if !pinnedItems.isEmpty {
                                    Text("Recent")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .onReceive(model.$historyPresentationID) { presentationID in
                        guard presentationID > 0 else { return }
                        resetToNewest(using: scrollProxy)
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 540)
        .background(.ultraThinMaterial)
        .background(
            KeyboardEventMonitor { event in
                guard !isShowingShortcutSettings else { return false }
                return handleKeyEvent(event)
            }
        )
        .onAppear {
            selection = filteredItems.first?.id
            searchIsFocused = true
        }
        .onChange(of: query) { _ in
            selection = filteredItems.first?.id
        }
        .onReceive(repository.$items) { items in
            let visibleIDs = Set(items.filter { $0.matches(query) }.map(\.id))
            if selection.map(visibleIDs.contains) != true {
                selection = items.first(where: { $0.matches(query) })?.id
            }
        }
        .onExitCommand(perform: onClose)
        .sheet(isPresented: $isShowingShortcutSettings) {
            ShortcutSettingsView(model: model)
        }
    }

    @ViewBuilder
    private func row(for item: ClipboardItem) -> some View {
        ClipboardRow(
            item: item,
            image: repository.image(for: item),
            shortcutNumber: shortcutNumber(for: item)
        )
        .tag(item.id)
        .id(item.id)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onChoose(item) }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                repository.togglePin(item)
            }
            Button("Delete", role: .destructive) {
                repository.delete(item)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            TextField("Search clipboard history", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchIsFocused)
                .onSubmit(chooseSelection)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(query.isEmpty ? "No clips yet" : "No matching clips")
                    .font(.headline)
                Text(
                    query.isEmpty
                        ? "Maclipp records text and images while it is running."
                        : "Try a different search term."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = repository.lastError ?? model.serviceError ?? model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                HStack(spacing: 5) {
                    if model.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("\(repository.items.count) clip\(repository.items.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Menu {
                Button(model.isPaused ? "Resume Recording" : "Pause Recording") {
                    model.togglePause()
                }
                Button(model.launchesAtLogin ? "Disable Launch at Login" : "Launch at Login") {
                    model.toggleLaunchAtLogin()
                }
                Button("Keyboard Shortcut…  \(model.keyboardShortcut.displayName)") {
                    isShowingShortcutSettings = true
                }
                Button("Clear Unpinned History") {
                    repository.clearUnpinned()
                }
                .disabled(repository.items.allSatisfy(\.isPinned))

                Divider()
                Button("Quit Maclipp") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           let shortcutIndex = shortcutIndex(for: event.keyCode),
           filteredItems.indices.contains(shortcutIndex) {
            onChoose(filteredItems[shortcutIndex])
            return true
        }

        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
            return true
        case 126: // Up arrow
            moveSelection(by: -1)
            return true
        case 36, 76: // Return, numpad Enter
            chooseSelection()
            return true
        case 53: // Escape
            onClose()
            return true
        default:
            return false
        }
    }

    private func shortcutIndex(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0
        case 19: return 1
        case 20: return 2
        case 21: return 3
        case 23: return 4
        default: return nil
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = selection.flatMap { selected in
            filteredItems.firstIndex(where: { $0.id == selected })
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selection = filteredItems[nextIndex].id
    }

    private func chooseSelection() {
        let item = selection.flatMap { selected in
            filteredItems.first(where: { $0.id == selected })
        } ?? filteredItems.first
        if let item {
            onChoose(item)
        }
    }

    private func resetToNewest(using scrollProxy: ScrollViewProxy) {
        query = ""
        guard let newestItem = repository.items.max(by: { $0.createdAt < $1.createdAt }) else {
            selection = nil
            return
        }

        selection = newestItem.id
        DispatchQueue.main.async {
            scrollProxy.scrollTo(newestItem.id, anchor: .top)
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let image: NSImage?
    let shortcutNumber: Int?

    @State private var isShowingImagePreview = false

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 4) {
                    if let source = item.sourceApplication {
                        Text(source)
                        Text("·")
                    }
                    Text(item.createdAt.clipboardAge)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                if let n = shortcutNumber {
                    Text("⌘\(n)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .onHover { isShowingImagePreview = $0 }
                .popover(
                    isPresented: $isShowingImagePreview,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .trailing
                ) {
                    ImageHoverPreview(image: image)
                }
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.1))
                Text(item.text ?? "")
                    .font(.system(size: 5.5))
                    .lineLimit(6)
                    .foregroundStyle(Color.accentColor.opacity(0.55))
                    .padding(5)
            }
        }
    }
}

private struct ImageHoverPreview: View {
    let image: NSImage

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 680, maxHeight: 560)
                .background(Color.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(imageDimensions)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var imageDimensions: String {
        let pixelsWide = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelsHigh = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        return "\(pixelsWide) × \(pixelsHigh) px"
    }
}

private extension Date {
    var clipboardAge: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(self)))

        switch elapsed {
        case 0..<60:
            return "\(elapsed) sec\(elapsed == 1 ? "" : "s") ago"
        case 60..<3_600:
            let minutes = elapsed / 60
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        case 3_600..<86_400:
            let hours = elapsed / 3_600
            return "\(hours) hr\(hours == 1 ? "" : "s") ago"
        default:
            let days = elapsed / 86_400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

private struct KeyboardEventMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handler(event) == true ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}
