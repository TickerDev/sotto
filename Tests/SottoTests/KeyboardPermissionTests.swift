import XCTest
import CoreGraphics
@testable import SottoUI

final class KeyboardPermissionTests: XCTestCase {
    func testExistingSystemGrantWithoutProcessAccessDoesNotClaimSwitchIsOff() {
        let grant = KeyboardPermissionSnapshot(preflightGranted: false, decision: .granted, listenerReady: false)
        XCTAssertEqual(grant.state, .unavailable)
        XCTAssertEqual(grant.state.label, "Unavailable to this copy")
        XCTAssertFalse(grant.state.canRequest)
        XCTAssertEqual(grant.shortcutLabel, "Keyboard access unavailable")
    }
    func testDenialAndUnknownAccessHaveDifferentRecoveryPaths() {
        let denied = KeyboardPermissionSnapshot(preflightGranted: false, decision: .denied, listenerReady: false)
        let unknown = KeyboardPermissionSnapshot(preflightGranted: false, decision: .unknown, listenerReady: false)
        XCTAssertEqual(denied.state, .unavailable)
        XCTAssertFalse(denied.state.canRequest)
        XCTAssertEqual(unknown.state, .notRequested)
        XCTAssertTrue(unknown.state.canRequest)
    }
    func testPermissionAndShortcutRegistrationAreIndependent() {
        let authorized = KeyboardPermissionSnapshot(preflightGranted: true, decision: .granted, listenerReady: false)
        XCTAssertEqual(authorized.state, .allowed)
        XCTAssertEqual(authorized.shortcutLabel, "Shortcut unavailable · retry registration")
        let ready = KeyboardPermissionSnapshot(preflightGranted: true, decision: .granted, listenerReady: true)
        XCTAssertEqual(ready.shortcutLabel, "Ready")
        let stalePreflight = KeyboardPermissionSnapshot(preflightGranted: false, decision: .denied, listenerReady: true)
        XCTAssertEqual(stalePreflight.state, .allowed, "A verified full keyboard listener is actual capability evidence")
    }
    @MainActor func testStrippedOrDisabledTapCannotClaimShortcutIsReady() {
        var info = CGEventTapInformation()
        info.tappingProcess = 123
        info.processBeingTapped = 0
        info.enabled = true
        info.tapPoint = .cgSessionEventTap
        info.options = .listenOnly
        info.eventsOfInterest = 1 << CGEventType.flagsChanged.rawValue
        XCTAssertFalse(GlobalShortcut.supportsShortcut(info, process: 123), "Observed macOS failure: only flagsChanged survives")
        info.eventsOfInterest = GlobalShortcut.keyboardMask
        XCTAssertTrue(GlobalShortcut.supportsShortcut(info, process: 123))
        info.enabled = false
        XCTAssertFalse(GlobalShortcut.supportsShortcut(info, process: 123))
        info.enabled = true
        XCTAssertFalse(GlobalShortcut.supportsShortcut(info, process: 456), "Another app's listener proves nothing about Sotto")
        info.processBeingTapped = 789
        XCTAssertFalse(GlobalShortcut.supportsShortcut(info, process: 123))
    }
}
