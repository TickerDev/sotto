import AppKit
import ApplicationServices
import EventKit
import IOKit.ps
import SottoTools

/// Compatibility adapters retain the existing native implementations and identifiers.
struct NamedTool: Tool {
    let descriptor: ToolDescriptor
    let base: any Tool
    let fixed: [String: JSONValue]
    init(_ id: String, _ base: any Tool, fixed: [String: JSONValue] = [:]) {
        self.base = base; self.fixed = fixed
        let d = base.descriptor
        let properties = (d.inputSchema.object?["properties"]?.object ?? [:]).filter { fixed[$0.key] == nil }
        let required: [String]
        if case .array(let values) = d.inputSchema.object?["required"] { required = values.compactMap(\.string).filter { fixed[$0] == nil } } else { required = [] }
        descriptor = ToolDescriptor(id: id, description: d.description, properties: properties, required: required, risk: d.risk, capabilities: d.capabilities, permissions: d.permissions)
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        return try await base.execute(arguments: .object((arguments.object ?? [:]).merging(fixed) { _, fixed in fixed }))
    }
}

struct FileManagementTool: Tool {
    let action: String
    var descriptor: ToolDescriptor {
        var properties = ["path": textProperty("Existing absolute local path")]
        if action == "move" { properties["destination"] = textProperty("Full destination path, including filename") }
        if action == "rename" { properties["name"] = textProperty("New filename, no path separators") }
        return ToolDescriptor(id: "files." + action, description: action == "info" ? "Read local file metadata" : "Move or rename a file without overwriting an existing item. Requires approval.", properties: properties, required: Array(properties.keys), risk: action == "info" ? .read : .consequential, capabilities: [.files], undo: action == "info" ? nil : "Move the returned destination back to the original path after approval.")
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let source = try FilePolicy.url(arguments.object?["path"]?.string ?? "")
        if action == "info" {
            let v = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey, .typeIdentifierKey])
            return ToolResult("Information for \(source.lastPathComponent)", data: .object([
                "path": .string(source.path), "bytes": .number(Double(v.fileSize ?? 0)),
                "directory": .bool(v.isDirectory == true), "type": .string(v.typeIdentifier ?? ""),
                "modified": v.contentModificationDate.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null
            ]))
        }
        let destination: URL
        if action == "rename" {
            let name = arguments.object?["name"]?.string ?? ""
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { throw ToolError.invalid("Choose a filename without path separators") }
            destination = source.deletingLastPathComponent().appendingPathComponent(name)
        } else {
            let path = arguments.object?["destination"]?.string ?? ""
            guard path.hasPrefix("/") || path.hasPrefix("~/"), !path.contains("\0") else { throw ToolError.invalid("Use an absolute destination") }
            destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        }
        let parent = try FilePolicy.url(destination.deletingLastPathComponent().path)
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        guard source != target, !FileManager.default.fileExists(atPath: target.path) else { throw ToolError.invalid("Destination already exists; nothing was moved") }
        // FileManager move refuses collisions; never remove the destination first.
        try FileManager.default.moveItem(at: source, to: target)
        guard FileManager.default.fileExists(atPath: target.path), !FileManager.default.fileExists(atPath: source.path) else {
            return ToolResult("Move could not be fully verified. Inspect both locations before retrying.", state: .partiallyCompleted)
        }
        return ToolResult("Moved \(source.lastPathComponent) to \(target.path)", data: .object(["original": .string(source.path), "path": .string(target.path)]))
    }
}

struct AppLifecycleTool: Tool {
    let action: String
    var descriptor: ToolDescriptor { ToolDescriptor(id: "apps." + action, description: action == "list" ? "List running and installed applications in standard application folders" : "\(action.capitalized) a running application by bundle identifier; quit is graceful and can be blocked by unsaved work.", properties: action == "list" ? [:] : ["bundle_id": textProperty("Exact application bundle identifier")], required: action == "list" ? [] : ["bundle_id"], risk: action == "quit" ? .consequential : .reversible, capabilities: [.applications]) }
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "list" {
            var apps: [String: JSONValue] = [:]
            for root in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
                let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? []
                for url in urls where url.pathExtension == "app" {
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                    apps[id] = .object(["bundle_id": .string(id), "name": .string(url.deletingPathExtension().lastPathComponent), "running": .bool(!NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty)])
                }
            }
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                if let id = app.bundleIdentifier { apps[id] = .object(["bundle_id": .string(id), "name": .string(app.localizedName ?? id), "running": .bool(true)]) }
            }
            return ToolResult("Found \(apps.count) applications", data: .array(apps.keys.sorted().compactMap { apps[$0] }))
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments.object?["bundle_id"]?.string ?? "").first else { throw ToolError.unavailable("Application is not running") }
        if action == "activate" {
            guard app.activate(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return ToolResult("Activation requested; foreground change is not yet confirmed.", state: .partiallyCompleted) }
            return ToolResult("Activated \(app.localizedName ?? "application")")
        }
        guard app.terminate() else { throw ToolError.unavailable("Application declined to quit; check for unsaved work") }
        for _ in 0..<20 {
            if app.isTerminated { return ToolResult("Application quit") }
            try await Task.sleep(for: .milliseconds(100))
        }
        return ToolResult("Quit requested. The application is still running; check for unsaved work.", state: .partiallyCompleted)
    }
}

