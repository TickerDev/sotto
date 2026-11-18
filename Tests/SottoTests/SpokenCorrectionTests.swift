import XCTest
import SottoTools
import SottoSecurity
import SottoIntegrations
@testable import SottoAgent

private actor CorrectedFolderProbe {
    var paths: [String] = []
    func opened(_ path: String) { paths.append(path) }
}
private struct CorrectedFolderTool: Tool {
    let descriptor: ToolDescriptor
    let probe: CorrectedFolderProbe
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let path = try XCTUnwrap(arguments.object?["path"]?.string)
        await probe.opened(path)
        return ToolResult("Opened \((path as NSString).lastPathComponent) in Finder")
    }
}
final class SpokenCorrectionTests: XCTestCase, @unchecked Sendable {
    func testReportedPoliteFolderQuestionExecutesDocumentsWithoutReasoning() async throws {
        let command = "Could you open documents, please?"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))
        let probe = CorrectedFolderProbe()
        let tool = CorrectedFolderTool(descriptor: try NativeTools.registry().tool("open_folder").descriptor, probe: probe)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run(command, provider: provider) { event in
            if case .question = event { XCTFail("Explicit Documents folder request must not ask for a document path") }
            if case .failure = event { XCTFail("Polite Documents request should succeed") }
        }
        let paths = await probe.paths
        XCTAssertEqual(paths, ["~/Documents"])
    }

    func testPolitenessIsAcceptedOnlyForExplicitKnownFolderRequests() throws {
        for command in [
            "Can you please open Documents?", "Could you open documents, please?",
            "Open the Documents folder, please?", "Would you open my Documents folder please?",
            "Please open Documents?", "Can you please open the Documents?"
        ] {
            let provider = try XCTUnwrap(NativeCommandProvider(command: command), command)
            XCTAssertEqual(provider.tool, "open_folder")
            XCTAssertEqual(provider.arguments.object?["path"], .string("~/Documents"), command)
        }
        for command in [
            "Could you open a document, please?", "Could you open the document, please?",
            "Could you tell me how to open Documents, please?", "Don't open Documents, please?",
            "Could you open Documents, please, and delete my files?",
            "Could you open Documents, please, if it is safe?",
            "Can you open a file named Documents please?"
        ] {
            XCTAssertNil(NativeCommandProvider(command: command), command)
        }
    }

    func testPoliteCorrectionsStillExecuteOnlyFinalFolder() async throws {
        let command = "Could you open Downloads, please? Actually, could you please open Documents, please?"
        let probe = CorrectedFolderProbe()
        let tool = CorrectedFolderTool(descriptor: try NativeTools.registry().tool("open_folder").descriptor, probe: probe)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run(command, provider: XCTUnwrap(NativeCommandProvider(command: command))) { _ in }
        let paths = await probe.paths
        XCTAssertEqual(paths, ["~/Documents"])
    }

    func testReportedCorrectionExecutesOnlyDocumentsThroughTrustedRuntime() async throws {
        let command = "Open downloads--actually open documents"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))
        let probe = CorrectedFolderProbe()
        let tool = CorrectedFolderTool(descriptor: try NativeTools.registry().tool("open_folder").descriptor, probe: probe)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run(command, provider: provider) { event in
            if case .approval = event { XCTFail("Requested folder opening needs no redundant approval") }
            if case .failure = event { XCTFail("Corrected request should succeed") }
        }
        let paths = await probe.paths
        XCTAssertEqual(paths, ["~/Documents"], "Never open the withdrawn Downloads destination")
    }

    func testCorrectionPunctuationAndDirectionSelectOnlyFinalKnownFolder() throws {
        let cases = [
            ("Open Documents—actually, open Downloads instead.", "~/Downloads"),
            ("Open downloads actually open documents", "~/Documents"),
            ("Please open my Downloads folder. Actually open my Documents folder instead!", "~/Documents"),
            ("Open Downloads, no, open Desktop", "~/Desktop"),
            ("Open Downloads, no I mean open Documents", "~/Documents"),
            ("Open Downloads; I mean open Documents", "~/Documents"),
            ("Open Downloads actually open Documents actually open Desktop", "~/Desktop")
        ]
        for (command, expected) in cases {
            let provider = try XCTUnwrap(NativeCommandProvider(command: command), command)
            XCTAssertEqual(provider.tool, "open_folder", command)
            XCTAssertEqual(provider.arguments.object?["path"], .string(expected), command)
        }
    }

    func testUnclearNegatedQuotedOrAdditionalWorkCannotBeDroppedByCorrectionParsing() {
        for command in [
            "Open Downloads actually don't open Documents",
            "Open Downloads actually open Documents or Desktop",
            "Open Downloads actually open Documents and delete my files",
            "Open Downloads actually open Documents and resume Spotify",
            "Delete my files actually open Documents",
            "Open Downloads actually open /tmp/private",
            "Open Downloads actually open Documents except don't open Documents",
            "Open Downloads actually open Documents? No",
            "Say 'open Downloads actually open Documents'",
            "Open Downloads actually open Documents actually open Desktop actually open Downloads"
        ] {
            XCTAssertNil(NativeCommandProvider(command: command), command)
        }
    }

    func testConjunctionStillOpensBothRequestedFolders() async throws {
        let command = "Open Downloads and open Documents"
        let probe = CorrectedFolderProbe()
        let tool = CorrectedFolderTool(descriptor: try NativeTools.registry().tool("open_folder").descriptor, probe: probe)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run(command, provider: XCTUnwrap(NativeCommandProvider(command: command))) { _ in }
        let paths = await probe.paths
        XCTAssertEqual(paths, ["~/Downloads", "~/Documents"])
    }
}
