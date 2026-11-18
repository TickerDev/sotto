import AppKit
import EventKit
import OSLog
import SottoTools

public enum NativeTools {
    public static func registry(sottoSettings: (any SottoSettingsBridge)? = nil, webSearch: (any WebSearchProvider)? = nil) -> ToolRegistry {
        let tools: [any Tool] = [
            MailDraftTool(),
            AppleMailTool(action: "accounts"), AppleMailTool(action: "search"), AppleMailTool(action: "read"),
            AppleNotesTool(action: "list"), AppleNotesTool(action: "search"), AppleNotesTool(action: "read"), AppleNotesTool(action: "create"), AppleNotesTool(action: "update"),
            NotesTool(action: "list"), NotesTool(action: "search"), NotesTool(action: "read"), NotesTool(action: "create"), NotesTool(action: "update"),
            ContactsTool(action: "search"), ContactsTool(action: "get"), ContactsTool(action: "create"), ContactsTool(action: "update"),
            BrowserTool(action: "currentTab"), BrowserTool(action: "readPage"), BrowserTool(action: "find"), BrowserTool(action: "openLink"),
            AliasTool(action: "list"), AliasTool(action: "save"), AliasTool(action: "remove"),
            FileIndexTool(), ScopedFileSearchTool(),
            NamedTool("files.open", FileTool(), fixed: ["action": .string("open")]),
            NamedTool("files.reveal", FileTool(), fixed: ["action": .string("reveal")]),
            NamedTool("files.read", ReadDocumentTool()),
            FileManagementTool(action: "info"), FileManagementTool(action: "move"), FileManagementTool(action: "rename"),
            NamedTool("apps.open", ApplicationTool(), fixed: ["action": .string("open")]),
            AppLifecycleTool(action: "list"), AppLifecycleTool(action: "activate"), AppLifecycleTool(action: "quit"),
            NamedTool("calendar.list", ListCalendarEventsTool()),
            NamedTool("calendar.create", CreateCalendarEventTool()),
            CompleteReminderTool(), UpdateCalendarTool(),
            NamedTool("reminders.list", ListRemindersTool()),
            NamedTool("reminders.create", CreateReminderTool()),
            TimerTool(action: "start"), TimerTool(action: "list"), TimerTool(action: "cancel"),
            ContextTool(action: "screen.context"), ContextTool(action: "selection.read"),
            ContextTool(action: "clipboard.read"), ContextTool(action: "clipboard.write"),
            WindowTool(action: "list"), WindowTool(action: "focus"), WindowTool(action: "manage"),
            NamedTool("audio.volume", SystemSettingsTool(), fixed: ["setting": .string("volume")]),
            NamedTool("system.openSettings", SystemSettingsTool(), fixed: ["setting": .string("open_pane"), "action": .string("open")]),
            NamedTool("media.next", SpotifyTool(), fixed: ["action": .string("next")]),
            NamedTool("media.previous", SpotifyTool(), fixed: ["action": .string("previous")]),
            MediaPlaybackTool(), AudioOutputTool(), ScreenTool(action: "capture"), ScreenTool(action: "readText"), SystemInfoTool(),
            WebDocumentTool(action: "download"), WebDocumentTool(action: "readPDF"),
            ImageSearchTool(), DocumentSearchTool(), ResearchTool(provider: webSearch), WebSearchTool(provider: webSearch), WebPageTool(action: "fetch"), WebPageTool(action: "extractLinks"), WebOpenTool(),
            ShortcutsTool(action: "list"), ShortcutsTool(action: "run"),
            SpotifyTool(),
            FolderTool(),
            FileTool(),
            SearchFilesTool(),
            ApplicationTool(),
            CreateReminderTool(),
            ListRemindersTool(),
            ListCalendarEventsTool(),
            CreateCalendarEventTool(),
            ReadDocumentTool(),
            SystemSettingsTool(),
            SystemSettingsUITool(),
            SystemPowerTool(),
            SottoSettingsTool(bridge: sottoSettings)
        ]
        let base = ToolRegistry(tools)
        return ToolRegistry(tools + [WorkflowTool(registry: base), ListWorkflowsTool(), SaveWorkflowTool(registry: base), RemoveWorkflowTool(), ListWorkflowRunsTool(), ResumeWorkflowTool(registry: base)])
    }
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
    func search(_ name: String, scopes: [URL]? = nil, content: Bool = false, fileExtension: String = "", modifiedSince: Date? = nil) async throws -> ToolResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                searchName = name
                query.searchScopes = scopes ?? [NSMetadataQueryLocalComputerScope]
                query.predicate = name == ".pdf"
                    ? NSPredicate(format: "%K ENDSWITH[cd] %@", NSMetadataItemFSNameKey, name)
                    : NSCompoundPredicate(orPredicateWithSubpredicates: FileSearchRanking.terms(name).map { NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0) })
                if content {
                    query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, name),
                        NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemTextContentKey, name)
                    ])
                }
                var predicates = [query.predicate!]
                if !fileExtension.isEmpty {
                    predicates.append(NSPredicate(format: "%K ENDSWITH[cd] %@", NSMetadataItemFSNameKey, "." + fileExtension))
                }
                if let modifiedSince {
                    predicates.append(NSPredicate(format: "%K >= %@", NSMetadataItemFSContentChangeDateKey, modifiedSince as NSDate))
                }
                query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
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
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.isReadableFile(atPath: path), !DocumentSearchPrivacy.isExcluded(fileURL) else { return nil }
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
    let descriptor = ToolDescriptor(id: "list_reminders", description: "List up to 30 incomplete reminders, optionally filtering their titles by a literal query. At most 5000 fetched reminders are examined; narrow the query when needed.", properties: ["query": textProperty("Optional literal title fragment")], required: [], risk: .read, capabilities: [.reminders])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let query = arguments.object?["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard query.count <= 120, query.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Use a short literal reminder title") }
        try await RemindersAccess.authorize(); try Task.checkCancellation()
        let store = RemindersAccess.store
        let items: [(String, String, String)] = await withCheckedContinuation { c in store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { @Sendable reminders in c.resume(returning: (reminders ?? []).prefix(5000).filter { query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query) }.prefix(30).map { ($0.calendarItemIdentifier, $0.title ?? "Untitled", $0.calendar.title) }) } }
        return ToolResult("Found \(items.count) incomplete reminders", data: .array(items.prefix(30).map { .object(["id": .string($0.0), "title": .string($0.1), "list": .string($0.2)]) }))
    }
}
public struct ForegroundContext: Sendable {
    public let name: String; public let bundleID: String
    @MainActor public static func current() -> ForegroundContext? { guard let app = NSWorkspace.shared.frontmostApplication else { return nil }; return .init(name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "") }
}

