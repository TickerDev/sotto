import XCTest
import AppKit
import SottoSecurity
import SottoTools
@testable import SottoUI

private struct StubOpenFolderTool: Tool {
    let descriptor = ToolDescriptor(id: "open_folder", description: "Stub open folder", properties: ["path": .object(["type": .string("string")])], required: ["path"], risk: .read, capabilities: [])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        ToolResult("Opened Downloads")
    }
}

final class CapsulePlacementTests: XCTestCase {
    @MainActor func testRealHostingLayoutGrowsUpwardWithinVisibleFrame() async throws {
        _ = NSApplication.shared
        let model = AppModel(preferences: Preferences(), startServices: false)
        let panel = VoicePanel(model: model, preview: true)
        defer { panel.close(); model.shutdown() }
        panel.show() // Inert fixture: no audio, model requests or tool execution.
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let small = panel.frame
        model.state = .thinking
        model.state = .awaitingApproval
        model.approval = SottoSecurity.Approval(tool: "review_fixture", arguments: .object(["details": .string(String(repeating: "Long readable detail. ", count: 100))]))
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(panel.frame.height, small.height, "The actual SwiftUI measurement must resize the window")
        XCTAssertEqual(panel.frame.minY, small.minY, accuracy: 0.5, "Growing content must not move the bottom downward")
        let screen = try XCTUnwrap(NSScreen.main)
        XCTAssertTrue(CapsulePlacement.usableArea(screen.visibleFrame).contains(panel.frame))
    }
    @MainActor func testListeningVoiceGlowLayoutWithLevelsAndTranscript() async throws {
        _ = NSApplication.shared
        let model = AppModel(preferences: Preferences(), startServices: false)
        let panel = VoicePanel(model: model, preview: true)
        defer { panel.close(); model.shutdown() }
        model.state = .listening
        model.status = "Listening on MacBook Microphone"
        model.levels = Array(repeating: 0.45, count: 36)
        panel.show()
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        let initial = panel.frame
        model.transcript = "Open Google Chrome and check my calendar for tomorrow morning"
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(panel.frame.height, initial.height)
        XCTAssertEqual(panel.frame.minY, initial.minY, accuracy: 0.5)
    }
    func testAutoDismissWindowProgressClampsBetweenZeroAndOne() {
        let window = AutoDismissWindow(startedAt: 100, duration: 5)
        XCTAssertEqual(window.progress(at: 99), 0, accuracy: 0.0001)
        XCTAssertEqual(window.progress(at: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(window.progress(at: 102.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(window.progress(at: 105), 1, accuracy: 0.0001)
        XCTAssertEqual(window.progress(at: 108), 1, accuracy: 0.0001)
    }
    @MainActor func testShortCompletedActionPublishesAutoDismissWindowAndCancelClearsIt() async throws {
        var preferences = Preferences()
        preferences.audioFeedback = false
        preferences.notifications = false
        let model = AppModel(preferences: preferences, startServices: false, registry: ToolRegistry([StubOpenFolderTool()]))
        let panel = VoicePanel(model: model, preview: true)
        defer { panel.close(); model.shutdown() }
        panel.show()
        XCTAssertNil(model.autoDismissWindow)
        model.submit("Open my Downloads folder")
        for _ in 0..<40 where model.state == .thinking || model.state == .executing || model.state == .idle {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(model.state, .completed)
        XCTAssertNotNil(model.autoDismissWindow)
        XCTAssertEqual(model.autoDismissWindow?.duration, 5)
        panel.contentView?.layoutSubtreeIfNeeded()
        model.cancel()
        XCTAssertNil(model.autoDismissWindow)
    }
    func testGrowthStaysAboveBottomMarginAndInsideEveryDisplay() {
        let displays: [CGRect] = [
            CGRect(x: 0, y: 80, width: 1280, height: 697),
            CGRect(x: -1920, y: -1080, width: 1920, height: 1020),
            CGRect(x: 1600, y: 900, width: 1024, height: 680),
            CGRect(x: 0, y: 0, width: 360, height: 260)
        ]
        for screen in displays {
            for size in [CGSize(width: 456, height: 150), CGSize(width: 456, height: 440), CGSize(width: 1200, height: 2000)] {
                let rect = CapsulePlacement.frame(for: size, visibleFrame: screen)
                XCTAssertTrue(CapsulePlacement.usableArea(screen).contains(rect))
                XCTAssertEqual(rect.minY, screen.minY + 14)
                XCTAssertEqual(rect.midX, screen.midX)
                XCTAssertLessThanOrEqual(rect.maxY, screen.maxY - 14)
            }
        }
    }
    func testDisplayAndDockChangesClampPreviouslyOversizedContent() {
        let old = CGRect(x: 0, y: 0, width: 1800, height: 1100)
        let resized = CGRect(x: 90, y: 120, width: 710, height: 480)
        let before = CapsulePlacement.frame(for: CGSize(width: 456, height: 780), visibleFrame: old)
        let after = CapsulePlacement.frame(for: before.size, visibleFrame: resized)
        XCTAssertTrue(CapsulePlacement.usableArea(resized).contains(after))
        XCTAssertEqual(after.minY, resized.minY + 14)
    }
    func testInvalidMeasurementsCannotProduceOffscreenFrames() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let rect = CapsulePlacement.frame(for: CGSize(width: CGFloat.infinity, height: CGFloat.nan), visibleFrame: screen)
        XCTAssertTrue(CapsulePlacement.usableArea(screen).contains(rect))
    }
}
