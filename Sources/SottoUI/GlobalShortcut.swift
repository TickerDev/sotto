import AppKit
import OSLog

@MainActor final class GlobalShortcut {
    var pressed: (() -> Bool)?
    var released: (() -> Void)?
    var handsFree: (() -> Void)?
    var cancelled: (() -> Void)?
    var binding = ActivationShortcut.default
    var toggleMode = false
    private(set) var activationTimestamp: Double?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    private var gesture = ShortcutGesture(doubleTapInterval: max(0.25, NSEvent.doubleClickInterval), tapDuration: max(0.25, NSEvent.doubleClickInterval))
    private var pendingRelease: Task<Void, Never>?
    var now: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var eventTime: (CGEvent) -> Double = { Double($0.timestamp) / 1_000_000_000 }
    private var hasKeyboardEvents = false
    var available: Bool {
        guard hasKeyboardEvents, let tap, source != nil, CFMachPortIsValid(tap) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    static let keyboardMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    static func supportsShortcut(_ info: CGEventTapInformation, process: pid_t) -> Bool {
        info.tappingProcess == process && info.processBeingTapped == 0 && info.enabled &&
        info.tapPoint == .cgSessionEventTap && info.options == .listenOnly &&
        info.eventsOfInterest & keyboardMask == keyboardMask
    }
    private func registeredKeyboardEvents() -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0, count <= 4096 else { return false }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        let capacity = count
        guard CGGetEventTapList(capacity, &taps, &count) == .success else { return false }
        return taps.prefix(Int(min(count, capacity))).contains { Self.supportsShortcut($0, process: ProcessInfo.processInfo.processIdentifier) }
    }
    func start() {
        stop()
        let mask = Self.keyboardMask
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { owner.handle(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
            // macOS can return a port after stripping keyboard events from its mask.
            // A non-nil port alone does not mean the shortcut is usable.
            hasKeyboardEvents = registeredKeyboardEvents()
            if !hasKeyboardEvents { stop() }
        }
        Logger(subsystem: "org.sotto.mac", category: "keyboard").notice("Shortcut listener ready: \(self.available)")
    }
    func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { resetGesture(); cancelled?(); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown && code == 53 { resetGesture(); cancelled?(); return }
        let matches = event.flags.intersection(ActivationShortcut.relevantFlags) == binding.flags
        let down = binding.keyCode == nil ? type == .flagsChanged && matches : type == .keyDown && code == Int64(binding.keyCode!) && matches && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        let timestamp = eventTime(event)
        if down && !held {
            held = true
            activationTimestamp = timestamp
            Logger(subsystem: "org.sotto.mac", category: "latency").notice("Shortcut event delivery delay ms: \(max(0, (self.now() - timestamp) * 1000))")
            if toggleMode { _ = pressed?() }
            else { apply(gesture.press(at: timestamp)) }
        }
        let up = type == .flagsChanged && !matches || (binding.keyCode != nil && type == .keyUp && code == Int64(binding.keyCode!))
        if held && up {
            held = false
            if !toggleMode { apply(gesture.release(at: timestamp)); scheduleRelease() }
        }
        if binding.keyCode == nil && held && type == .keyDown && !ActivationShortcut.modifierKeys.contains(UInt16(clamping: code)) {
            // A modifier used as part of another shortcut must not submit audio.
            resetGesture(); cancelled?()
        }
    }
    private func apply(_ effects: [ShortcutGesture.Effect]) {
        for effect in effects {
            switch effect {
            case .beginHold: if pressed?() != true { resetGesture() }
            case .handsFree: pendingRelease?.cancel(); pendingRelease = nil; handsFree?()
            case .submit: released?()
            }
        }
    }
    private func scheduleRelease() {
        pendingRelease?.cancel(); pendingRelease = nil
        guard let deadline = gesture.deadline else { return }
        pendingRelease = Task { [weak self] in
            // Let already queued input drain if the UI delivered a tap late.
            try? await Task.sleep(for: .seconds(max(0.01, deadline - (self?.now() ?? deadline))))
            guard !Task.isCancelled, let self else { return }
            self.apply(self.gesture.expire(at: self.now()))
        }
    }
    func resetGesture() {
        pendingRelease?.cancel(); pendingRelease = nil; held = false; gesture.reset()
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil; resetGesture(); hasKeyboardEvents = false
    }
}
