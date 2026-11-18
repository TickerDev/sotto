import AppKit
import XCTest
import SottoAgent
import SottoTools
@testable import SottoUI

private struct AccessibleFolderFixture: Tool {
    let descriptor = ToolDescriptor(id: "open_folder", description: "Fixture", properties: ["path": textProperty("Path")], required: ["path"], risk: .read, capabilities: [])
    func execute(arguments: JSONValue) async throws -> ToolResult { ToolResult("Opened fixture folder") }
}
private struct AccessibleSearchFixture: Tool {
    let files: [FileSearchMatch]
    let descriptor = ToolDescriptor(id: "find_files", description: "Fixture", properties: ["name": textProperty("Name")], required: ["name"], risk: .read, capabilities: [])
    func execute(arguments: JSONValue) async throws -> ToolResult { ToolResult("Found fixture", data: FileSearchResults(files: files).data) }
}
final class AccessibleFeedbackTests: XCTestCase {
    @MainActor private func complete(_ model: AppModel) async throws {
        model.submit("Open my Downloads folder")
        for _ in 0..<100 where model.state != .completed { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.state, .completed)
    }
    @MainActor func testAssistiveReadingKeepsCompletedResultUntilDismissed() async throws {
        let model = AppModel(preferences: Preferences(), startServices: false, registry: ToolRegistry([AccessibleFolderFixture()]), assistiveReadingEnabled: { true })
        defer { model.shutdown() }
        try await complete(model)
        XCTAssertNil(model.autoDismissWindow)
        XCTAssertEqual(model.confirmedSummary, "Opened fixture folder")
    }
    @MainActor func testHoverPausesAndLeavingRestartsOnlyAnExistingCountdown() async throws {
        let model = AppModel(preferences: Preferences(), startServices: false, registry: ToolRegistry([AccessibleFolderFixture()]), assistiveReadingEnabled: { false })
        defer { model.shutdown() }
        model.setFeedbackInteraction(true); model.setFeedbackInteraction(false)
        XCTAssertNil(model.autoDismissWindow)
        try await complete(model)
        XCTAssertNotNil(model.autoDismissWindow)
        model.setFeedbackInteraction(true)
        XCTAssertNil(model.autoDismissWindow)
        model.setFeedbackInteraction(true) // Repeated hover callbacks don't clear the pause.
        model.setFeedbackInteraction(false)
        XCTAssertNotNil(model.autoDismissWindow)
        model.setFeedbackInteraction(true); model.cancel(); model.setFeedbackInteraction(false)
        XCTAssertNil(model.autoDismissWindow, "Leaving a canceled panel cannot restart a timer")
    }
    @MainActor func testInteractionAlreadyActiveAtCompletionAndKeyboardFocusBothHoldFeedback() async throws {
        let model = AppModel(preferences: Preferences(), startServices: false, registry: ToolRegistry([AccessibleFolderFixture()]), assistiveReadingEnabled: { false })
        defer { model.shutdown() }
        model.setFeedbackInteraction(true)
        try await complete(model)
        XCTAssertNil(model.autoDismissWindow)
        model.setFeedbackInteraction(true, keyboard: true)
        model.setFeedbackInteraction(false)
        XCTAssertNil(model.autoDismissWindow, "Keyboard focus must retain the result after pointer exit")
        model.setFeedbackInteraction(false, keyboard: true)
        XCTAssertNotNil(model.autoDismissWindow)
    }
    func testAnnouncementsAreOnlyForStableOutcomesAndNeededDecisions() {
        for state: AgentState in [.idle, .listening, .transcribing, .thinking, .executing] {
            XCTAssertNil(CapsuleAccessibility.announcement(state: state, status: "Progress"))
        }
        for state: AgentState in [.completed, .responded, .failed, .awaitingInput, .awaitingApproval] {
            XCTAssertNotNil(CapsuleAccessibility.announcement(state: state, status: "Done"))
        }
    }
    @MainActor func testSelectedDocumentSummaryRetainsExactCachedPathAndRejectsInventedOrUnsupportedFiles() async throws {
        let file = FileSearchMatch(path: "/tmp/Review notes.PDF"), unsupported = FileSearchMatch(path: "/tmp/Review.pages")
        let model = AppModel(preferences: Preferences(), startServices: false, onDeviceAvailable: { false }, registry: ToolRegistry([AccessibleSearchFixture(files: [file, unsupported])]))
        defer { model.shutdown() }
        model.submit("Find my resume")
        for _ in 0..<100 where model.fileMatches.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.fileMatches.count, 2)
        // Let the native response finish before selecting its result.
        for _ in 0..<100 where model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        model.summarizeFileMatch(FileSearchMatch(path: "/tmp/invented.pdf"))
        model.summarizeFileMatch(unsupported)
        XCTAssertNil(model.pendingIntelligence.intent)
        model.summarizeFileMatch(file)
        for _ in 0..<100 where model.pendingIntelligence.intent == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.pendingIntelligence.intent?.text, "Summarize /tmp/Review notes.PDF")
        XCTAssertTrue(model.intelligenceSetupPresented)
        XCTAssertEqual(model.status, "Intelligence needed")
    }
}
