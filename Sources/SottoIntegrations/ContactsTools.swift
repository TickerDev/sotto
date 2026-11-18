import Foundation
import Contacts
import CryptoKit
import SottoTools

struct ContactFields: Codable, Sendable, Equatable {
    var givenName: String
    var familyName: String
    var organization: String
    var emails: [String]
    var phones: [String]
    var name: String {
        let personal = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return !personal.isEmpty ? personal : !organization.isEmpty ? organization : emails.first ?? phones.first ?? ""
    }
    var data: JSONValue { .object(["given_name": .string(givenName), "family_name": .string(familyName), "organization": .string(organization), "emails": .array(emails.map(JSONValue.string)), "phones": .array(phones.map(JSONValue.string))]) }
    static func parse(_ args: JSONValue, base: Self? = nil) throws -> Self {
        let object = args.object ?? [:]
        func text(_ key: String, _ fallback: String) throws -> String {
            guard let value = object[key] else { return fallback }
            guard let raw = value.string else { throw ToolError.invalid("Contact fields must be text") }
            let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.count <= 200, result.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Contact names must be under 200 characters without control characters") }
            return result
        }
        func values(_ key: String, _ fallback: [String]) throws -> [String] {
            guard let value = object[key] else { return fallback }
            guard case .array(let rows) = value, rows.count <= 10 else { throw ToolError.invalid("Use at most ten email addresses or phone numbers") }
            return try rows.map {
                guard let value = $0.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.count <= 254, value.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Invalid contact address or phone number") }
                if key == "emails" {
                    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
                    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, !value.contains(where: \.isWhitespace), !value.contains(where: { "<>?,;".contains($0) }) else { throw ToolError.invalid("Provide a complete email address") }
                } else {
                    guard value.allSatisfy({ $0.isNumber || "+()- .".contains($0) }), (3...20).contains(value.filter(\.isNumber).count) else { throw ToolError.invalid("Provide a phone number without scripts or extension commands") }
                }
                return value
            }
        }
        let result = try Self(givenName: text("given_name", base?.givenName ?? ""), familyName: text("family_name", base?.familyName ?? ""),
                              organization: text("organization", base?.organization ?? ""), emails: values("emails", base?.emails ?? []), phones: values("phones", base?.phones ?? []))
        guard !result.name.isEmpty, Set(result.emails).count == result.emails.count, Set(result.phones).count == result.phones.count else { throw ToolError.invalid("Provide a name or organization and distinct contact addresses") }
        return result
    }
}
struct ContactRecord: Sendable {
    let id: String
    let fields: ContactFields
    let revision: String
    init(id: String, fields: ContactFields) {
        self.id = id; self.fields = fields
        revision = SHA256.hash(data: Data((id + fields.data.encoded).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var data: JSONValue { .object(["id": .string(id), "name": .string(fields.name), "revision": .string(revision), "details": fields.data, "untrusted": .bool(true)]) }
}
struct ContactMatches: Sendable { let records: [ContactRecord]; let limited: Bool }
struct ContactWriteReceipt: Sendable { let record: ContactRecord; let verified: Bool }
protocol ContactsAccess: Sendable {
    func search(_ query: String) async throws -> ContactMatches
    func get(_ id: String) async throws -> ContactRecord
    func create(_ fields: ContactFields) async throws -> ContactWriteReceipt
    func update(_ id: String, revision: String, fields: ContactFields) async throws -> ContactWriteReceipt
}
actor NativeContactsAccess: ContactsAccess {
    static let shared = NativeContactsAccess()
    private let store = CNContactStore()
    private var uncertainCreations: Set<String> = []
    private let keys: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey].map { $0 as CNKeyDescriptor }
    private func authorize() throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else { throw ToolError.denied("Allow Sotto Contacts access to read or change the contacts you request") }
        try Task.checkCancellation()
    }
    static func snapshot(_ contact: CNContact) -> ContactRecord {
        ContactRecord(id: contact.identifier, fields: .init(givenName: contact.givenName, familyName: contact.familyName, organization: contact.organizationName,
            emails: contact.emailAddresses.map { String($0.value) }, phones: contact.phoneNumbers.map { $0.value.stringValue }))
    }
    private static func supported(_ contact: CNContact) -> Bool {
        guard contact.emailAddresses.count <= 10, contact.phoneNumbers.count <= 10 else { return false }
        let names = [contact.givenName, contact.familyName, contact.organizationName, contact.jobTitle]
        let addresses = contact.emailAddresses.map { String($0.value) } + contact.phoneNumbers.map { $0.value.stringValue }
        return names.allSatisfy { $0.count <= 200 && $0.rangeOfCharacter(from: .controlCharacters) == nil } && addresses.allSatisfy { $0.count <= 254 && $0.rangeOfCharacter(from: .controlCharacters) == nil }
    }
    func search(_ query: String) throws -> ContactMatches {
        try authorize()
        let normalized = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let digits = query.filter(\.isNumber)
        var rows: [(ContactRecord, Int)] = [], inspected = 0, limited = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, stop in
            if Task.isCancelled || inspected >= 5000 || ContinuousClock.now >= deadline { limited = true; stop.pointee = true; return }
            inspected += 1
            guard Self.supported(contact) else { limited = true; return }
            let row = Self.snapshot(contact)
            let strings = [row.fields.name, row.fields.organization, contact.jobTitle] + row.fields.emails
            let match = strings.contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) } ||
                (digits.count >= 3 && row.fields.phones.contains { $0.filter(\.isNumber).contains(digits) })
            if match { rows.append((row, row.fields.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized ? 2 : 1)) }
        }
        try Task.checkCancellation()
        let ordered = rows.sorted { $0.1 == $1.1 ? $0.0.fields.name < $1.0.fields.name : $0.1 > $1.1 }
        return .init(records: Array(ordered.prefix(20).map(\.0)), limited: limited || rows.count > 20)
    }
    func get(_ id: String) throws -> ContactRecord {
        try authorize()
        let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
        guard Self.supported(contact) else { throw ToolError.unavailable("This card exceeds safe contact-detail limits. Review it in Contacts; no fields were changed.") }
        return Self.snapshot(contact)
    }
    private func apply(_ fields: ContactFields, to contact: CNMutableContact) {
        contact.givenName = fields.givenName; contact.familyName = fields.familyName; contact.organizationName = fields.organization
        if contact.emailAddresses.map({ String($0.value) }) != fields.emails { contact.emailAddresses = fields.emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) } }
        if contact.phoneNumbers.map({ $0.value.stringValue }) != fields.phones { contact.phoneNumbers = fields.phones.map { CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: $0)) } }
    }
    func create(_ fields: ContactFields) throws -> ContactWriteReceipt {
        try authorize()
        let fingerprint = fields.data.encoded
        let matches = try search(fields.name)
        guard !matches.limited else { throw ToolError.denied("Contact search coverage is incomplete. Narrow the person before creating another card.") }
        let exact = matches.records.filter { $0.fields == fields }
        if exact.count == 1 { return .init(record: exact[0], verified: true) }
        guard exact.isEmpty else { throw ToolError.invalid("Several identical contacts exist. Choose an actual contact instead of creating another.") }
        guard !matches.limited, uncertainCreations.count < 100, uncertainCreations.insert(fingerprint).inserted else { throw ToolError.denied("Contact creation is uncertain or search coverage is incomplete. Check Contacts before retrying; another card was not created.") }
        let contact = CNMutableContact(); apply(fields, to: contact)
        let request = CNSaveRequest(); request.add(contact, toContainerWithIdentifier: nil)
        do { try store.execute(request) }
        catch {
            if let actual = try? get(contact.identifier), actual.fields == fields { uncertainCreations.remove(fingerprint); return .init(record: actual, verified: true) }
            throw ToolError.unavailable("Contacts did not confirm creation. Check Contacts before retrying; it may have saved the card.")
        }
        let actual = try get(contact.identifier)
        uncertainCreations.remove(fingerprint)
        return .init(record: actual, verified: actual.fields == fields)
    }
    func update(_ id: String, revision: String, fields: ContactFields) throws -> ContactWriteReceipt {
        try authorize()
        let existing = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
        guard Self.supported(existing) else { throw ToolError.denied("This card has more details than Sotto can safely edit. Review it in Contacts.") }
        guard Self.snapshot(existing).revision == revision else { throw ToolError.denied("This contact changed after review. Find it again before updating.") }
        guard let contact = existing.mutableCopy() as? CNMutableContact else { throw ToolError.unavailable("This contact is not editable") }
        apply(fields, to: contact)
        let request = CNSaveRequest(); request.update(contact)
        do { try store.execute(request) }
        catch {
            if let actual = try? get(id), actual.fields == fields { return .init(record: actual, verified: true) }
            throw ToolError.unavailable("Contact update is unconfirmed. Check the card before retrying.")
        }
        let actual = try get(id)
        return .init(record: actual, verified: actual.fields == fields)
    }
}
struct ContactsTool: Tool {
    let action: String
    let access: any ContactsAccess
    init(action: String, access: any ContactsAccess = NativeContactsAccess.shared) { self.action = action; self.access = access }
    var requiresPermissionForAuthorization: Bool { action == "update" }
    var descriptor: ToolDescriptor {
        var properties: [String: JSONValue] = [:], required: [String] = []
        switch action {
        case "search": properties["query"] = textProperty("Name, organization, role, email or phone fragment"); required = ["query"]
        case "get": properties["id"] = textProperty("Actual identifier from contacts.search"); required = ["id"]
        default:
            for key in ["given_name", "family_name", "organization"] { properties[key] = textProperty("Requested " + key.replacingOccurrences(of: "_", with: " ")) }
            for key in ["emails", "phones"] { properties[key] = .object(["type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .number(10)]) }
            properties["current_name"] = textProperty("Application-resolved card name for approval")
            if action == "update" {
                properties["id"] = textProperty("Actual contact identifier"); properties["revision"] = textProperty("Actual revision from contacts.search/get")
                required = ["id", "revision"]
            }
        }
        return ToolDescriptor(id: "contacts." + action, description: "\(action.capitalized) local Contacts cards through Apple's Contacts framework. Search is bounded; when several people match, ask which person and never guess. Use actual returned IDs/revisions. Reads follow the selected intelligence privacy settings. Creation/update requires review of exact fields; updates preserve unmodified fields. No email/message is sent.",
                              properties: properties, required: required, risk: action == "search" || action == "get" ? .read : .consequential, capabilities: [.contacts])
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments)
        if action == "create" { return try ContactFields.parse(arguments).data }
        guard action == "update" else { return arguments }
        let id = arguments.object?["id"]?.string ?? "", revision = arguments.object?["revision"]?.string ?? ""
        let current = try await access.get(id)
        guard current.revision == revision else { throw ToolError.denied("This contact changed. Read it again before updating.") }
        guard !Set(arguments.object?.keys.map { $0 } ?? []).isDisjoint(with: ["given_name", "family_name", "organization", "emails", "phones"]) else { throw ToolError.invalid("Specify which contact fields to change") }
        let fields = try ContactFields.parse(arguments, base: current.fields)
        return .object((fields.data.object ?? [:]).merging(["id": .string(id), "revision": .string(revision), "current_name": .string(current.fields.name)]) { _, new in new })
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "search" {
            let query = (arguments.object?["query"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, query.count <= 120, query.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Say the person, organization, email address or phone number to find") }
            let found = try await access.search(query)
            return ToolResult("Found \(found.records.count) contact matches" + (found.records.count > 1 ? ". Ask which person before using an address." : "") + (found.limited ? ". Only a bounded part of accessible Contacts was searched." : ""),
                data: .object(["contacts": .array(found.records.map(\.data)), "requires_disambiguation": .bool(found.records.count > 1), "limited": .bool(found.limited), "untrusted": .bool(true)]))
        }
        if action == "get" {
            let id = arguments.object?["id"]?.string ?? ""
            guard !id.isEmpty else { throw ToolError.invalid("Choose an actual contact reference") }
            let contact = try await access.get(id)
            return ToolResult("Read contact “\(contact.fields.name)”", data: contact.data)
        }
        let fields = try ContactFields.parse(arguments)
        let receipt: ContactWriteReceipt
        if action == "create" { receipt = try await access.create(fields) }
        else {
            guard let id = arguments.object?["id"]?.string, let revision = arguments.object?["revision"]?.string,
                  let name = arguments.object?["current_name"]?.string, !name.isEmpty else { throw ToolError.denied("Review the specific contact before updating it") }
            receipt = try await access.update(id, revision: revision, fields: fields)
        }
        return ToolResult(receipt.verified ? "Saved contact “\(receipt.record.fields.name)” and verified its fields." : "Contacts accepted the save, but the requested fields were not fully verified. Check the card before retrying.",
                          data: receipt.record.data, state: receipt.verified ? .success : .partiallyCompleted)
    }
}