struct ScopedFileSearchTool: Tool {
    let descriptor = ToolDescriptor(id: "files.search", description: "Search accessible files in Documents, Downloads and Desktop using local Spotlight names, metadata and optionally Spotlight content. mode semantic searches Sotto’s automatic local content cache, with Spotlight content fallback while it warms up. Index coverage varies. Returns ranked matches; ask the user to choose when ambiguous. Excluded folders are omitted.", properties: [
        "name": textProperty("Filename or content phrase; .pdf for recent PDFs"),
        "mode": textProperty("Search mode", choices: ["filename", "content", "semantic"]),
        "extension": textProperty("Optional file extension without dot, or empty"),
        "modified_since": textProperty("Optional ISO8601 earliest modification timestamp with time zone, or empty")
    ], required: ["name", "mode", "extension", "modified_since"], risk: .read, capabilities: [.files])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let name = arguments.object?["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ext = arguments.object?["extension"]?.string ?? ""
        let modified = arguments.object?["modified_since"]?.string ?? ""
        let date = modified.isEmpty ? nil : ISO8601DateFormatter().date(from: modified)
        guard !name.isEmpty, ext.count <= 16, ext.allSatisfy({ $0.isLetter || $0.isNumber }), modified.isEmpty || date != nil else { throw ToolError.invalid("Provide a search phrase, simple extension and valid modification date") }
        if arguments.object?["mode"]?.string == "semantic" {
            let cached = try await LocalDocumentIndex.shared.search(query: name, fileExtension: ext, modifiedSince: date)
            if let matches = FileSearchResults.decode(cached.data), !matches.files.isEmpty { return cached }
            // Spotlight is already indexed; never send the user to a manual setup page
            // just because Sotto's richer local cache is still warming up.
            return try await SpotlightSearch().search(name, scopes: nil, content: true, fileExtension: ext, modifiedSince: date)
        }
        return try await SpotlightSearch().search(name, scopes: nil, content: arguments.object?["mode"]?.string == "content", fileExtension: ext, modifiedSince: date)
    }
}
