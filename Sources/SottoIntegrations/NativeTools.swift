import AppKit
import EventKit
import OSLog
import SottoTools

public enum NativeTools {
    public static func registry() -> ToolRegistry { ToolRegistry([SpotifyTool(), FolderTool(), FileTool(), SearchFilesTool(), ApplicationTool(), CreateReminderTool(), ListRemindersTool(), ListCalendarEventsTool()]) }
}
public enum FilePolicy {
    public static let supportedDocumentExtensions = ["pdf", "txt", "md", "rtf", "docx", "xlsx", "pptx", "png", "gif", "jpg", "jpeg", "heic", "mp3", "mp4", "mov", "pages", "numbers", "key"]
    public static func openingURL(_ path: String) throws -> URL {
        let url = try self.url(path)
        let values = try url.resourceValues(forKeys: [.isApplicationKey, .isRegularFileKey, .isPackageKey])
        if values.isApplication == true { return url }
        guard supportedDocumentExtensions.contains(url.pathExtension.lowercased()), values.isRegularFile == true || values.isPackage == true else {
            throw ToolError.denied("This file type cannot be opened by Sotto. Reveal it in Finder instead.")
        }
        return url
    }
    public static func url(_ path: String) throws -> URL {
        guard !path.contains("\0"), path.hasPrefix("/") || path.hasPrefix("~/") else { throw ToolError.invalid("Use an absolute local path") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError.unavailable("File does not exist or is inaccessible") }; return url
    }
}
struct FolderTool: Tool {
    let descriptor = ToolDescriptor(id: "open_folder", description: "Open a folder in Finder", properties: ["path": textProperty("Absolute folder path or ~/Downloads")], required: ["path"], risk: .reversible, capabilities: [.files])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        let url = try FilePolicy.url(arguments.object?["path"]?.string ?? "")
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue, (try url.resourceValues(forKeys: [.isPackageKey])).isPackage != true else { throw ToolError.invalid("Choose a folder, not a file or application") }
        try Task.checkCancellation()
        try await MainActor.run { guard NSWorkspace.shared.open(url) else { throw ToolError.unavailable("Finder could not open this folder") } }
        return ToolResult("Opened \(url.lastPathComponent) in Finder")
    }
}
struct FileTool: Tool {
    let descriptor = ToolDescriptor(id: "open_file", description: "Open a local document, media file or macOS application. Supported file extensions: \(FilePolicy.supportedDocumentExtensions.joined(separator: ", ")). Use action open when asked to open a supported file. Action reveal only selects it in Finder; use that when the user asks to show its location, or opening its type is unsupported.", properties: ["path": textProperty("Absolute file path"), "action": textProperty("Action", choices: ["open", "reveal"])], required: ["path", "action"], risk: .reversible, capabilities: [.files])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let path = arguments.object?["path"]?.string ?? ""
        let url = try arguments.object?["action"]?.string == "reveal" ? FilePolicy.url(path) : FilePolicy.openingURL(path)
        try Task.checkCancellation()
        return try await MainActor.run {
            if arguments.object?["action"]?.string == "reveal" { NSWorkspace.shared.activateFileViewerSelecting([url]); return ToolResult("Revealed \(url.lastPathComponent)") }
            guard NSWorkspace.shared.open(url) else { throw ToolError.unavailable("macOS could not open this file") }
            return ToolResult("macOS opened \(url.lastPathComponent)")
        }
    }
}
@MainActor private final class SpotlightSearch {
    let query = NSMetadataQuery()
    var observer: NSObjectProtocol?
    var continuation: CheckedContinuation<ToolResult, Error>?
    var timeout: Task<Void, Never>?
    var searchName = ""
    func search(_ name: String) async throws -> ToolResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                searchName = name
                query.searchScopes = [FileManager.default.homeDirectoryForCurrentUser]
                query.predicate = name == ".pdf"
                    ? NSPredicate(format: "%K ENDSWITH[cd] %@", NSMetadataItemFSNameKey, name)
                    : NSCompoundPredicate(orPredicateWithSubpredicates: FileSearchRanking.terms(name).map { NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0) })
                query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
                observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in Task { @MainActor in self?.finish() } }
                timeout = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { finish(error: ToolError.unavailable("File search took too long. Please try again.")) } }
                if !query.start() { finish(error: ToolError.unavailable("Spotlight search could not start")) }
            }
        } onCancel: { Task { @MainActor in self.finish(error: CancellationError()) } }
    }
    func finish(error: Error? = nil) {
        guard let continuation else { return }; self.continuation = nil
        query.disableUpdates(); timeout?.cancel()
        defer { query.stop() }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let error { continuation.resume(throwing: error); return }
        let candidates = (0..<min(query.resultCount, 500)).compactMap { index -> FileSearchMatch? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return FileSearchMatch(path: path, modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)
        }
        let files = Array(FileSearchRanking.ranked(candidates, query: searchName).prefix(20))
        Logger(subsystem: "org.sotto.mac", category: "file-search").notice("Search completed: indexed=\(self.query.resultCount), candidates=\(candidates.count), documents=\(files.count)")
        let summary = files.isEmpty ? "No matching indexed files found." : "Found \(files.count) matching \(files.count == 1 ? "file" : "files")."
        continuation.resume(returning: ToolResult(summary, data: FileSearchResults(files: files).data))
    }
}
struct SearchFilesTool: Tool {
    let descriptor = ToolDescriptor(id: "find_files", description: "Find files by name using Spotlight. Returns ranked actionable file matches; résumé searches also match CV and accented names. Sotto presents matches with Open and Finder actions; do not ask for a folder when matches exist.", properties: ["name": textProperty("Filename or subject, such as resume. Not a Spotlight expression; do not assume PDF unless requested.")], required: ["name"], risk: .read, capabilities: [.files])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let name = arguments.object?["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { throw ToolError.invalid("Say which file you want to find.") }
        let indexed = try await SpotlightSearch().search(name)
        guard FileSearchResults.decode(indexed.data)?.files.isEmpty == true else { return indexed }
        let files = try await DocumentFolderSearch().search(name)
        try Task.checkCancellation()
        return ToolResult(files.isEmpty ? "No matching accessible files found. Try another name." : "Found \(files.count) matching \(files.count == 1 ? "file" : "files").", data: FileSearchResults(files: files).data)
    }
}
struct ApplicationTool: Tool {
    let descriptor = ToolDescriptor(id: "applications", description: "List running applications or open an installed macOS application (for example com.google.Chrome or com.apple.Safari)", properties: ["action": textProperty("Action", choices: ["list", "open"]), "bundle_id": textProperty("Bundle identifier; empty for list")], required: ["action", "bundle_id"], risk: .reversible, capabilities: [.applications])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try Task.checkCancellation()
        if arguments.object?["action"]?.string == "list" {
            return await MainActor.run { ToolResult("Running applications", data: .array(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map { .object(["name": .string($0.localizedName ?? ""), "bundle_id": .string($0.bundleIdentifier ?? "")]) })) }
        }
        let id = arguments.object?["bundle_id"]?.string ?? ""
        let url = try await MainActor.run { guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { throw ToolError.unavailable("Application not found") }; return url }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return ToolResult("Opened \(url.deletingPathExtension().lastPathComponent)")
    }
}
@MainActor private enum RemindersAccess {
    static let store = EKEventStore()
    static func authorize() async throws {
        guard try await store.requestFullAccessToReminders() else { throw ToolError.denied("Allow Reminders access in System Settings") }
    }
}
struct CreateReminderTool: Tool {
    let descriptor = ToolDescriptor(id: "create_reminder", description: "Create a reminder", properties: ["title": textProperty("Reminder title"), "due": textProperty("ISO8601 date and time with timezone")], required: ["title", "due"], risk: .reversible, capabilities: [.reminders])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        guard let title = arguments.object?["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let due = arguments.object?["due"]?.string, let date = ISO8601DateFormatter().date(from: due) else { throw ToolError.invalid("Provide a title and ISO8601 due date") }
        try await RemindersAccess.authorize(); try Task.checkCancellation()
        guard let calendar = RemindersAccess.store.defaultCalendarForNewReminders() else { throw ToolError.unavailable("Set a default Reminders list first") }
        let reminder = EKReminder(eventStore: RemindersAccess.store); reminder.title = title; reminder.calendar = calendar
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: date)
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        try RemindersAccess.store.save(reminder, commit: true)
        guard RemindersAccess.store.calendarItem(withIdentifier: reminder.calendarItemIdentifier) != nil else { throw ToolError.unavailable("Reminder saved but verification failed") }
        return ToolResult("Created “\(title)” for \(date.formatted())", data: .string(reminder.calendarItemIdentifier))
    }
}
struct ListRemindersTool: Tool {
    let descriptor = ToolDescriptor(id: "list_reminders", description: "List incomplete reminders", properties: [:], required: [], risk: .read, capabilities: [.reminders])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try await RemindersAccess.authorize(); try Task.checkCancellation()
        let store = RemindersAccess.store
        let items: [String] = await withCheckedContinuation { c in store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { @Sendable reminders in c.resume(returning: (reminders ?? []).map { $0.title ?? "Untitled" }) } }
        return ToolResult("Found \(items.count) incomplete reminders", data: .array(items.prefix(30).map { .string($0) }))
    }
}
public struct ForegroundContext: Sendable {
    public let name: String; public let bundleID: String
    @MainActor public static func current() -> ForegroundContext? { guard let app = NSWorkspace.shared.frontmostApplication else { return nil }; return .init(name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "") }
}
