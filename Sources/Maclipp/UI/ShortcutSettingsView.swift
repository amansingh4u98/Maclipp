import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftShortcut: KeyboardShortcut
    @State private var isRecording = false
    @State private var validationMessage: String?

    init(model: AppModel) {
        self.model = model
        _draftShortcut = State(initialValue: model.keyboardShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Keyboard Shortcut")
                    .font(.title2.weight(.semibold))
                Text("Choose the global shortcut that opens Maclipp from any application.")
                    .foregroundStyle(.secondary)
            }

            Button {
                validationMessage = nil
                isRecording = true
            } label: {
                HStack {
                    Text(isRecording ? "Press a shortcut…" : draftShortcut.displayName)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                    Spacer()
                    Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .overlay {
                ShortcutCaptureView(
                    isRecording: isRecording,
                    onCapture: { shortcut in
                        draftShortcut = shortcut
                        validationMessage = nil
                        isRecording = false
                    },
                    onInvalid: {
                        validationMessage = "Include Command, Option, Control, or Shift."
                    },
                    onCancel: {
                        isRecording = false
                    }
                )
                .allowsHitTesting(false)
            }

            if let message = validationMessage ?? model.shortcutError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Click the field, then press your preferred key combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset to ⌥Space") {
                    draftShortcut = .default
                    validationMessage = nil
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if model.updateKeyboardShortcut(draftShortcut) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRecording)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (KeyboardShortcut) -> Void
    let onInvalid: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        configure(nsView)
        guard isRecording else { return }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func configure(_ view: KeyCaptureView) {
        view.isRecording = isRecording
        view.onCapture = onCapture
        view.onInvalid = onInvalid
        view.onCancel = onCancel
    }
}

private final class KeyCaptureView: NSView {
    var isRecording = false
    var onCapture: ((KeyboardShortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty {
            onCancel?()
            return
        }

        guard let shortcut = KeyboardShortcut(event: event) else {
            onInvalid?()
            return
        }

        onCapture?(shortcut)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
}
