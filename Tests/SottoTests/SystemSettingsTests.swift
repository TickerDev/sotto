import XCTest
import SottoTools
import SottoSecurity
import SottoProviders
@testable import SottoAgent
@testable import SottoIntegrations
@testable import SottoUI

private actor SettingsProbe {
    var executions: [(tool: String, arguments: JSONValue)] = []
    func record(_ tool: String, _ arguments: JSONValue) {
        executions.append((tool, arguments))
    }
}

private struct ProbeSettingsTool: Tool {
    let descriptor: ToolDescriptor
    let probe: SettingsProbe
    var resultSummary: String

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        await probe.record(descriptor.id, arguments)
        return ToolResult(resultSummary)
    }
}

private actor AccessGateSignal {
    var continuation: CheckedContinuation<Void, Never>?
    func wait(_ started: @Sendable () -> Void) async {
        await withCheckedContinuation {
            continuation = $0
            started()
        }
    }
    func grant() {
        continuation?.resume()
        continuation = nil
    }
}

private actor MockSottoBridge: SottoSettingsBridge {
    var appearance = "system"
    var audioFeedback = true
    var notifications = false

    func apply(setting: SottoSettingKey, action: String, value: String) async throws -> ToolResult {
        if setting == .appearance {
            if action == "status" {
                return ToolResult("Sotto appearance is \(appearance)", data: .object(["appearance": .string(appearance)]))
            }
            guard ["system", "light", "dark"].contains(value.lowercased()) else {
                throw ToolError.invalid("Invalid appearance")
            }
            appearance = value.lowercased()
            return ToolResult("Set Sotto appearance to \(appearance)", data: .object(["appearance": .string(appearance)]))
        }
        if setting == .audio_feedback {
            if action == "status" {
                return ToolResult("Audio feedback is \(audioFeedback ? "on" : "off")", data: .object(["enabled": .bool(audioFeedback)]))
            }
            let target = action == "toggle" ? !audioFeedback : (action == "on")
            audioFeedback = target
            return ToolResult("Turned audio feedback \(target ? "on" : "off") in Sotto", data: .object(["enabled": .bool(target)]))
        }
        if setting == .notifications {
            let target = action == "toggle" ? !notifications : (action == "on")
            notifications = target
            return ToolResult("Turned notifications \(target ? "on" : "off") in Sotto", data: .object(["enabled": .bool(target)]))
        }
        return ToolResult("Updated \(setting.rawValue)")
    }
}

