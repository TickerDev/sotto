import Foundation

public struct FileSearchMatch: Codable, Sendable, Identifiable, Equatable {
    public let path: String
    public let modified: Date?
    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(path: String, modified: Date? = nil) { self.path = path; self.modified = modified }
}

public struct FileSearchResults: Codable, Sendable {
    public let files: [FileSearchMatch]
    public init(files: [FileSearchMatch]) { self.files = files }
    public var data: JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))) ?? .null }
    public static func decode(_ data: JSONValue) -> Self? {
        try? JSONDecoder().decode(Self.self, from: JSONEncoder().encode(data))
    }
}
