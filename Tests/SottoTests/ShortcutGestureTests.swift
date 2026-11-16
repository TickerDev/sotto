import XCTest
import AppKit
@testable import SottoUI

final class ShortcutGestureTests: XCTestCase, @unchecked Sendable {
    func testHoldStartsImmediatelyAndReleaseSubmitsOnce() {
        var gesture = ShortcutGesture()
        XCTAssertEqual(gesture.press(at: 0), [.beginHold])
        XCTAssertEqual(gesture.press(at: 1), [])
        XCTAssertEqual(gesture.release(at: 2), [.submit])
        XCTAssertEqual(gesture.release(at: 2.1), [])
        XCTAssertEqual(gesture.expire(at: 9), [])
    }
    func testDoubleTapNeverSubmitsBetweenTapsAndStaysHandsFree() {
        var gesture = ShortcutGesture()
        XCTAssertEqual(gesture.press(at: 0), [.beginHold])
        XCTAssertEqual(gesture.release(at: 0.08), [])
        XCTAssertEqual(gesture.expire(at: 0.15), [])
        XCTAssertEqual(gesture.press(at: 0.2), [.handsFree])
        XCTAssertEqual(gesture.release(at: 0.28), [])
        XCTAssertEqual(gesture.expire(at: 10), [])
        XCTAssertEqual(gesture.press(at: 11), [], "Hands-free waits for Send rather than toggling off")
        XCTAssertEqual(gesture.release(at: 12), [])
        gesture.reset()
        XCTAssertEqual(gesture.press(at: 13), [.beginHold])
    }
    func testShortSingleTapExpiresAndCannotBecomeLateDoubleTap() {
        var gesture = ShortcutGesture()
        _ = gesture.press(at: 0); _ = gesture.release(at: 0.1)
        XCTAssertEqual(gesture.expire(at: 0.59), [])
        XCTAssertEqual(gesture.expire(at: 0.61), [.submit])
        XCTAssertEqual(gesture.press(at: 0.7), [.beginHold])
        _ = gesture.release(at: 0.75)
        XCTAssertEqual(gesture.press(at: 1.5), [.submit, .beginHold], "A delayed timer cannot turn an unrelated later press into a double-tap")
    }
    func testCancellationInvalidatesPendingSubmissionAndHandsFree() {
        var gesture = ShortcutGesture()
        _ = gesture.press(at: 0); _ = gesture.release(at: 0.05)
        gesture.reset()
        XCTAssertEqual(gesture.expire(at: 10), [])
        _ = gesture.press(at: 11); _ = gesture.release(at: 11.05); _ = gesture.press(at: 11.1)
        gesture.reset()
        XCTAssertEqual(gesture.release(at: 12), [])
        XCTAssertEqual(gesture.expire(at: 13), [])
    }
    func testLegacyTogglePreferenceDoesNotOverrideNewHoldBehavior() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"shortcut":2,"keyCode":79,"toggleToTalk":true,"language":"he-IL"}"#.utf8))
        XCTAssertEqual(p.activationShortcut, .legacy(modifierIndex: 2, keyCode: 79))
        XCTAssertEqual(p.language, "he-IL")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        XCTAssertNil(encoded["toggleToTalk"]); XCTAssertNil(encoded["shortcut"]); XCTAssertNil(encoded["keyCode"])
        XCTAssertNotNil(encoded["activationShortcut"])
    }
    func testCustomChordAndModifierOnlyBindingPersist() throws {
        for binding in [ActivationShortcut(keyCode: 2, flags: [.maskCommand, .maskShift], keyLabel: "D"), ActivationShortcut(keyCode: nil, flags: .maskSecondaryFn)] {
            var p = Preferences(); p.activationShortcut = binding
            XCTAssertTrue(binding.isValid)
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(decoded.activationShortcut, binding)
        }
    }
    func testUnsafeBareKeysAndEscapeAreNotRecordable() {
        XCTAssertFalse(ActivationShortcut(keyCode: 0, flags: [], keyLabel: "A").isValid)
        XCTAssertFalse(ActivationShortcut(keyCode: 53, flags: .maskCommand, keyLabel: "Escape").isValid)
        XCTAssertFalse(ActivationShortcut(keyCode: nil, flags: []).isValid)
        XCTAssertTrue(ActivationShortcut(keyCode: 79, flags: [], keyLabel: "F18").isValid)
    }
    @MainActor func testKeyboardEventsReleaseWhenModifiersAreReleasedFirst() throws {
        let shortcut = GlobalShortcut(); defer { shortcut.stop() }
        var time = 0.0; shortcut.now = { time }; shortcut.eventTime = { _ in time }
        var starts = 0, submissions = 0
        shortcut.pressed = { starts += 1; return true }; shortcut.released = { submissions += 1 }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true))
        event.flags = [.maskControl, .maskAlternate]
        shortcut.handle(.keyDown, event)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1); shortcut.handle(.keyDown, event)
        time = 1; event.flags = []; shortcut.handle(.flagsChanged, event)
        shortcut.handle(.keyUp, event)
        XCTAssertEqual(starts, 1); XCTAssertEqual(submissions, 1)
    }
    @MainActor func testModifierOnlyFnDoubleTapAndEscapeDiscard() throws {
        let shortcut = GlobalShortcut(); defer { shortcut.stop() }
        shortcut.binding = ActivationShortcut(keyCode: nil, flags: .maskSecondaryFn)
        var time = 0.0; shortcut.now = { time }; shortcut.eventTime = { _ in time }
        var starts = 0, latches = 0, submissions = 0, cancellations = 0
        shortcut.pressed = { starts += 1; return true }; shortcut.released = { submissions += 1 }
        shortcut.handsFree = { latches += 1 }; shortcut.cancelled = { cancellations += 1 }
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.flags = .maskSecondaryFn; shortcut.handle(.flagsChanged, event)
        time = 0.05; event.flags = []; shortcut.handle(.flagsChanged, event)
        time = 0.1; event.flags = .maskSecondaryFn; shortcut.handle(.flagsChanged, event)
        time = 0.15; event.flags = []; shortcut.handle(.flagsChanged, event)
        XCTAssertEqual(starts, 1); XCTAssertEqual(latches, 1); XCTAssertEqual(submissions, 0)
        let escape = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        shortcut.handle(.keyDown, escape)
        XCTAssertEqual(cancellations, 1); XCTAssertEqual(submissions, 0)
    }
    @MainActor func testBusyRuntimeRejectsGestureWithoutSubmittingButtonRecording() throws {
        let shortcut = GlobalShortcut(); defer { shortcut.stop() }
        var submissions = 0
        shortcut.pressed = { false }; shortcut.released = { submissions += 1 }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true))
        event.flags = [.maskControl, .maskAlternate]
        shortcut.handle(.keyDown, event); shortcut.handle(.keyUp, event)
        XCTAssertEqual(submissions, 0)
    }
    @MainActor func testDelayedCallbackDoesNotTurnPhysicalTapIntoLongHold() throws {
        let shortcut = GlobalShortcut(); defer { shortcut.stop() }
        shortcut.binding = ActivationShortcut(keyCode: nil, flags: .maskSecondaryFn)
        var callbackTime = 100.0; shortcut.now = { callbackTime }
        var latches = 0, submissions = 0
        shortcut.pressed = { callbackTime += 2; return true }
        shortcut.handsFree = { latches += 1 }; shortcut.released = { submissions += 1 }
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.timestamp = 100_000_000_000; event.flags = .maskSecondaryFn; shortcut.handle(.flagsChanged, event)
        event.timestamp = 100_080_000_000; event.flags = []; shortcut.handle(.flagsChanged, event)
        event.timestamp = 100_200_000_000; event.flags = .maskSecondaryFn; shortcut.handle(.flagsChanged, event)
        event.timestamp = 100_280_000_000; event.flags = []; shortcut.handle(.flagsChanged, event)
        XCTAssertEqual(latches, 1); XCTAssertEqual(submissions, 0)
    }
    func testNaturalDoubleTapWithFourHundredMillisecondFirstTap() {
        var gesture = ShortcutGesture()
        XCTAssertEqual(gesture.press(at: 0), [.beginHold])
        XCTAssertEqual(gesture.release(at: 0.4), [])
        XCTAssertEqual(gesture.press(at: 0.7), [.handsFree])
        XCTAssertEqual(gesture.release(at: 0.8), [])
    }
    @MainActor func testModifierKeyEchoDoesNotCancelFnRecording() throws {
        let shortcut = GlobalShortcut(); defer { shortcut.stop() }
        shortcut.binding = ActivationShortcut(keyCode: nil, flags: .maskSecondaryFn)
        shortcut.pressed = { true }
        var cancellations = 0; shortcut.cancelled = { cancellations += 1 }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true))
        event.flags = .maskSecondaryFn
        shortcut.handle(.flagsChanged, event)
        shortcut.handle(.keyDown, event)
        XCTAssertEqual(cancellations, 0)
        event.setIntegerValueField(.keyboardEventKeycode, value: 49)
        shortcut.handle(.keyDown, event)
        XCTAssertEqual(cancellations, 1, "Fn+Space still cancels a modifier-only activation")
    }
}
