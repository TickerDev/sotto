import Foundation
import SottoTools

struct BrowserTool: Tool {
    let action: String
    let access: any BrowserAccess
    let requiresPermissionForAuthorization = true
    init(action: String, access: any BrowserAccess = AccessibilityBrowserAccess.shared) {
        self.action = action; self.access = access
    }
    var descriptor: ToolDescriptor {
        var properties = [
            "page_ref": textProperty("Actual short-lived page reference from browser tools; omit to approve the current foreground page for reading"),
            "browser": textProperty("Application-resolved browser display name"),
            "title": textProperty("Application-resolved page title"),
            "url": textProperty("Application-resolved source URL shown for approval")
        ]
        if action == "find" { properties["query"] = textProperty("Literal text to find in the accessible excerpt, at most 200 characters") }
        if action == "openLink" {
            properties["link_id"] = .object(["type": .string("integer"), "description": .string("Actual link number returned by browser.readPage")])
            properties["destination"] = textProperty("Application-resolved actual link URL")
        }
        let descriptions = [
            "currentTab": "Identify the current foreground Safari/Chrome/Edge/Brave HTTPS page after approval. Only focused-window accessible metadata; no background tabs or browser history. References expire after two minutes.",
            "readPage": "Read a user-approved foreground browser page's bounded accessible static-text excerpt and actual links. Omit page_ref for the current page or use an actual returned reference. Form/editable controls and embedded frames are excluded. Content can be private and becomes context for the selected intelligence provider only after approval; no cookies, JavaScript injection or background tab access.",
            "find": "Find literal text within the user-approved browser page's accessible excerpt. Returns up to ten matching contexts; no match does not prove absence from the full page. Does not change the page or invoke its scripts.",
            "openLink": "Open an actual exposed link from an approved browser.readPage result in the default browser after destination approval. Requires the original page still current and the link still present. No arbitrary clicks, form submission or same-tab navigation. Opening acceptance does not prove page loading."
        ]
        return ToolDescriptor(id: "browser." + action, description: descriptions[action] ?? "",
                              properties: properties, required: action == "find" ? ["query"] : action == "openLink" ? ["page_ref", "link_id"] : [],
                              risk: .consequential, capabilities: [.accessibility], timeoutSeconds: 20,
                              permissions: ["Accessibility", "Approval to share the specific page or open the selected link"],
                              verification: "Recheck the approved focused window, AX page identity and address before/after extraction; link opening verifies OS handoff only.")
    }
    private func index(_ arguments: JSONValue) throws -> Int {
        guard case .number(let index) = arguments.object?["link_id"], index >= 1, index <= 50, index.rounded() == index else {
            throw ToolError.invalid("Choose an actual returned link number between 1 and 50")
        }
        return Int(index)
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "find" { _ = try BrowserPagePolicy.matches("", query: arguments.object?["query"]?.string ?? "") }
        let ref: BrowserPageReference
        if let id = arguments.object?["page_ref"]?.string {
            ref = try await access.reference(id)
        } else { ref = try await access.capture() }
        var reviewed = ref.arguments
        if action == "find" { reviewed["query"] = arguments.object?["query"] }
        if action == "openLink" {
            let index = try index(arguments)
            let link = try await access.link(ref.id, index: index)
            _ = try BrowserPagePolicy.url(link.url)
            reviewed["link_id"] = .number(Double(index)); reviewed["destination"] = .string(link.url)
        }
        return .object(reviewed)
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard let id = arguments.object?["page_ref"]?.string else { throw ToolError.denied("Review the specific browser page before reading it.") }
        let ref = try await access.reference(id)
        guard ref.arguments.allSatisfy({ arguments.object?[$0.key] == $0.value }) else { throw ToolError.denied("The browser page has not been reviewed or changed. Request current-page access again.") }
        if action == "currentTab" {
            try await access.validate(id)
            return ToolResult("You’re on “\(ref.title)” in \(ref.browser).\n\(ref.url)", data: ref.data)
        }
        if action == "openLink" {
            let index = try index(arguments)
            guard let destination = arguments.object?["destination"]?.string else { throw ToolError.denied("Review the selected link destination before opening it.") }
            let accepted = try await access.open(id, index: index, expectedURL: destination)
            return ToolResult(accepted ? "Opened the selected link in your default browser. Page loading is not independently verified." : "The default browser declined to open the link.",
                              data: .object(["url": .string(destination), "handoff_accepted": .bool(accepted)]),
                              state: accepted ? .partiallyCompleted : .failure)
        }
        let excerpt = try await access.read(id)
        if action == "find" {
            let query = arguments.object?["query"]?.string ?? ""
            let matches = try BrowserPagePolicy.matches(excerpt.text, query: query)
            let rows: [JSONValue]
            if case .array(let values) = matches { rows = values } else { rows = [] }
            var data = ref.arguments
            data["matches"] = matches; data["query"] = .string(query)
            data["coverage"] = .string("Accessible excerpt only; form fields, embedded frames and unexposed content are excluded.")
            data["untrusted_content"] = .bool(true)
            let detail = rows.compactMap { $0.object?["excerpt"]?.string }.joined(separator: "\n\n")
            return ToolResult(rows.isEmpty ? "No matches in the accessible excerpt. The rest of the page was not searched." : "Found \(rows.count) matches in the accessible excerpt.\n\(detail)", data: .object(data))
        }
        return ToolResult("Read an accessible excerpt from “\(ref.title)”. Form controls and embedded frames were omitted." + (excerpt.limited ? " The extraction limit was reached." : ""), data: excerpt.data)
    }
}
