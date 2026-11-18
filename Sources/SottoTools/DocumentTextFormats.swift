import Foundation

public enum DocumentTextFormats {
    public static let extensions: Set<String> = ["pdf", "txt", "md", "rtf", "docx"]
    public static func supports(_ path: String) -> Bool { extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
}
