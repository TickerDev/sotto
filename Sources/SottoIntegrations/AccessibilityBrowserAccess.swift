import AppKit
import ApplicationServices
import SottoTools

/// All AX objects remain on this actor, away from the UI thread. Nothing is
/// observed continuously; handles exist only after an explicit tool request.
actor AccessibilityBrowserAccess: BrowserAccess {
    static let shared = AccessibilityBrowserAccess()
    private struct Entry {
        let reference: BrowserPageReference
        let pid: pid_t
        let window: AXUIElement
        let area: AXUIElement
        let created: ContinuousClock.Instant
        var links: [BrowserPageLink] = []
    }
    private var entries: [String: Entry] = [:]
    private let lifetime: Duration = .seconds(120)
    private func permission() throws {
        guard AXIsProcessTrusted() else { throw ToolError.denied("Allow Accessibility access, then return to your browser and ask again. Sotto only reads the page you approve.") }
        try Task.checkCancellation()
    }
    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func string(_ element: AXUIElement, _ key: String) -> String? { value(element, key) as? String }
    private func url(_ element: AXUIElement) -> String? {
        if let url = value(element, kAXURLAttribute) as? URL { return url.absoluteString }
        return string(element, kAXURLAttribute) ?? string(element, kAXDocumentAttribute)
    }
    private func children(_ element: AXUIElement, limit: Int) -> (nodes: [AXUIElement], limited: Bool) {
        guard limit > 0 else { return ([], true) }
        AXUIElementSetMessagingTimeout(element, 0.15)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success, count > 0 else { return ([], false) }
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, min(count, limit), &result) == .success else { return ([], true) }
        return (result as? [AXUIElement] ?? [], count > limit)
    }
    private func focusedWindow(_ pid: pid_t) throws -> AXUIElement {
        guard let raw = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw ToolError.unavailable("The browser has no accessible focused window. Return to the page and try again.") }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
    private func webArea(_ window: AXUIElement) throws -> AXUIElement {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited: [AXUIElement] = []
        var found: [AXUIElement] = []
        let began = ContinuousClock.now
        while !queue.isEmpty, visited.count < 300, began.duration(to: .now) < .seconds(3) {
            try Task.checkCancellation()
            let (node, depth) = queue.removeFirst()
            if visited.contains(where: { CFEqual($0, node) }) { continue }
            visited.append(node)
            let role = string(node, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" {
                if let raw = url(node), (try? BrowserPagePolicy.url(raw)) != nil { found.append(node) }
                continue
            }
            if depth < 12, !BrowserPagePolicy.excludedRoles.contains(role) {
                let next = children(node, limit: 300 - visited.count - queue.count)
                guard !next.limited else { throw ToolError.unavailable("The focused browser window exceeds the bounded page-identification limit.") }
                queue += next.nodes.map { ($0, depth + 1) }
            }
        }
        guard queue.isEmpty else { throw ToolError.unavailable("The browser page could not be identified within the access limit.") }
        guard found.count == 1 else { throw ToolError.unavailable("No single accessible HTTPS page was found. Browser settings, a PDF, private/internal pages or this browser's accessibility support may prevent access. Select the page and try again.") }
        return found[0]
    }
    private func entry(_ id: String) throws -> Entry {
        entries = entries.filter { $0.value.created.duration(to: .now) < lifetime }
        guard let entry = entries[id] else { throw ToolError.denied("This page reference expired or is unknown. Read the current tab again before continuing.") }
        return entry
    }
    func capture() async throws -> BrowserPageReference {
        try permission()
        guard let app = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let bundle = app.bundleIdentifier, BrowserPagePolicy.supportedBundles.contains(bundle) else {
            throw ToolError.unavailable("Bring a page in Safari, Chrome, Edge or Brave to the front and ask again. Other browsers are not supported by this bridge.")
        }
        let window = try focusedWindow(app.processIdentifier)
        let area = try webArea(window)
        guard let rawURL = url(area) else { throw ToolError.unavailable("The browser did not expose a page URL") }
        let safe = try BrowserPagePolicy.url(rawURL)
        let ref = BrowserPageReference(id: UUID().uuidString, browser: app.localizedName ?? bundle,
                                       title: String((string(area, kAXTitleAttribute) ?? string(window, kAXTitleAttribute) ?? "").prefix(500)), url: safe.absoluteString)
        entries = entries.filter { $0.value.created.duration(to: .now) < lifetime }
        if entries.count >= 8, let oldest = entries.min(by: { $0.value.created < $1.value.created })?.key { entries.removeValue(forKey: oldest) }
        entries[ref.id] = Entry(reference: ref, pid: app.processIdentifier, window: window, area: area, created: .now)
        return ref
    }
    func reference(_ id: String) throws -> BrowserPageReference { try entry(id).reference }
    func validate(_ id: String) async throws {
        try permission()
        let entry = try entry(id)
        let foreground = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let ownBundle = Bundle.main.bundleIdentifier
        guard let foreground,
              foreground.processIdentifier == entry.pid || (ownBundle != nil && foreground.bundleIdentifier == ownBundle) else {
            throw ToolError.denied("The foreground application changed. Return to the approved browser page and ask again.")
        }
        let window = try focusedWindow(entry.pid)
        guard CFEqual(window, entry.window) else { throw ToolError.denied("The browser window changed after review. Read the current tab again.") }
        let area = try webArea(window)
        guard CFEqual(area, entry.area), url(area).flatMap({ try? BrowserPagePolicy.url($0).absoluteString }) == entry.reference.url else {
            throw ToolError.denied("The browser tab or address changed after review. Read the current tab again.")
        }
    }
    func read(_ id: String) async throws -> BrowserPageExcerpt {
        try await validate(id)
        let entry = try entry(id)
        var builder = BrowserExcerptBuilder()
        var queue: [(AXUIElement, Int)] = [(entry.area, 0)]
        var visited: [AXUIElement] = []
        let began = ContinuousClock.now
        while !queue.isEmpty, visited.count < 1_200, began.duration(to: .now) < .seconds(5), builder.text.count < 16_000 {
            try Task.checkCancellation()
            let (node, depth) = queue.removeFirst()
            if visited.contains(where: { CFEqual($0, node) }) { continue }
            visited.append(node)
            let role = string(node, kAXRoleAttribute) ?? ""
            if BrowserPagePolicy.excludedRoles.contains(role) { continue }
            if role == "AXWebArea", !CFEqual(node, entry.area) { builder.markLimited(); continue } // No embedded-frame traversal.
            builder.append(role: role, value: role == "AXStaticText" ? string(node, kAXValueAttribute) : nil,
                           title: role == "AXLink" ? string(node, kAXTitleAttribute) : nil, url: role == "AXLink" ? url(node) : nil)
            if depth < 24 {
                let remaining = 1_200 - visited.count - queue.count
                let next = children(node, limit: remaining)
                queue += next.nodes.map { ($0, depth + 1) }
                if next.limited { builder.markLimited() }
            } else { builder.markLimited() }
        }
        if !queue.isEmpty { builder.markLimited() }
        try await validate(id)
        guard !builder.text.isEmpty else { throw ToolError.unavailable("This page exposes no readable static text. Sotto did not read form controls or bypass the website's restrictions.") }
        entries[id]?.links = builder.links
        return BrowserPageExcerpt(reference: entry.reference, text: builder.text, links: builder.links, limited: builder.limited)
    }
    func link(_ id: String, index: Int) throws -> BrowserPageLink {
        let entry = try entry(id)
        guard let link = entry.links.first(where: { $0.id == index }) else { throw ToolError.invalid("Choose a link returned by browser.readPage, using its actual page reference and link number.") }
        return link
    }
    func open(_ id: String, index: Int, expectedURL: String) async throws -> Bool {
        let selected = try link(id, index: index)
        guard selected.url == expectedURL else { throw ToolError.denied("The selected link changed. Review it again.") }
        // Re-read the approved page; dynamic content cannot substitute a new URL.
        let current = try await read(id)
        guard current.links.contains(where: { $0.url == selected.url }) else { throw ToolError.denied("That link is no longer exposed by the approved page.") }
        let safe = try BrowserPagePolicy.url(selected.url)
        try Task.checkCancellation()
        return await MainActor.run { NSWorkspace.shared.open(safe) }
    }
}