final class SystemSettingsTests: XCTestCase, @unchecked Sendable {
    func testNativeCommandProviderParsesDirectAndAccessibilitySettings() throws {
        let nightShift = try XCTUnwrap(NativeCommandProvider(command: "Turn on Night Shift"))
        XCTAssertEqual(nightShift.tool, "system_settings")
        XCTAssertEqual(nightShift.arguments.object?["setting"], .string("night_shift"))
        XCTAssertEqual(nightShift.arguments.object?["action"], .string("on"))

        let nightShiftOff = try XCTUnwrap(NativeCommandProvider(command: "Turn Night Shift off!"))
        XCTAssertEqual(nightShiftOff.tool, "system_settings")
        XCTAssertEqual(nightShiftOff.arguments.object?["setting"], .string("night_shift"))
        XCTAssertEqual(nightShiftOff.arguments.object?["action"], .string("off"))

        let warmth = try XCTUnwrap(NativeCommandProvider(command: "Set Night Shift warmth to 65%"))
        XCTAssertEqual(warmth.arguments.object?["setting"], .string("night_shift"))
        XCTAssertEqual(warmth.arguments.object?["action"], .string("set"))
        XCTAssertEqual(warmth.arguments.object?["value"], .string("65"))

        let lightMode = try XCTUnwrap(NativeCommandProvider(command: "Switch to light mode"))
        XCTAssertEqual(lightMode.arguments.object?["setting"], .string("dark_mode"))
        XCTAssertEqual(lightMode.arguments.object?["action"], .string("off"))

        let wifi = try XCTUnwrap(NativeCommandProvider(command: "Disable Wi-Fi"))
        XCTAssertEqual(wifi.arguments.object?["setting"], .string("wifi"))
        XCTAssertEqual(wifi.arguments.object?["action"], .string("off"))

        let volume = try XCTUnwrap(NativeCommandProvider(command: "Set volume to 45 percent"))
        XCTAssertEqual(volume.arguments.object?["setting"], .string("volume"))
        XCTAssertEqual(volume.arguments.object?["action"], .string("set"))
        XCTAssertEqual(volume.arguments.object?["value"], .string("45"))

        let brightnessUp = try XCTUnwrap(NativeCommandProvider(command: "Turn brightness up"))
        XCTAssertEqual(brightnessUp.arguments.object?["setting"], .string("brightness"))
        XCTAssertEqual(brightnessUp.arguments.object?["action"], .string("up"))

        let lowPower = try XCTUnwrap(NativeCommandProvider(command: "Turn on Low Power Mode"))
        XCTAssertEqual(lowPower.tool, "system_settings_ui")
        XCTAssertEqual(lowPower.arguments.object?["pane"], .string("Battery"))
        XCTAssertEqual(lowPower.arguments.object?["control"], .string("Low Power Mode"))
        XCTAssertEqual(lowPower.arguments.object?["action"], .string("on"))

        let batterySavingOff = try XCTUnwrap(NativeCommandProvider(command: "Turn off battery saving"))
        XCTAssertEqual(batterySavingOff.tool, "system_settings_ui")
        XCTAssertEqual(batterySavingOff.arguments.object?["pane"], .string("Battery"))
        XCTAssertEqual(batterySavingOff.arguments.object?["control"], .string("Low Power Mode"))
        XCTAssertEqual(batterySavingOff.arguments.object?["action"], .string("off"))

        let politeBatterySaver = try XCTUnwrap(NativeCommandProvider(command: "Please turn on power saving mode"))
        XCTAssertEqual(politeBatterySaver.tool, "system_settings_ui")
        XCTAssertEqual(politeBatterySaver.arguments.object?["control"], .string("Low Power Mode"))
        XCTAssertEqual(politeBatterySaver.arguments.object?["action"], .string("on"))

        let lockScreen = try XCTUnwrap(NativeCommandProvider(command: "Lock my screen"))
        XCTAssertEqual(lockScreen.tool, "system_power")
        XCTAssertEqual(lockScreen.arguments.object?["action"], .string("lock_screen"))

        let reduceMotion = try XCTUnwrap(NativeCommandProvider(command: "Enable Reduce Motion"))
        XCTAssertEqual(reduceMotion.tool, "system_settings_ui")
        XCTAssertEqual(reduceMotion.arguments.object?["pane"], .string("Accessibility"))
        XCTAssertEqual(reduceMotion.arguments.object?["control"], .string("Reduce motion"))
        XCTAssertEqual(reduceMotion.arguments.object?["action"], .string("on"))

        let pane = try XCTUnwrap(NativeCommandProvider(command: "Open Display settings"))
        XCTAssertEqual(pane.tool, "system_settings")
        XCTAssertEqual(pane.arguments.object?["setting"], .string("open_pane"))
        XCTAssertEqual(pane.arguments.object?["action"], .string("open"))
        XCTAssertEqual(pane.arguments.object?["value"], .string("display"))

        let privacyPane = try XCTUnwrap(NativeCommandProvider(command: "Open Privacy and Security settings"))
        XCTAssertEqual(privacyPane.tool, "system_settings")
        XCTAssertEqual(privacyPane.arguments.object?["setting"], .string("open_pane"))
        XCTAssertEqual(privacyPane.arguments.object?["value"], .string("privacy & security"))

        XCTAssertNil(NativeCommandProvider(command: "Open Sotto settings"))
    }

