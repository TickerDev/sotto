import XCTest
import AppKit
@testable import SottoUI

final class SettingsWindowTests: XCTestCase, @unchecked Sendable {
    @MainActor func testSettingsContentDoesNotActAsTitleBarOrHideWhenInactive() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 820, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.isMovableByWindowBackground = true; window.hidesOnDeactivate = true
        SettingsWindowPolicy.apply(to: window)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertTrue(window.styleMask.contains(.miniaturizable), "The user's intentional minimize control remains available")
        XCTAssertFalse(window.isMiniaturized)
        let frame = window.frame
        SettingsWindowPolicy.apply(to: window)
        XCTAssertEqual(window.frame, frame, "Preference changes must not move or resize the window chrome")
        XCTAssertFalse(window.isMiniaturized)
    }
    @MainActor func testDecorativeMaterialAndChromeCannotInterceptControlClicks() {
        let backdrop = PassiveMaterialView(frame: NSRect(x: 0, y: 0, width: 820, height: 620))
        XCTAssertNil(backdrop.hitTest(NSPoint(x: 400, y: 300)))
        XCTAssertFalse(backdrop.mouseDownCanMoveWindow)
        let chrome = SettingsWindowChrome.Attachment(frame: backdrop.frame)
        XCTAssertNil(chrome.hitTest(NSPoint(x: 400, y: 300)))
        XCTAssertFalse(chrome.mouseDownCanMoveWindow)
    }
}
