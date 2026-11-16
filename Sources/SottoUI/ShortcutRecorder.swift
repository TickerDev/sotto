import SwiftUI
import AppKit

/// One control and one persisted binding, shared by General and guided setup.
struct ShortcutSettingsRow: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                Text("Activation shortcut")
                Spacer(minLength: 12)
                ShortcutRecorder(model: model, binding: model.settings.activationShortcut, enabled: !model.isBusy).frame(width: 210, height: 28)
            }
            Text(model.settings.toggleToTalk ? "Press once to talk. Press again to send. You can also click Send." : "Hold to talk. Release to send. Double-tap for hands-free, then click Send.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Click the shortcut to change it. Press Esc to cancel. Fn / Globe shortcuts follow your macOS keyboard settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let model: AppModel
    let binding: ActivationShortcut
    let enabled: Bool
    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.model = model; view.refresh()
        return view
    }
    func updateNSView(_ view: RecorderButton, context: Context) { view.model = model; view.refresh() }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish(nil) }

    @MainActor final class RecorderButton: NSButton {
        weak var model: AppModel?
        private var recording = false
        private var candidateFlags: CGEventFlags = []
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded; setButtonType(.momentaryPushIn)
            target = self; action = #selector(toggleRecording)
            image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            imagePosition = .imageTrailing; imageHugsTitle = false
            setAccessibilityLabel("Activation shortcut")
            setAccessibilityIdentifier("activation-shortcut-recorder")
            toolTip = "Click, then press a key combination or press and release modifier keys. Escape cancels."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func refresh() {
            guard let model else { return }
            isEnabled = !model.isBusy
            if !recording { title = model.settings.activationShortcut.display }
            setAccessibilityValue(recording ? "Recording shortcut" : model.settings.activationShortcut.display)
        }
        @objc private func toggleRecording() {
            if recording { finish(nil); return }
            guard model?.beginShortcutEditing() == true else { return }
            recording = true; candidateFlags = []; title = "Press a shortcut…"
            setAccessibilityValue("Recording shortcut. Press Escape to cancel.")
            if window?.makeFirstResponder(self) != true { finish(nil) }
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { finish(nil); return }
            if event.keyCode == 48 && event.modifierFlags.intersection([.control, .option, .command, .shift, .function]).isEmpty {
                finish(nil); window?.selectNextKeyView(self); return
            }
            guard !event.isARepeat else { return }
            let shortcut = ActivationShortcut.capture(event)
            guard shortcut.isValid else { title = "Include a modifier key"; NSSound.beep(); return }
            finish(shortcut)
        }
        override func flagsChanged(with event: NSEvent) {
            guard recording else { super.flagsChanged(with: event); return }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(ActivationShortcut.relevantFlags)
            if !flags.isEmpty {
                if flags.rawValue.nonzeroBitCount >= candidateFlags.rawValue.nonzeroBitCount { candidateFlags = flags }
                title = ActivationShortcut(keyCode: nil, flags: flags).display
            } else if !candidateFlags.isEmpty {
                finish(ActivationShortcut(keyCode: nil, flags: candidateFlags))
            }
        }
        override func resignFirstResponder() -> Bool {
            finish(nil)
            return super.resignFirstResponder()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { finish(nil) }
        }
        func finish(_ shortcut: ActivationShortcut?) {
            guard recording else { return }
            recording = false; candidateFlags = []
            model?.finishShortcutEditing(shortcut); refresh()
        }
    }
}
