import XCTest
import SottoAudio
@testable import SottoUI

final class DeviceAndSetupTests: XCTestCase, @unchecked Sendable {
    let builtIn = Microphone(uid: "builtin-uid", deviceID: 12, name: "Mac microphone")
    let headset = Microphone(uid: "headset-uid", deviceID: 42, name: "Headset")

    func testPinnedUIDSurvivesDeviceRenumbering() throws {
        let reconnected = Microphone(uid: "headset-uid", deviceID: 901, name: "Headset")
        let selected = try Microphones.resolve(uid: "headset-uid", devices: [builtIn, reconnected], defaultInputID: 12)
        XCTAssertEqual(selected.deviceID, 901)
        XCTAssertEqual(selected.uid, headset.uid)
    }
    func testDisconnectedPreferredInputFallsBackToSystemDefault() throws {
        XCTAssertEqual(try Microphones.resolve(uid: "headset-uid", devices: [builtIn], defaultInputID: 12).uid, builtIn.uid)
    }
    func testIdenticalNamesDoNotConfuseSelection() throws {
        let a = Microphone(uid: "usb-a", deviceID: 100, name: "USB microphone")
        let b = Microphone(uid: "usb-b", deviceID: 101, name: "USB microphone")
        XCTAssertEqual(try Microphones.resolve(uid: "usb-b", devices: [a, b], defaultInputID: 100).deviceID, 101)
    }
    func testSystemDefaultUsesCurrentDefaultAndRejectsMissingInput() throws {
        XCTAssertEqual(try Microphones.resolve(uid: "", devices: [builtIn, headset], defaultInputID: 42).uid, headset.uid)
        XCTAssertEqual(try Microphones.resolve(uid: "", devices: [builtIn], defaultInputID: 999).uid, builtIn.uid)
        XCTAssertEqual(try Microphones.resolve(uid: Microphones.legacySelection, devices: [builtIn], defaultInputID: 12).uid, builtIn.uid)
    }
    func testOldPreferencesPreserveChoicesAndRequireOneTimeMicrophoneSelection() throws {
        let data = Data(#"{"shortcut":2,"keyCode":79,"toggleToTalk":true,"appearance":"dark","microphone":42,"language":"fr-FR","model":"gpt-4.1","remoteConsent":true,"historyEnabled":false,"retentionDays":7}"#.utf8)
        let p = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(p.microphoneUID, Microphones.legacySelection)
        XCTAssertEqual(p.activationShortcut, .legacy(modifierIndex: 2, keyCode: 79))
        XCTAssertEqual(p.language, "fr-FR"); XCTAssertEqual(p.appearance, "dark"); XCTAssertEqual(p.model, "gpt-4.1")
        XCTAssertTrue(p.remoteConsent); XCTAssertFalse(p.historyEnabled); XCTAssertEqual(p.retentionDays, 7)
        XCTAssertTrue(p.setupCompleted)
    }
    func testNewPreferencesRoundTripAndDefaultsAreSafe() throws {
        var p = Preferences(); p.microphoneUID = "headset-uid"; p.microphoneName = "Headset"; p.setupDismissed = true; p.firstActionSucceeded = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.microphoneUID, "headset-uid"); XCTAssertEqual(decoded.microphoneName, "Headset")
        XCTAssertTrue(decoded.setupDismissed); XCTAssertTrue(decoded.firstActionSucceeded)
        let empty = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.remoteConsent); XCTAssertFalse(empty.setupCompleted); XCTAssertEqual(empty.microphoneUID, "")
        let oldDefault = try JSONDecoder().decode(Preferences.self, from: Data(#"{"microphone":0}"#.utf8))
        XCTAssertEqual(oldDefault.microphoneUID, "")
    }
    func testBadStoredOptionsAreNormalizedWithoutResettingOtherPreferences() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"shortcut":99,"keyCode":999,"retentionDays":-1,"language":"es-ES"}"#.utf8))
        XCTAssertEqual(p.activationShortcut, .legacy(modifierIndex: 2, keyCode: 49)); XCTAssertEqual(p.retentionDays, 30); XCTAssertEqual(p.language, "es-ES")
    }
    func testSetupCannotFinishWithoutConsentVoiceAndProviderButKeyboardIsOptional() {
        let ready = SetupReadiness(providerConnected: true, remoteConsent: true, voiceAllowed: true, microphoneAvailable: true, shortcutReady: false)
        XCTAssertTrue(ready.ready); XCTAssertEqual(ready.completedSteps, 3); XCTAssertTrue(ready.blockers.isEmpty)
        let noConsent = SetupReadiness(providerConnected: true, remoteConsent: false, voiceAllowed: true, microphoneAvailable: true, shortcutReady: true)
        XCTAssertFalse(noConsent.ready); XCTAssertEqual(noConsent.blockers.count, 1)
        let noVoice = SetupReadiness(providerConnected: true, remoteConsent: true, voiceAllowed: false, microphoneAvailable: false, shortcutReady: true)
        XCTAssertFalse(noVoice.ready); XCTAssertEqual(noVoice.blockers.count, 2)
        XCTAssertFalse(SetupReadiness(providerConnected: false, remoteConsent: true, voiceAllowed: true, microphoneAvailable: true, shortcutReady: true).ready)
    }
    func testDeniedAndRestrictedPermissionsAreNotRepeatedlyPrompted() {
        XCTAssertFalse(PermissionState.denied.canRequest); XCTAssertFalse(PermissionState.restricted.canRequest)
        XCTAssertFalse(PermissionState.allowed.canRequest); XCTAssertFalse(PermissionState.systemManaged.canRequest)
        XCTAssertTrue(PermissionState.notRequested.canRequest); XCTAssertTrue(PermissionState.notEnabled.canRequest)
    }
}
