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
        if approval.tool == "open_file", let path = arguments["path"]?.string {
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
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
