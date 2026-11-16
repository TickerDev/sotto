import XCTest
import SottoTools
import SottoSecurity
import SottoIntegrations

final class NativeAuthorizationTests: XCTestCase, @unchecked Sendable {
    func testRequestedReminderCreationDoesNotAskForSecondApproval() async throws {
        let descriptor = try NativeTools.registry().tool("create_reminder").descriptor
        let gate = AuthorizationGate()
        try await gate.authorize(descriptor, arguments: .object([
            "title": .string("Review notes"), "due": .string("2026-11-16T17:00:00-06:00")
        ])) { request in
            XCTFail("Reminder creation should execute directly after the user's request")
            await gate.resolve(request.id, allowed: false)
        }
        // Validation still runs for automatic actions.
        do {
            try await gate.authorize(descriptor, arguments: .object(["title": .number(42)])) { _ in
                XCTFail("Invalid arguments must fail before authorization")
            }
            XCTFail("Invalid reminder arguments were accepted")
        } catch is ToolError {}
    }

    func testRequestedFileOpeningDoesNotAskForSecondApproval() async throws {
        let descriptor = try NativeTools.registry().tool("open_file").descriptor
        let gate = AuthorizationGate()
        for action in ["open", "reveal"] {
            try await gate.authorize(descriptor, arguments: .object(["path": .string("/tmp/example.pdf"), "action": .string(action)])) { request in
                XCTFail("A requested file action should not require another click")
                await gate.resolve(request.id, allowed: false)
            }
        }
        do {
            try await gate.authorize(descriptor, arguments: .object(["path": .string("/tmp/example.pdf"), "action": .string("execute")])) { _ in XCTFail("Invalid action reached approval") }
            XCTFail("Invalid action was accepted")
        } catch is ToolError {}
    }
    func testDirectOpeningRetainsFileTypeChecksAndAllowsApplications() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["document.pdf", "animation.gif", "animation.GIF", "script.command", "script.scpt", "installer.pkg"] {
            let file = folder.appendingPathComponent(name)
            try Data().write(to: file)
            if ["document.pdf", "animation.gif", "animation.GIF"].contains(name) { XCTAssertEqual(try FilePolicy.openingURL(file.path), file.resolvingSymlinksInPath()) }
            else { XCTAssertThrowsError(try FilePolicy.openingURL(file.path)) }
        }
        XCTAssertThrowsError(try FilePolicy.openingURL(folder.path))
        let settings = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        XCTAssertEqual(try FilePolicy.openingURL(settings.path), settings.resolvingSymlinksInPath())
    }
    func testFileToolAdvertisesTheSameFormatsThatNativeOpeningAllows() throws {
        let descriptor = try NativeTools.registry().tool("open_file").descriptor
        for ext in FilePolicy.supportedDocumentExtensions { XCTAssertTrue(descriptor.description.contains(ext)) }
        XCTAssertTrue(descriptor.description.contains("Use action open"))
    }
}
