#if DEBUG
import AppKit
import ApplicationServices
import Contacts
import EventKit
import UserNotifications
import SottoIntegrations
import SottoTools

/// Explicit debug acceptance only. Reports statuses, never personal content.
/// No permission prompts, external communication or model requests.
@MainActor public enum NativeAcceptanceReport {
    public static func run(to destination: URL) async throws {
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"
        guard destination.resolvingSymlinksInPath().path.hasPrefix(temp), !FileManager.default.fileExists(atPath: destination.path) else { throw ToolError.denied("Choose a new report file in the temporary directory") }
        var rows: [JSONValue] = []
        func record(_ tool: String, _ status: String, _ detail: String) {
            rows.append(.object(["tool": .string(tool), "status": .string(status), "detail": .string(detail)]))
        }
        if CommandLine.arguments.contains("--notes-permission-only") || CommandLine.arguments.contains("--mail-permission-only") {
            let mail = CommandLine.arguments.contains("--mail-permission-only")
            let prefix = mail ? "mail" : "appleNotes"
            let app = mail ? "Mail" : "Notes"
            let status = mail ? AppleMailAuthorization.status() : AppleNotesAuthorization.status()
            let state: String = switch status { case .allowed: "allowed"; case .notRequested: "notRequested"; case .denied: "denied"; case .unavailable: "unavailable" }
            record(prefix + ".permission", "observed", "Native per-target Automation preflight: " + state + ". No " + app + " launch, consent prompt, account or content read/write.")
            record(prefix + ".*", "pending", "Real owned-account operations and just-in-time permission UI acceptance remain required.")
            let bytes = try JSONEncoder().encode(JSONValue.object(["generated_at": .string(ISO8601DateFormatter().string(from: Date())), "identity": .string(Bundle.main.bundleIdentifier ?? ""), "checks": .array(rows)]))
            try bytes.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return
        }
        let registry = NativeTools.registry()
        if CommandLine.arguments.contains("--windows-only") {
            if AXIsProcessTrusted() { try await windows(registry, record: record) }
            else { record("windows.* / selection.read", "blocked", "Accessibility unavailable; no prompt.") }
            let bytes = try JSONEncoder().encode(JSONValue.object(["identity": .string(Bundle.main.bundleIdentifier ?? ""), "checks": .array(rows)]))
            try bytes.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return
        }
        for id in ["apps.list", "screen.context", "system.info", "audio.output"] {
            do {
                let args: JSONValue = id == "audio.output" ? .object(["action": .string("list"), "device_id": .number(0)]) : .object([:])
                let result = try await registry.tool(id).execute(arguments: args)
                record(id, result.state == .success ? "observed" : "partial", "Actual native read executed; private values omitted from this report.")
            } catch { record(id, "failed", "Native read failed; no success inferred.") }
        }
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            do { _ = try await CalendarAcceptance.run(); record("calendar.create/list", "observed", "Owned test event created, listed, duplicate request reused and cleanup verified.") }
            catch { record("calendar.create/list", "failed", "Owned-event check did not fully complete; see Calendar for any remaining Sotto verification event.") }
            do { try await calendarUpdate(registry); record("calendar.update", "observed", "Owned fixture updated through the production tool, read back and removed.") }
            catch { record("calendar.update", "failed", "Owned update/cleanup did not fully complete; no success inferred.") }
        } else { record("calendar.*", "blocked", "Sotto does not have existing Calendar full access. No access prompt or event write.") }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            do { try await reminderCheck(registry); record("reminders.create/list/complete", "observed", "Owned fixture created, found by the production title filter, completed, read back and removed.") }
            catch { record("reminders.*", "failed", "Owned reminder check/cleanup did not fully complete; no success inferred.") }
        } else { record("reminders.*", "blocked", "Existing full access unavailable; no prompt.") }

        if AXIsProcessTrusted() {
            try await windows(registry, record: record)
        } else {
            record("windows.* / selection.read", "blocked", "Sotto Accessibility access is unavailable. No permission prompt.")
        }
        record("screen.capture/readText", "pending", CGPreflightScreenCaptureAccess() ? "Access exists; controlled visible-content capture/OCR acceptance remains required. No screenshot taken." : "Screen Recording access unavailable. No screenshot or prompt.")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            await timerCheck(registry, record: record)
        } else { record("timers.delivery", "blocked", "Existing notification authorization unavailable; no prompt or timer.") }
        record("contacts.*", "pending", CNContactStore.authorizationStatus(for: .contacts) == .authorized ? "Existing access is available; Contacts acceptance remains required." : "Contacts access unavailable; just-in-time permission required. No contact read or write.")

        for id in ["media.playPause", "audio.output.select", "shortcuts.run", "browser.currentTab/readPage/openLink"] {
            record(id, "pending", "Requires a suitable running app/device or explicitly selected safe fixture. No personal playback, output route, shortcut or tab was changed.")
        }
        let data = try JSONEncoder().encode(JSONValue.object(["generated_at": .string(ISO8601DateFormatter().string(from: Date())), "identity": .string(Bundle.main.bundleIdentifier ?? ""), "checks": .array(rows)]))
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    private static func calendarUpdate(_ registry: ToolRegistry) async throws {
        let title = "Sotto owned update check " + UUID().uuidString
        let start = Date().addingTimeInterval(86_400), end = start.addingTimeInterval(300)
        let formatter = ISO8601DateFormatter()
        let created = try await registry.tool("calendar.create").execute(arguments: .object(["title": .string(title), "start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: end))]))
        guard let id = created.data.object?["identifier"]?.string else { throw ToolError.unavailable("No owned event reference") }
        let store = EKEventStore()
        var outcome: Error?
        do {
            let result = try await registry.tool("calendar.update").execute(arguments: .object(["id": .string(id), "current_title": .string(title), "title": .string(title + " updated"), "start": created.data.object?["start"] ?? .null, "end": created.data.object?["end"] ?? .null]))
            guard result.state == .success, store.event(withIdentifier: id)?.title == title + " updated" else { throw ToolError.unavailable("Update not observed") }
        } catch { outcome = error }
        guard let owned = store.event(withIdentifier: id), [title, title + " updated"].contains(owned.title),
              abs(owned.startDate.timeIntervalSince(start)) < 2, abs(owned.endDate.timeIntervalSince(end)) < 2,
              owned.attendees?.isEmpty != false else { throw ToolError.denied("Owned event changed; cleanup refused") }
        try store.remove(owned, span: .thisEvent, commit: true)
        guard store.event(withIdentifier: id) == nil else { throw ToolError.unavailable("Cleanup unverified") }
        if let outcome { throw outcome }
    }
    private static func reminderCheck(_ registry: ToolRegistry) async throws {
        let title = "Sotto owned reminder check " + UUID().uuidString
        let due = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        let result = try await registry.tool("reminders.create").execute(arguments: .object(["title": .string(title), "due": .string(due)]))
        guard let id = result.data.string else { throw ToolError.unavailable("No owned reminder reference") }
        let store = EKEventStore()
        var outcome: Error?
        do {
            let listed = try await registry.tool("reminders.list").execute(arguments: .object(["query": .string(title)]))
            guard case .array(let rows) = listed.data, rows.contains(where: { $0.object?["id"]?.string == id }) else { throw ToolError.unavailable("Owned reminder not in results") }
            let completed = try await registry.tool("reminders.complete").execute(arguments: .object(["id": .string(id), "title": .string(title)]))
            guard completed.state == .success, (store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted == true else { throw ToolError.unavailable("Reminder completion unverified") }
        } catch { outcome = error }
        guard let owned = store.calendarItem(withIdentifier: id) as? EKReminder, owned.title == title else { throw ToolError.denied("Owned reminder changed; cleanup refused") }
        try store.remove(owned, commit: true)
        guard store.calendarItem(withIdentifier: id) == nil else { throw ToolError.unavailable("Reminder cleanup unverified") }
        if let outcome { throw outcome }
    }
    private static func timerCheck(_ registry: ToolRegistry, record: (String, String, String) -> Void) async {
        var id: String?
        do {
            let result = try await registry.tool("timers.start").execute(arguments: .object(["seconds": .number(2), "name": .string("Sotto notification check")]))
            guard let reference = result.data.object?["id"]?.string else { throw ToolError.unavailable("No timer reference") }
            id = reference
            record("timers.start", result.state == .success ? "observed" : "partial", "Actual native scheduling result; no delivery inferred.")
            try await Task.sleep(for: .seconds(4))
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            record("timers.delivery", delivered.contains(where: { $0.request.identifier == reference }) ? "observed" : "pending",
                   "Notification Center presence checked for the owned timer only. Banner/sound and sleep/Focus behavior still need observation.")
            let cancelled = try await registry.tool("timers.cancel").execute(arguments: .object(["id": .string(reference)]))
            record("timers.cancel", cancelled.state == .success ? "observed" : "partial", "Owned pending/delivered alert removal and saved-record cleanup checked.")
            id = nil
        } catch { record("timers.delivery", "failed", "Owned notification check did not fully complete.") }
        if let id { _ = try? await registry.tool("timers.cancel").execute(arguments: .object(["id": .string(id)])) }
    }
    private static func windows(_ registry: ToolRegistry, record: (String, String, String) -> Void) async throws {
        let previous = NSWorkspace.shared.frontmostApplication
        let token = UUID().uuidString
        let title = "Sotto owned Accessibility check " + token
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--native-fixture", token]
        configuration.createsNewApplicationInstance = true; configuration.activates = true; configuration.addsToRecentItems = false
        let helper = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        guard helper.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw ToolError.unavailable("Separate fixture application was not launched") }
        defer { _ = helper.terminate(); _ = previous?.activate() }
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == helper.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == helper.processIdentifier else {
            record("selection.read/windows.*", "blocked", "Owned external fixture did not become foreground. No personal selection read.")
            return
        }
        do {
            let selected = try await registry.tool("selection.read").execute(arguments: .object([:]))
            record("selection.read", selected.data.object?["text"]?.string == "Sotto controlled selection fixture." ? "observed" : "partial", "Only the owned NSTextView selection was checked; no personal selected text read.")
        } catch { record("selection.read", "failed", "Owned selection not observed: " + error.localizedDescription) }
        do {
            let listed = try await registry.tool("windows.list").execute(arguments: .object([:]))
            guard case .array(let values) = listed.data, let target = values.first(where: { $0.object?["pid"] == .number(Double(helper.processIdentifier)) && $0.object?["title"]?.string == title }), let row = target.object else { throw ToolError.unavailable("Owned window not listed") }
            record("windows.list", "observed", "Owned process/window found through production AX enumeration.")
            let identity: [String: JSONValue] = ["pid": row["pid"]!, "index": row["index"]!, "title": row["title"]!]
            for operation in ["minimize", "restore", "left", "right", "maximize"] {
                do {
                    let result = try await registry.tool("windows.manage").execute(arguments: .object(identity.merging(["operation": .string(operation)]) { _, value in value }))
                    record("windows.manage." + operation, result.state == .success ? "observed" : "partial", result.state == .success ? "Owned test window changed and read back." : result.summary)
                } catch { record("windows.manage." + operation, "failed", error.localizedDescription) }
            }
            let focused = try await registry.tool("windows.focus").execute(arguments: .object(identity))
            record("windows.focus", focused.state == .success ? "observed" : "partial", "Owned focus result retained exactly; raising alone is not proof of keyboard focus.")
        } catch { record("windows.*", "failed", "Owned window check did not fully complete.") }
    }
}
#endif
