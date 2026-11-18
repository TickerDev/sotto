import XCTest
import SottoTools
import SottoSecurity
@testable import SottoIntegrations

final class NotesTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> (SottoNoteStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SottoNotes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes/notes.json")
        return (SottoNoteStore(file: file), file)
    }
    func testRealCreateReadSearchUpdateAndRelaunchKeepSottoSourceAndIdentity() async throws {
        let (store, file) = try fixture()
        let create = NotesTool(action: "create", store: store)
        let proposal: JSONValue = .object(["title": .string("Research"), "body": .string("Engineering ethics meeting notes.")])
        let saved = try await create.execute(arguments: create.authorizationArguments(proposal))
        let id = try XCTUnwrap(saved.data.object?["id"]?.string)
        XCTAssertEqual(saved.data.object?["source"], .string("Sotto Notes"))
        let search = try await NotesTool(action: "search", store: store).execute(arguments: .object(["query": .string("ethics")]))
        XCTAssertFalse(search.data.encoded.contains("Engineering ethics meeting notes."), "Search returns references, not full bodies")
        let update = NotesTool(action: "update", store: store)
        let reviewed = try await update.authorizationArguments(.object(["id": .string(id), "revision": .number(1), "mode": .string("append"), "body": .string("Follow up tomorrow.")]))
        let presentation = ApprovalPresentation(Approval(tool: "notes.update", arguments: reviewed))
        XCTAssertTrue(presentation.fields.contains { $0.value.contains("Sotto Notes") })
        XCTAssertTrue(presentation.fields.contains { $0.value.contains("Engineering ethics") && $0.value.contains("Follow up") })
        let changed = try await update.execute(arguments: reviewed)
        XCTAssertEqual(changed.data.object?["revision"], .number(2))
        XCTAssertEqual(changed.data.object?["id"]?.string, id)
        let restored = SottoNoteStore(file: file)
        let note = try await restored.get(id)
        XCTAssertEqual(note.body, "Engineering ethics meeting notes.\nFollow up tomorrow.")
        do { _ = try await update.execute(arguments: reviewed); XCTFail("Stale review cannot overwrite a newer note") } catch {}
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testDuplicateCreateDoesNotRepeatSideEffectAndLargeReviewRespectsDeclaredBound() async throws {
        let (store, _) = try fixture()
        let tool = NotesTool(action: "create", store: store)
        let args: JSONValue = .object(["title": .string("Long note"), "body": .string(String(repeating: "a", count: 8000))])
        let approved = try await tool.authorizationArguments(args)
        let first = try await tool.execute(arguments: approved)
        let second = try await tool.execute(arguments: approved)
        XCTAssertEqual(first.data.object?["id"], second.data.object?["id"])
        let notes = try await store.all(); XCTAssertEqual(notes.count, 1)
        do { _ = try await tool.authorizationArguments(.object(["title": .string("Too long"), "body": .string(String(repeating: "b", count: 16001))])); XCTFail() } catch {}
    }
    func testCorruptNotesStayPreservedAndUnapprovedAppendCannotExecute() async throws {
        let (store, file) = try fixture()
        _ = try await store.create(title: "Original", body: "Keep this")
        let notes = try await store.all()
        let note = try XCTUnwrap(notes.first)
        let update = NotesTool(action: "update", store: store)
        do { _ = try await update.execute(arguments: .object(["id": .string(note.id), "revision": .number(1), "mode": .string("append"), "body": .string("not reviewed")])); XCTFail() } catch {}
        let current = try await store.get(note.id); XCTAssertEqual(current.body, "Keep this")
        let corrupt = Data("corrupt".utf8); try corrupt.write(to: file)
        do { _ = try await store.create(title: "No overwrite", body: ""); XCTFail() } catch {}
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