    func testNativeCompoundSettingCommandsExecuteSequentially() async throws {
        let probe = SettingsProbe()
        let descriptors = NativeTools.registry().descriptors
        let tools = descriptors.map { ProbeSettingsTool(descriptor: $0, probe: probe, resultSummary: "Done \($0.id)") }
        let runtime = AgentRuntime(registry: ToolRegistry(tools), gate: AuthorizationGate())
        let command = "Turn off Night Shift and turn on battery saver"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))
        _ = try await runtime.run(command, provider: provider) { _ in }
        let executions = await probe.executions
        XCTAssertEqual(executions.count, 2)
        XCTAssertEqual(executions[0].tool, "system_settings")
        XCTAssertEqual(executions[0].arguments.object?["setting"], .string("night_shift"))
        XCTAssertEqual(executions[0].arguments.object?["action"], .string("off"))
        XCTAssertEqual(executions[1].tool, "system_settings_ui")
        XCTAssertEqual(executions[1].arguments.object?["pane"], .string("Battery"))
        XCTAssertEqual(executions[1].arguments.object?["control"], .string("Low Power Mode"))
        XCTAssertEqual(executions[1].arguments.object?["action"], .string("on"))
    }

    func testNativeCompoundWithFillersAndPunctuationParsesAndExecutes() async throws {
        let probe = SettingsProbe()
        let descriptors = NativeTools.registry().descriptors
        let tools = descriptors.map { ProbeSettingsTool(descriptor: $0, probe: probe, resultSummary: "Done \($0.id)") }
        let runtime = AgentRuntime(registry: ToolRegistry(tools), gate: AuthorizationGate())

        let command = "All right, let's turn on low power mode, and set the volume to 50%."
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))
        _ = try await runtime.run(command, provider: provider) { _ in }
        let executions = await probe.executions
        XCTAssertEqual(executions.count, 2)
        XCTAssertEqual(executions[0].tool, "system_settings_ui")
        XCTAssertEqual(executions[0].arguments.object?["pane"], .string("Battery"))
        XCTAssertEqual(executions[0].arguments.object?["control"], .string("Low Power Mode"))
        XCTAssertEqual(executions[0].arguments.object?["action"], .string("on"))
        XCTAssertEqual(executions[1].tool, "system_settings")
        XCTAssertEqual(executions[1].arguments.object?["setting"], .string("volume"))
        XCTAssertEqual(executions[1].arguments.object?["action"], .string("set"))
        XCTAssertEqual(executions[1].arguments.object?["value"], .string("50"))

        XCTAssertNotNil(NativeCommandProvider(command: "Okay, turn off Night Shift, and then turn on battery saver!"))

        let audioProvider = try XCTUnwrap(NativeCommandProvider(command: "Turn on low power mode, set the audio to 50%"))
        XCTAssertEqual(audioProvider.tool, "system_settings_ui")

        let audioAdjust = try XCTUnwrap(NativeCommandProvider(command: "Change audio volume to 35 percent"))
        XCTAssertEqual(audioAdjust.tool, "system_settings")
        XCTAssertEqual(audioAdjust.arguments.object?["setting"], .string("volume"))
        XCTAssertEqual(audioAdjust.arguments.object?["action"], .string("set"))
        XCTAssertEqual(audioAdjust.arguments.object?["value"], .string("35"))

        let audioUp = try XCTUnwrap(NativeCommandProvider(command: "Turn up the audio"))
        XCTAssertEqual(audioUp.tool, "system_settings")
        XCTAssertEqual(audioUp.arguments.object?["setting"], .string("volume"))
        XCTAssertEqual(audioUp.arguments.object?["action"], .string("up"))
    }

    func testSystemSettingsPaneCatalogResolvesMainAndAccessibilitySubpanes() {
        XCTAssertEqual(
            SystemSettingsPaneCatalog.resolve("Battery")?.url.absoluteString,
            "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        )
        XCTAssertEqual(
            SystemSettingsPaneCatalog.resolve("Battery saver")?.url.absoluteString,
            "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        )
        XCTAssertEqual(
            SystemSettingsPaneCatalog.resolve("Accessibility", controlHint: "Reduce motion")?.url.absoluteString,
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Motion"
        )
        XCTAssertEqual(
            SystemSettingsPaneCatalog.resolve("Accessibility", controlHint: "Increase contrast")?.url.absoluteString,
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display"
        )
        XCTAssertEqual(
            SystemSettingsPaneCatalog.resolve("Privacy & Security")?.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    func testControlMatcherScoringAndNormalization() {
        XCTAssertEqual(SystemSettingsControlMatcher.score(query: "Low Power Mode", candidate: "Low Power Mode"), 100)
        XCTAssertEqual(SystemSettingsControlMatcher.score(query: "Reduce motion", candidate: "Reduce motion…"), 100)
        XCTAssertGreaterThan(
            SystemSettingsControlMatcher.score(query: "Tap to click", candidate: "Tap to click (Tap with one finger)"),
            SystemSettingsControlMatcher.score(query: "Tap to click", candidate: "Secondary click")
        )
        XCTAssertEqual(SystemSettingsControlMatcher.score(query: "VoiceOver", candidate: "Trackpad"), 0)

        // Ensure generic/contradictory LLM placeholders never hijack on/off popup selection
        XCTAssertEqual(
            SystemSettingsControlMatcher.desiredPopupCandidates(action: .on, value: "true", current: "Never"),
            ["Always", "On", "Enabled"]
        )
        XCTAssertEqual(
            SystemSettingsControlMatcher.desiredPopupCandidates(action: .on, value: "Never", current: "Never"),
            ["Always", "On", "Enabled"]
        )
        XCTAssertEqual(
            SystemSettingsControlMatcher.desiredPopupCandidates(action: .off, value: "Always", current: "Always"),
            ["Never", "Off", "Disabled"]
        )
        XCTAssertEqual(
            SystemSettingsControlMatcher.desiredPopupCandidates(action: .on, value: "Only on Battery", current: "Never"),
            ["Only on Battery"]
        )

        let lowPowerChoices = ["Never", "Always", "Only on Battery", "Only on Power Adapter"]
        XCTAssertEqual(
            SystemSettingsControlMatcher.bestPopupOptionIndex(titles: lowPowerChoices, desiredCandidates: ["Always", "On", "Enabled"]),
            1
        )
        XCTAssertEqual(
            SystemSettingsControlMatcher.bestPopupOptionIndex(titles: lowPowerChoices, desiredCandidates: ["Never", "Off", "Disabled"]),
            0
        )
        // "On" must not falsely match "Only on Battery"
        XCTAssertNil(
            SystemSettingsControlMatcher.bestPopupOptionIndex(titles: ["Never", "Only on Battery", "Only on Power Adapter"], desiredCandidates: ["On"])
        )
        XCTAssertEqual(
            SystemSettingsControlMatcher.bestPopupOptionIndex(titles: ["Off", "On"], desiredCandidates: ["Always", "On", "Enabled"]),
            1
        )
    }

    func testSettingDescriptorsUseStringPropertiesAndSafeRiskLevels() async throws {
        let registry = NativeTools.registry()
        let gate = AuthorizationGate()

        for toolID in ["system_settings", "system_settings_ui", "sotto_settings"] {
            let descriptor = try registry.tool(toolID).descriptor
            XCTAssertEqual(descriptor.risk, .reversible)
            XCTAssertTrue(descriptor.capabilities.contains(.settings))
            let properties = try XCTUnwrap(descriptor.inputSchema.object?["properties"]?.object)
            for (name, property) in properties {
                XCTAssertEqual(property.object?["type"]?.string, "string", "\(toolID).\(name) must remain a string property for FoundationModels compatibility")
            }
        }

        let powerDesc = try registry.tool("system_power").descriptor
        XCTAssertEqual(powerDesc.risk, .consequential)
        let powerProperties = try XCTUnwrap(powerDesc.inputSchema.object?["properties"]?.object)
        for (name, property) in powerProperties {
            XCTAssertEqual(property.object?["type"]?.string, "string", "system_power.\(name) must remain a string property")
        }

        let approvalSeen = expectation(description: "system_power requires explicit approval")
        do {
            try await gate.authorize(powerDesc, arguments: .object(["action": .string("lock_screen")])) { request in
                approvalSeen.fulfill()
                await gate.resolve(request.id, allowed: false)
            }
            XCTFail("system_power must require approval")
        } catch is ToolError {}
        await fulfillment(of: [approvalSeen], timeout: 1)

        let sysDesc = try registry.tool("system_settings").descriptor
        try await gate.authorize(sysDesc, arguments: .object(["setting": .string("night_shift"), "action": .string("on")])) { request in
            XCTFail("Requested setting change should not ask for second approval")
            await gate.resolve(request.id, allowed: false)
        }

        do {
            _ = try await registry.tool("system_settings").execute(arguments: .object(["setting": .string("not_listed"), "action": .string("on")]))
            XCTFail("not_listed must fail cleanly without mutating any setting")
        } catch let error as ToolError {
            XCTAssertTrue(error.localizedDescription.contains("system_settings_ui"))
        }

        let uiDesc = try registry.tool("system_settings_ui").descriptor
        XCTAssertTrue(uiDesc.capabilities.contains(.accessibility))
        try await gate.authorize(uiDesc, arguments: .object(["pane": .string("Battery"), "control": .string("Low Power Mode"), "action": .string("on")])) { request in
            XCTFail("Requested UI setting change should authorize directly once Accessibility is prepared")
            await gate.resolve(request.id, allowed: false)
        }

        do {
            try await gate.authorize(sysDesc, arguments: .object(["setting": .string("invalid_setting"), "action": .string("on")])) { _ in
                XCTFail("Invalid setting must fail validation")
            }
            XCTFail("Invalid setting was accepted")
        } catch is ToolError {}
    }

    func testAccessibilityBackedSettingWaitsForPermissionBeforeExecuting() async throws {
        let probe = SettingsProbe()
        let uiDescriptor = try NativeTools.registry().tool("system_settings_ui").descriptor
        let runtime = AgentRuntime(
            registry: ToolRegistry([ProbeSettingsTool(descriptor: uiDescriptor, probe: probe, resultSummary: "Turned on Low Power Mode")]),
            gate: AuthorizationGate()
        )
        let signal = AccessGateSignal()
        let awaitingPermission = expectation(description: "Accessibility permission pending")
        let command = "Turn on Low Power Mode"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))

        let task = Task {
            try await runtime.run(command, provider: provider, prepare: { descriptor in
                XCTAssertTrue(descriptor.capabilities.contains(.accessibility))
                await signal.wait { awaitingPermission.fulfill() }
            }) { _ in }
        }

        await fulfillment(of: [awaitingPermission], timeout: 2)
        let beforeGrant = await probe.executions
        XCTAssertTrue(beforeGrant.isEmpty, "UI setting must not run while Accessibility permission is pending")

        await signal.grant()
        _ = try await task.value
        let afterGrant = await probe.executions
        XCTAssertEqual(afterGrant.count, 1)
        XCTAssertEqual(afterGrant[0].tool, "system_settings_ui")
    }

    func testDeniedAccessibilityBlocksExecutionCleanly() async throws {
        let probe = SettingsProbe()
        let uiDescriptor = try NativeTools.registry().tool("system_settings_ui").descriptor
        let runtime = AgentRuntime(
            registry: ToolRegistry([ProbeSettingsTool(descriptor: uiDescriptor, probe: probe, resultSummary: "Turned on Low Power Mode")]),
            gate: AuthorizationGate()
        )
        let command = "Turn on Low Power Mode"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))

        do {
            _ = try await runtime.run(command, provider: provider, prepare: { _ in
                throw IntegrationAccessError.notGranted("Accessibility")
            }) { _ in }
            XCTFail("Expected IntegrationAccessError.notGranted")
        } catch let error as IntegrationAccessError {
            XCTAssertTrue(error.localizedDescription.contains("Accessibility"))
        }
        let executions = await probe.executions
        XCTAssertTrue(executions.isEmpty)
    }

    func testSottoSettingsBridgeUpdatesAndValidatesPreferences() async throws {
        let bridge = MockSottoBridge()
        let registry = NativeTools.registry(sottoSettings: bridge)
        let tool = try registry.tool("sotto_settings")

        let darkResult = try await tool.execute(arguments: .object([
            "setting": .string("appearance"),
            "action": .string("set"),
            "value": .string("dark")
        ]))
        XCTAssertEqual(darkResult.data.object?["appearance"], .string("dark"))

        let feedbackResult = try await tool.execute(arguments: .object([
            "setting": .string("audio_feedback"),
            "action": .string("toggle")
        ]))
        XCTAssertEqual(feedbackResult.data.object?["enabled"], .bool(false))
    }

    @MainActor
    func testPermissionModelSupportsAccessibilityAndAutomationRecovery() {
        XCTAssertEqual(PermissionKind.accessibility.title, "Accessibility")
        XCTAssertTrue(PermissionKind.accessibility.settingsURL.absoluteString.contains("Privacy_Accessibility"))
        XCTAssertEqual(IntegrationAccessRequest(kind: .accessibility).kind, .accessibility)
        XCTAssertEqual(RecoveryAction.permission(.accessibility).title, "Open Accessibility Settings")
        XCTAssertEqual(RecoveryAction.permission(.automation).title, "Open Automation Settings")
    }

    func testReadOnlyHardwareSettingsStatusDoesNotCrash() async throws {
        let tool = try NativeTools.registry().tool("system_settings")
        for setting in ["night_shift", "true_tone", "brightness", "volume", "mute", "wifi", "bluetooth"] {
            do {
                let result = try await tool.execute(arguments: .object([
                    "setting": .string(setting),
                    "action": .string("status")
                ]))
                XCTAssertFalse(result.summary.isEmpty, "Empty status for \(setting)")
            } catch ToolError.unavailable {
                // Acceptable on displays/hardware without a particular sensor/feature.
            }
        }
    }

    func testLiveOnDeviceLowPowerAndVolumeRouting() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else {
            throw XCTSkip("Opt-in: real on-device generation, no action execution")
        }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else {
            throw XCTSkip("On-device intelligence unavailable")
        }
        let probe = SettingsProbe()
        let descriptors = NativeTools.registry().descriptors
        let definitionsSize = descriptors.map { "\($0.id): \($0.description)\n\($0.inputSchema.encoded)" }.joined(separator: "\n").count
        print("Definitions size:", definitionsSize)
        let tools = descriptors.map { ProbeSettingsTool(descriptor: $0, probe: probe, resultSummary: "Done \($0.id)") }
        let runtime = AgentRuntime(registry: ToolRegistry(tools), gate: AuthorizationGate())
        _ = try await runtime.run("All right, let's turn on low power mode and set the volume to 50%.", provider: OnDeviceProvider()) { event in
            if case .failure(let tool, let err) = event { print("Probe failure:", tool, err) }
            if case .text(let s) = event { print("Probe text:", s) }
        }
        let executions = await probe.executions
        print("Live executions:", executions.map { "\($0.tool): \($0.arguments.encoded)" })
        XCTAssertFalse(executions.isEmpty)
    }
}
