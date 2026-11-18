import AppKit
import ApplicationServices
import SottoTools

/// Windows are addressed by a per-process index from windows.list; identity is
/// rechecked against its title before applying a change.
struct WindowTool: Tool {
    let action: String
    var descriptor: ToolDescriptor {
        var p: [String: JSONValue] = [:]
        if action != "list" {
            p = ["pid": .object(["type": .string("integer")]), "index": .object(["type": .string("integer")]), "title": textProperty("Exact title from windows.list; refreshed before acting")]
        }
        if action == "manage" {
            p["operation"] = textProperty("Supported action", choices: ["minimize", "restore", "hide", "left", "right", "maximize"])
        }
        return ToolDescriptor(id: "windows." + action, description: "\(action.capitalized) accessible application windows. Requires Accessibility. Supports minimize, restore, hide and screen-relative arrangement; unsupported apps report errors.", properties: p, required: Array(p.keys), risk: .reversible, capabilities: [.accessibility], permissions: ["Accessibility"])
    }
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw ToolError.denied("Allow Accessibility access to manage windows") }
        if action == "list" {
            var rows: [JSONValue] = []
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                for (index, window) in windows(app.processIdentifier).enumerated() {
                    rows.append(.object(["pid": .number(Double(app.processIdentifier)), "index": .number(Double(index)), "title": .string(title(window)), "app": .string(app.localizedName ?? "")]))
                }
            }
            return ToolResult("Found \(rows.count) accessible windows", data: .array(Array(rows.prefix(100))))
        }
        guard case .number(let pid) = arguments.object?["pid"], pid > 0, pid <= Double(Int32.max),
              case .number(let index) = arguments.object?["index"], (0...100).contains(index),
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { throw ToolError.invalid("Choose a window from windows.list") }
        let current = windows(app.processIdentifier)
        guard current.indices.contains(Int(index)) else { throw ToolError.unavailable("Window no longer exists. List windows again.") }
        let window = current[Int(index)]
        guard title(window) == arguments.object?["title"]?.string else { throw ToolError.invalid("Window identity changed. List windows again.") }
        if action == "focus" {
            try set(window, kAXMinimizedAttribute, kCFBooleanFalse)
            guard app.activate(), AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw ToolError.unavailable("The application did not accept window focus") }
            for _ in 0..<10 {
                try Task.checkCancellation()
                var focused: CFTypeRef?
                let application = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(application, 0.5)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                   AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                   let focused, CFEqual(focused, window) {
                    return ToolResult("Focused the selected window and verified its foreground identity.")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            return ToolResult("Raised the selected window; foreground window focus could not be verified.", state: .partiallyCompleted)
        }
        let operation = arguments.object?["operation"]?.string ?? ""
        switch operation {
        case "hide":
            guard app.hide(), app.isHidden else { throw ToolError.unavailable("Application did not hide") }
        case "minimize", "restore":
            let value = operation == "minimize"
            try set(window, kAXMinimizedAttribute, value ? kCFBooleanTrue : kCFBooleanFalse)
            var actual: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &actual) == .success, (actual as? Bool) == value else { throw ToolError.unavailable("Window state could not be verified") }
        default:
            guard let screen = NSScreen.main, let primary = NSScreen.screens.first else { throw ToolError.unavailable("No display is available") }
            var rect = screen.visibleFrame
            if operation == "left" || operation == "right" {
                rect.size.width /= 2
                if operation == "right" { rect.origin.x += rect.width }
            }
            var point = CGPoint(x: rect.minX, y: primary.frame.maxY - rect.maxY)
            var size = rect.size
            guard let positionValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { throw ToolError.unavailable("Window geometry could not be created") }
            try set(window, kAXPositionAttribute, positionValue); try set(window, kAXSizeAttribute, sizeValue)
            var actualPosition: CFTypeRef?; var actualSize: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &actualPosition) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &actualSize) == .success,
                  let actualPosition, let actualSize else { throw ToolError.unavailable("Window geometry could not be read back") }
            var readPoint = CGPoint.zero; var readSize = CGSize.zero
            guard CFGetTypeID(actualPosition) == AXValueGetTypeID(), CFGetTypeID(actualSize) == AXValueGetTypeID(),
                  AXValueGetValue(unsafeDowncast(actualPosition, to: AXValue.self), .cgPoint, &readPoint),
                  AXValueGetValue(unsafeDowncast(actualSize, to: AXValue.self), .cgSize, &readSize),
                  abs(readPoint.x - point.x) < 3, abs(readPoint.y - point.y) < 3,
                  abs(readSize.width - size.width) < 3, abs(readSize.height - size.height) < 3 else {
                return ToolResult("The application adjusted or rejected the requested window arrangement.", state: .partiallyCompleted)
            }
        }
        return ToolResult("Updated the selected window")
    }
    @MainActor private func windows(_ pid: pid_t) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    private func title(_ window: AXUIElement) -> String {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }
    private func set(_ element: AXUIElement, _ key: String, _ value: CFTypeRef) throws {
        guard AXUIElementSetAttributeValue(element, key as CFString, value) == .success else { throw ToolError.unavailable("The application does not support this window operation") }
    }
}