struct ContextTool: Tool {
    let action: String
    var descriptor: ToolDescriptor {
        ToolDescriptor(id: action, description: action == "selection.read" ? "Read selected text from the focused accessible control, after approval to share it with the active reasoning provider." : action == "clipboard.read" ? "Read clipboard text after approval to share it with the active reasoning provider." : action == "clipboard.write" ? "Replace clipboard with requested text after approval." : "Read the current foreground application name and bundle identifier.", properties: action == "clipboard.write" ? ["text": textProperty("Text to place on the clipboard")] : [:], required: action == "clipboard.write" ? ["text"] : [], risk: action == "screen.context" ? .read : .consequential, capabilities: action == "selection.read" ? [.accessibility] : action.hasPrefix("clipboard") ? [.clipboard] : [.screen], permissions: action == "selection.read" ? ["Accessibility", "Approval to share selected text"] : [])
    }
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "screen.context" {
            guard let c = ForegroundContext.current() else { throw ToolError.unavailable("No foreground application") }
            return ToolResult("You’re using \(c.name)", data: .object(["name": .string(c.name), "bundle_id": .string(c.bundleID)]))
        }
        if action == "clipboard.write" {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let text = arguments.object?["text"]?.string ?? ""
            guard pasteboard.setString(text, forType: .string), pasteboard.string(forType: .string) == text else { throw ToolError.unavailable("Clipboard write failed") }
            return ToolResult("Copied text to the clipboard")
        }
        let text: String
        if action == "clipboard.read" {
            guard let value = NSPasteboard.general.string(forType: .string) else { throw ToolError.unavailable("Clipboard has no supported text") }
            text = value
        } else {
            guard AXIsProcessTrusted() else { throw ToolError.denied("Allow Accessibility access to read selected text") }
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused else { throw ToolError.unavailable("The application does not expose a focused control") }
            var selected: CFTypeRef?
            guard AXUIElementCopyAttributeValue(unsafeDowncast(focused, to: AXUIElement.self), kAXSelectedTextAttribute as CFString, &selected) == .success, let value = selected as? String, !value.isEmpty else { throw ToolError.unavailable("No accessible selected text. Select text in the original application first.") }
            text = value
        }
        return ToolResult("Read text (untrusted content)", data: .object(["text": .string(String(text.prefix(16_000))), "truncated": .bool(text.count > 16_000)]))
    }
}

struct SystemInfoTool: Tool {
    let descriptor = ToolDescriptor(id: "system.info", description: "Read macOS version, memory, uptime and available home-volume storage", properties: [:], required: [], risk: .read, capabilities: [.system])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try Task.checkCancellation()
        let storage = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        var batteries: [JSONValue] = []
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let details = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                batteries.append(.object([
                    "name": .string(details[kIOPSNameKey] as? String ?? "Battery"),
                    "charging": .bool(details[kIOPSIsChargingKey] as? Bool ?? false),
                    "current_capacity": .number((details[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0),
                    "max_capacity": .number((details[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 0),
                    "power_source": .string(details[kIOPSPowerSourceStateKey] as? String ?? "Unknown")
                ]))
            }
        }
        return ToolResult(ProcessInfo.processInfo.operatingSystemVersionString, data: .object([
            "batteries": .array(batteries),
            "os": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "memory_bytes": .number(Double(ProcessInfo.processInfo.physicalMemory)),
            "uptime_seconds": .number(ProcessInfo.processInfo.systemUptime),
            "available_storage_bytes": .number((storage[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0)
        ]))
    }
}
