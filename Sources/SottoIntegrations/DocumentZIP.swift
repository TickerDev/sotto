import Foundation
import SottoDocumentBridge
import SottoTools

/// Reads exact selected ZIP entries in memory. No archive path is ever written,
/// executed, resolved as a URL or passed to an external process.
struct DocumentZIP {
    static let expandedLimit = 8 * 1024 * 1024
    private let bytes: Data
    private let directoryOffset: Int
    private let entries: [String: Entry]
    private struct Entry {
        let flags: Int, method: Int, crc: UInt32, compressed: Int, expanded: Int, offset: Int
    }
    init(_ bytes: Data) throws {
        guard bytes.count <= DocumentTextReader.byteLimit, bytes.count >= 22 else { throw ToolError.invalid("Invalid or oversized Word archive") }
        let end = try Self.endRecord(bytes)
        guard try bytes.le16(end + 4) == 0, try bytes.le16(end + 6) == 0 else { throw ToolError.invalid("Multi-part Word archives are unsupported") }
        let count = try bytes.le16(end + 10)
        guard count > 0, count <= 512, try bytes.le16(end + 8) == count else { throw ToolError.invalid("This Word archive has too many entries or uses an unsupported ZIP format") }
        let size = try bytes.le32(end + 12), offset = try bytes.le32(end + 16)
        guard offset <= end, size == end - offset else { throw ToolError.invalid("Invalid Word archive directory") }
        var position = offset
        var entries: [String: Entry] = [:]
        let targets = ["word/document.xml", "[Content_Types].xml"]
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try bytes.le32(position) == 0x02014b50, position + 46 <= end else { throw ToolError.invalid("Invalid Word archive entry") }
            let nameLength = try bytes.le16(position + 28), extra = try bytes.le16(position + 30), comment = try bytes.le16(position + 32)
            let next = position + 46 + nameLength + extra + comment
            guard next <= end, try bytes.le16(position + 34) == 0 else { throw ToolError.invalid("Invalid Word archive bounds") }
            let rawName = bytes.subdata(in: position + 46..<position + 46 + nameLength)
            if let name = targets.first(where: { Data($0.utf8) == rawName }) {
                guard entries[name] == nil else { throw ToolError.invalid("Duplicate Word document entry") }
                let flags = try bytes.le16(position + 8), method = try bytes.le16(position + 10)
                let compressed = try bytes.le32(position + 20), expanded = try bytes.le32(position + 24)
                guard flags & 0x2041 == 0, [0, 8].contains(method), expanded > 0,
                      expanded <= Self.expandedLimit, compressed > 0, compressed <= bytes.count,
                      expanded <= compressed * 200 else { throw ToolError.invalid("Encrypted, unsupported or excessively compressed Word content") }
                entries[name] = Entry(flags: flags, method: method, crc: UInt32(try bytes.le32(position + 16)), compressed: compressed, expanded: expanded, offset: try bytes.le32(position + 42))
            }
            position = next
        }
        guard position == end, entries.count == 2 else { throw ToolError.invalid("Choose a standard DOCX document with readable document text") }
        self.bytes = bytes; self.directoryOffset = offset; self.entries = entries
    }
    func read(_ name: String) throws -> Data {
        try Task.checkCancellation()
        guard let entry = entries[name] else { throw ToolError.invalid("Missing Word document content") }
        let offset = entry.offset
        guard offset + 30 <= directoryOffset, try bytes.le32(offset) == 0x04034b50,
              try bytes.le16(offset + 6) == entry.flags, try bytes.le16(offset + 8) == entry.method else { throw ToolError.invalid("Inconsistent Word archive headers") }
        let nameLength = try bytes.le16(offset + 26), extra = try bytes.le16(offset + 28)
        let start = offset + 30 + nameLength + extra
        guard start <= directoryOffset, entry.compressed <= directoryOffset - start,
              bytes.subdata(in: offset + 30..<offset + 30 + nameLength) == Data(name.utf8) else { throw ToolError.invalid("Invalid Word document entry path or bounds") }
        if entry.flags & 8 == 0 {
            guard try bytes.le32(offset + 14) == Int(entry.crc), try bytes.le32(offset + 18) == entry.compressed,
                  try bytes.le32(offset + 22) == entry.expanded else { throw ToolError.invalid("Inconsistent Word archive sizes") }
        }
        let compressed = bytes.subdata(in: start..<start + entry.compressed)
        let decoded: Data
        if entry.method == 0 {
            guard compressed.count == entry.expanded else { throw ToolError.invalid("Invalid stored Word entry size") }
            decoded = compressed
        } else {
            var output = Data(count: entry.expanded)
            let valid = compressed.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { destination in
                    sotto_document_inflate(input.bindMemory(to: UInt8.self).baseAddress, compressed.count, destination.bindMemory(to: UInt8.self).baseAddress, entry.expanded)
                }
            }
            guard valid == 1 else { throw ToolError.invalid("Word content could not be safely decompressed") }
            decoded = output
        }
        let checksum = decoded.withUnsafeBytes { sotto_document_crc32($0.bindMemory(to: UInt8.self).baseAddress, decoded.count) }
        guard checksum == entry.crc else { throw ToolError.invalid("The Word document failed its integrity check") }
        try Task.checkCancellation()
        return decoded
    }
    private static func endRecord(_ data: Data) throws -> Int {
        let lower = max(0, data.count - 22 - 65_535)
        for position in stride(from: data.count - 22, through: lower, by: -1) {
            if try data.le32(position) == 0x06054b50, position + 22 + (try data.le16(position + 20)) == data.count { return position }
        }
        throw ToolError.invalid("Invalid Word ZIP directory")
    }
}
private extension Data {
    func le16(_ offset: Int) throws -> Int {
        guard offset >= 0, offset <= count - 2 else { throw ToolError.invalid("Truncated Word archive") }
        return Int(self[offset]) | Int(self[offset + 1]) << 8
    }
    func le32(_ offset: Int) throws -> Int {
        guard offset >= 0, offset <= count - 4 else { throw ToolError.invalid("Truncated Word archive") }
        return Int(self[offset]) | Int(self[offset + 1]) << 8 | Int(self[offset + 2]) << 16 | Int(self[offset + 3]) << 24
    }
}
