import Foundation
import SottoTools

/// Presentation only: authorization continues to use the original, immutable arguments.
public struct ApprovalPresentation: Sendable {
    public struct Field: Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }
    public let title: String
    public let fields: [Field]

    public init(_ approval: Approval) {
        let arguments = approval.arguments.object ?? [:]
        if approval.tool == "mail.draft" {
            title = "Prepare an unsent email"
            fields = [Field(label: "Account", value: arguments["account_name"]?.string ?? ""),
                      Field(label: "From", value: arguments["sender"]?.string ?? ""),
                      Field(label: "To", value: { if case .array(let rows) = arguments["to"] { return rows.compactMap(\.string).joined(separator: "\n") }; return "" }()),
                      Field(label: "Subject", value: arguments["subject"]?.string ?? ""),
                      Field(label: "Complete message", value: arguments["body"]?.string ?? ""),
                      Field(label: "Action", value: "Open an unsent compose window in Apple Mail. Nothing will be sent. Saved Drafts-folder persistence is not verified.")]
        } else if approval.tool.hasPrefix("appleNotes.") {
            title = approval.tool == "appleNotes.create" ? "Create an Apple Note" : "Update an Apple Note"
            var review = [Field(label: "Location", value: "Apple Notes · " + (arguments["folder_name"]?.string ?? "")),
                          Field(label: "Title", value: arguments["title"]?.string ?? ""),
                          Field(label: "Final note text", value: arguments["body"]?.string ?? "")]
            if approval.tool == "appleNotes.update" {
                review.append(Field(label: "Change", value: arguments["mode"]?.string == "replace" ? "Replace existing content. Rich formatting will be removed." : "Append the requested text."))
            }
            fields = review
        } else if approval.tool.hasPrefix("notes.") {
            title = approval.tool == "notes.create" ? "Create a Sotto note" : "Update a Sotto note"
            fields = [Field(label: "Location", value: "Sotto Notes · Local to this Mac"),
                      Field(label: "Title", value: arguments["title"]?.string ?? ""),
                      Field(label: "Final note text", value: arguments["body"]?.string ?? "")]
        } else if approval.tool.hasPrefix("contacts.") {
            title = approval.tool == "contacts.create" ? "Add a contact" : "Update a contact"
            var review: [Field] = []
            if let current = arguments["current_name"]?.string { review.append(Field(label: "Current contact", value: current)) }
            for (key, label) in [("given_name", "Given name"), ("family_name", "Family name"), ("organization", "Organization")] {
                review.append(Field(label: label, value: arguments[key]?.string ?? ""))
            }
            for (key, label) in [("emails", "Email addresses"), ("phones", "Phone numbers")] {
                if case .array(let rows) = arguments[key] { review.append(Field(label: label, value: rows.compactMap(\.string).joined(separator: "\n"))) }
            }
            fields = review
        } else if approval.tool.hasPrefix("browser.") {
            title = approval.tool == "browser.openLink" ? "Open a page link" : approval.tool == "browser.currentTab" ? "Identify your browser tab" : "Read the approved browser page"
            var review = [Field(label: "Browser", value: arguments["browser"]?.string ?? ""),
                          Field(label: "Page", value: arguments["title"]?.string ?? ""),
                          Field(label: "Source address", value: arguments["url"]?.string ?? "")]
            if let query = arguments["query"]?.string { review.append(Field(label: "Find text", value: query)) }
            if let destination = arguments["destination"]?.string {
                review.append(Field(label: "Open in default browser", value: destination))
            } else {
                review.append(Field(label: "Shared with this conversation", value: approval.tool == "browser.currentTab" ? "Page title and address only. Your selected intelligence may process this information." : "Accessible page text and links. Your selected intelligence may process this content. Form fields and embedded frames are omitted; excerpts may be incomplete."))
            }
            fields = review
        } else if approval.tool == "workflows.resume", case .array(let steps) = arguments["steps"] {
            title = "Continue interrupted workflow"
            var review: [Field] = []
            if case .array(let skipped) = arguments["skipped_steps"], !skipped.isEmpty {
                review.append(Field(label: "Uncertain actions will be skipped", value: "Only continue after checking these actions. Their outcomes will remain unverified."))
                review += skipped.enumerated().map { index, item in
                    let summary = WorkflowActionSummary(item.object?["definition"] ?? .null)
                    return Field(label: "Skip \(index + 1): " + summary.title, value: summary.detail)
                }
            }
            review += steps.enumerated().map { index, step in
                let summary = WorkflowActionSummary(step)
                return Field(label: "Continue \(index + 1): " + summary.title, value: summary.detail)
            }
            if review.isEmpty { review = [Field(label: "Actions", value: "No actions remain; finalize the existing record only.")] }
            fields = review
        } else if ["workflows.run", "workflows.save"].contains(approval.tool), case .array(let steps) = arguments["steps"] {
            title = approval.tool == "workflows.save" ? "Save workflow" : "Run workflow"
            let name = arguments["name"]?.string ?? ""
            fields = (name.isEmpty ? [] : [Field(label: "Workflow", value: name)]) + steps.enumerated().map { index, step in
                let summary = WorkflowActionSummary(step)
                return Field(label: "Step \(index + 1): " + summary.title, value: summary.detail)
            }
        } else if approval.tool == "workflows.remove" {
            title = "Remove saved workflow"
            fields = [Field(label: "Workflow", value: arguments["name"]?.string ?? "")]
        } else if approval.tool == "aliases.save" {
            title = "Remember a name"
            let kind = arguments["kind"]?.string ?? "file"
            fields = [Field(label: "Name", value: arguments["name"]?.string ?? ""),
                      Field(label: kind.capitalized, value: arguments["target_name"]?.string ?? arguments["path"]?.string ?? "")]
        } else if approval.tool == "aliases.remove" {
            title = "Forget a remembered name"
            fields = [Field(label: "Name", value: arguments["name"]?.string ?? "")]
        } else if approval.tool == "open_file", let path = arguments["path"]?.string {
            title = arguments["action"]?.string == "reveal" ? "Reveal file in Finder" : "Open file"
            fields = [Field(label: "File", value: (path as NSString).lastPathComponent), Field(label: "Location", value: path)]
        } else {
            title = Self.label(approval.tool)
            fields = arguments.keys.sorted().map { key in
                Field(label: Self.label(key), value: arguments[key]?.string ?? arguments[key]?.encoded ?? "")
            }
        }
    }
    private static func label(_ key: String) -> String {
        key.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
