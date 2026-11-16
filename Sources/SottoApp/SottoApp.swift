import SwiftUI
import AppKit
import OSLog
import SottoUI
#if DEBUG
import SottoSecurity
#endif

@main struct SottoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { SettingsView(model: delegate.model) } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    lazy var model = AppModel()
    private let lifecycle = Logger(subsystem: "org.sotto.mac", category: "lifecycle")
    private var panel: VoicePanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var localMonitor: Any?
    #if DEBUG
    private var reviewPanel: VoicePanel?
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Sotto runs in the menu bar without an open window")
        lifecycle.notice("Application started")
        NSApp.setActivationPolicy(.accessory)
        panel = VoicePanel(model: model)
        model.present = { [weak self] in self?.panel.show() }
        model.dismiss = { [weak self] in self?.panel.orderOut(nil) }
        model.openSettings = { [weak self] in self?.showSettings() }
        model.permissions.restartApplication = { [weak self] in self?.restart() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sotto")
        let menu = NSMenu()
        menu.addItem(withTitle: "Activate Sotto", action: #selector(activate), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Recent Activity…", action: #selector(showActivity), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Set Up Sotto…", action: #selector(showSetup), keyEquivalent: "")
        menu.addItem(withTitle: "Pause / Resume Sotto", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit Sotto", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }; statusItem.menu = menu
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                let editing = MainActor.assumeIsolated { self?.model.isEditingShortcut ?? false }
                if editing { return event }
                MainActor.assumeIsolated { self?.model.cancel() }; return nil
            }; return event
        }
        let needsSetup = !model.settings.setupCompleted && !model.settings.setupDismissed
        if needsSetup { model.settingsSection = "Setup" }
        if CommandLine.arguments.contains("--setup") { model.settingsSection = "Setup" }
        if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--setup") || needsSetup || !UserDefaults.standard.bool(forKey: "hasLaunched") { showSettings(); UserDefaults.standard.set(true, forKey: "hasLaunched") }
        #if DEBUG
        // Exercise real shortcut/audio behavior without inference or native side effects.
        if CommandLine.arguments.contains("--shortcut-voice-check") { model.shortcutCapturePurpose = .voiceCheck }
        // Visual review only: shows the idle capsule, with no recording or provider request.
        if CommandLine.arguments.contains("--show-capsule") { panel.show() }
        if let index = CommandLine.arguments.firstIndex(of: "--review-capsule"), CommandLine.arguments.indices.contains(index + 1) {
            model.shutdown() // Visual fixtures must never respond to the global recording shortcut.
            let fixture = AppModel()
            fixture.shutdown()
            fixture.state = .thinking
            switch CommandLine.arguments[index + 1] {
            case "question":
                fixture.state = .awaitingInput; fixture.status = "A quick question"
                fixture.reply = "What time tomorrow should I remind you to review your notes?"
            case "approval":
                fixture.state = .awaitingApproval; fixture.status = "Approve this action"
                fixture.approval = Approval(tool: "open_file", arguments: .object(["action": .string("open"), "path": .string("~/Downloads/Research notes and assignment reference material.pdf")]))
            case "completion":
                fixture.state = .completed; fixture.status = "Done"
                fixture.reply = "Created “Review my research notes and prepare the assignment reference material” for Monday, November 16 at 5:00 PM.\n\nThis interface preview uses sample text only. No reminder was created."
            default: return
            }
            reviewPanel = VoicePanel(model: fixture, preview: true)
            reviewPanel?.show()
        }
        #endif
    }
    @objc private func showSetup() { model.settingsSection = "Setup"; showSettings() }
    @objc private func showActivity() { model.settingsSection = "Activity"; showSettings() }
    @objc private func activate() { model.activate() }
    @objc private func togglePause() { model.paused.toggle(); if model.paused { model.cancel() } }
    @objc private func quit() { NSApp.terminate(nil) }
    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--setup"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.model.error = "Couldn’t restart Sotto: \(error.localizedDescription)" }
                else { NSApp.terminate(nil) }
            }
        }
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            SettingsWindowPolicy.apply(to: window)
            window.title = "Sotto Settings"; window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowDidMiniaturize(_ notification: Notification) { lifecycle.notice("Settings miniaturized") }
    func windowDidDeminiaturize(_ notification: Notification) { lifecycle.notice("Settings restored from miniaturization") }
    func windowWillClose(_ notification: Notification) { lifecycle.notice("Settings closed; menu bar utility remains running") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { lifecycle.notice("Application terminating"); model.shutdown(); if let localMonitor { NSEvent.removeMonitor(localMonitor) } }
}
