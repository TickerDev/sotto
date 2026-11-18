import XCTest
import Contacts
import SottoTools
import SottoSecurity
@testable import SottoIntegrations
@testable import SottoUI

private actor ContactsFixture: ContactsAccess {
    var records: [ContactRecord]
    private(set) var writes = 0
    var verified = true
    init(_ records: [ContactRecord]) { self.records = records }
    func setVerified(_ value: Bool) { verified = value }
    func search(_ query: String) -> ContactMatches { .init(records: records.filter { $0.fields.name.localizedCaseInsensitiveContains(query) }, limited: false) }
    func get(_ id: String) throws -> ContactRecord {
        guard let record = records.first(where: { $0.id == id }) else { throw ToolError.unavailable("No matching contact") }
        return record
    }
    func create(_ fields: ContactFields) -> ContactWriteReceipt {
        writes += 1
        let record = ContactRecord(id: UUID().uuidString, fields: fields)
        records.append(record); return .init(record: record, verified: verified)
    }
    func update(_ id: String, revision: String, fields: ContactFields) throws -> ContactWriteReceipt {
        let old = try get(id)
        guard old.revision == revision, let index = records.firstIndex(where: { $0.id == id }) else { throw ToolError.denied("Stale contact") }
        writes += 1
        let record = ContactRecord(id: id, fields: fields)
        records[index] = record; return .init(record: record, verified: verified)
    }
}
final class ContactsTests: XCTestCase, @unchecked Sendable {
    private func person(_ name: String = "Alex", id: String = "one") -> ContactRecord {
        .init(id: id, fields: .init(givenName: name, familyName: "Example", organization: "University", emails: ["alex@example.invalid"], phones: ["+1 555 010 2000"]))
    }
    func testNativeContactSnapshotAndRevisionDoNotRequireAccountAccess() throws {
        let card = CNMutableContact()
        card.givenName = "Alex"; card.familyName = "Example"; card.organizationName = "University"
        card.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "alex@example.invalid" as NSString)]
        card.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: "+1 555 010 2000"))]
        let first = NativeContactsAccess.snapshot(card)
        XCTAssertEqual(first.fields.emails, ["alex@example.invalid"])
        XCTAssertEqual(first.fields.name, "Alex Example")
        XCTAssertEqual(first.revision, NativeContactsAccess.snapshot(card).revision)
        card.organizationName = "Changed"
        XCTAssertNotEqual(first.revision, NativeContactsAccess.snapshot(card).revision)
    }
    func testSearchReturnsActualDistinctIdentitiesAndRequiresDisambiguation() async throws {
        let fixture = ContactsFixture([person(), person("Alexandra", id: "two")])
        let result = try await ContactsTool(action: "search", access: fixture).execute(arguments: .object(["query": .string("Alex")]))
        XCTAssertEqual(result.data.object?["requires_disambiguation"], .bool(true))
        guard case .array(let values) = result.data.object?["contacts"] else { return XCTFail() }
        XCTAssertEqual(Set(values.compactMap { $0.object?["id"]?.string }), ["one", "two"])
        let read = try await ContactsTool(action: "get", access: fixture).execute(arguments: .object(["id": .string("two")]))
        XCTAssertEqual(read.data.object?["name"], .string("Alexandra Example"))
        do { _ = try await fixture.get("invented"); XCTFail() } catch {}
    }
    func testUpdateFreezesFieldsPreservesUnchangedDetailsAndRejectsStaleApproval() async throws {
        let original = person()
        let fixture = ContactsFixture([original])
        let tool = ContactsTool(action: "update", access: fixture)
        let request: JSONValue = .object(["id": .string(original.id), "revision": .string(original.revision), "organization": .string("Lab")])
        let reviewed = try await tool.authorizationArguments(request)
        XCTAssertEqual(reviewed.object?["emails"], .array([.string("alex@example.invalid")]))
        let display = ApprovalPresentation(Approval(tool: "contacts.update", arguments: reviewed))
        XCTAssertTrue(display.fields.contains { $0.label == "Current contact" && $0.value == "Alex Example" })
        XCTAssertFalse(display.fields.contains { $0.value == original.revision })
        let result = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(result.state, .success)
        let updated = try await fixture.get(original.id)
        XCTAssertEqual(updated.fields.organization, "Lab"); XCTAssertEqual(updated.fields.phones, original.fields.phones)
        do { _ = try await tool.execute(arguments: reviewed); XCTFail("Stale update cannot overwrite newer card") } catch {}
        let writes = await fixture.writes; XCTAssertEqual(writes, 1)
    }
    func testCreateAndPartialReadbackNeverClaimUnverifiedSuccess() async throws {
        let fixture = ContactsFixture([])
        let tool = ContactsTool(action: "create", access: fixture)
        let reviewed = try await tool.authorizationArguments(person().fields.data)
        let first = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(first.state, .success)
        await fixture.setVerified(false)
        let partial = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(partial.state, .partiallyCompleted)
        XCTAssertTrue(partial.summary.contains("not fully verified"))
        XCTAssertEqual(tool.descriptor.risk, .consequential)
        XCTAssertEqual(ContactsTool(action: "search").descriptor.risk, .read)
    }
    func testInvalidFieldsCannotBecomeReviewedWrites() async throws {
        let fixture = ContactsFixture([])
        let tool = ContactsTool(action: "create", access: fixture)
        for args: JSONValue in [
            .object([:]),
            .object(["given_name": .string("Alex"), "emails": .array([.string("bad@example.invalid\nBcc: x@y.invalid")])]),
            .object(["given_name": .string("Alex"), "phones": .array([.string("run shell")])]),
            .object(["given_name": .string("Alex"), "emails": .array(Array(repeating: .string("a@b.invalid"), count: 11))])
        ] {
            do { _ = try await tool.authorizationArguments(args); XCTFail() } catch {}
        }
        let writes = await fixture.writes; XCTAssertEqual(writes, 0)
    }
    func testRegistrationPermissionAndNativeDenialAreExplicit() async throws {
        let registry = NativeTools.registry()
        for id in ["contacts.search", "contacts.get", "contacts.create", "contacts.update"] {
            XCTAssertTrue(try registry.tool(id).descriptor.capabilities.contains(.contacts))
        }
        XCTAssertEqual(PermissionKind.contacts.title, "Contacts")
        XCTAssertTrue(PermissionKind.contacts.settingsURL.absoluteString.contains("Privacy_Contacts"))
        if CNContactStore.authorizationStatus(for: .contacts) != .authorized {
            do { _ = try await NativeContactsAccess.shared.search("Sotto non-personal permission probe"); XCTFail("Permission must not be bypassed") } catch {}
        }
    }
}
