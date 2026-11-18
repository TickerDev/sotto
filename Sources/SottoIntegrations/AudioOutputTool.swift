import Foundation
import CoreAudio
import SottoTools

struct AudioOutputTool: Tool {
    let descriptor = ToolDescriptor(id: "audio.output", description: "List Core Audio output devices or select a device using its identifier. Devices without output streams are excluded.", properties: ["action": textProperty("Action", choices: ["list", "select"]), "device_id": .object(["type": .string("integer"), "description": .string("Device identifier from list; 0 when listing")])], required: ["action", "device_id"], risk: .reversible, capabilities: [.audio])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { throw ToolError.unavailable("Audio device discovery failed") }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { throw ToolError.unavailable("Audio device list could not be read") }
        let outputs = devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr && bytes > 0
        }
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current: AudioObjectID = 0; var currentSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &currentSize, &current) == noErr else { throw ToolError.unavailable("Default output could not be read") }
        if arguments.object?["action"]?.string == "select" {
            guard case .number(let n) = arguments.object?["device_id"], n >= 0, n <= Double(UInt32.max), outputs.contains(AudioObjectID(n)) else { throw ToolError.invalid("Select a current output-device identifier from audio.output list") }
            var target = AudioObjectID(n)
            guard AudioObjectSetPropertyData(system, &defaultAddress, 0, nil, currentSize, &target) == noErr else { throw ToolError.unavailable("This audio output cannot be selected") }
            guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &currentSize, &current) == noErr, current == target else { return ToolResult("Output selection requested, but not confirmed.", state: .partiallyCompleted) }
            return ToolResult("Selected audio output \(target)")
        }
        let rows: [JSONValue] = outputs.map { device in
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
            return .object(["device_id": .number(Double(device)), "name": .string((name?.takeRetainedValue() as String?) ?? "Audio output"), "selected": .bool(device == current)])
        }
        return ToolResult("Found \(rows.count) audio output devices", data: .array(rows))
    }
}
