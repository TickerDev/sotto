import Foundation
import CoreAudio
import Observation

public struct Microphone: Identifiable, Sendable, Equatable {
    public var id: String { uid }
    public let uid: String
    public let deviceID: UInt32
    public let name: String
    public init(uid: String, deviceID: UInt32, name: String) { self.uid = uid; self.deviceID = deviceID; self.name = name }
}
public enum Microphones {
    public static let legacySelection = "sotto:reselect-legacy-microphone"
    public static func available() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0, usableInput(id),
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            return Microphone(uid: uid, deviceID: id, name: string(id, selector: kAudioObjectPropertyName) ?? "Microphone")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func usableInput(_ id: AudioDeviceID) -> Bool {
        var aliveAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &aliveAddress, 0, nil, &size, &alive) == noErr, alive != 0 else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).contains { $0.mNumberChannels > 0 }
    }
    private static func string(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }
    public static func defaultInputID() -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return 0 }
        return id
    }
    public static func resolve(uid: String, devices: [Microphone], defaultInputID: UInt32, excluding: Set<String> = []) throws -> Microphone {
        let available = devices.filter { !excluding.contains($0.uid) }
        let device = available.first { !$0.uid.isEmpty && $0.uid == uid }
            ?? available.first { $0.deviceID == defaultInputID }
            ?? available.sorted { $0.uid < $1.uid }.first
        guard let device else { throw SpeechError.microphoneUnavailable("No working microphone is available. Connect an input device and try again.") }
        return device
    }

}

/// Hardware listeners are retained and removed with the exact same queue/block pair.
@MainActor @Observable public final class MicrophoneCatalog {
    public private(set) var devices: [Microphone] = []
    public private(set) var defaultInputID: UInt32 = 0
    public private(set) var monitoringAvailable = false
    public var changed: (() -> Void)?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let inventory: @MainActor () -> ([Microphone], UInt32)
    public init(observeHardware: Bool = true, inventory: @escaping @MainActor () -> ([Microphone], UInt32) = { (Microphones.available(), Microphones.defaultInputID()) }) {
        self.inventory = inventory
        refresh(); if observeHardware { start() }
    }
    public func refresh() {
        (devices, defaultInputID) = inventory()
        changed?()
    }
    public func selected(_ uid: String, excluding: Set<String> = []) throws -> Microphone { try Microphones.resolve(uid: uid, devices: devices, defaultInputID: defaultInputID, excluding: excluding) }
    private func start() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in Task { @MainActor in self?.refresh() } }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr { listeners.append((address, block)) }
        }
        monitoringAvailable = listeners.count == 2
    }
    public func stop() {
        for (var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) }
        listeners = []; monitoringAvailable = false
    }
}
