@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import SottoAudioBridge

enum CaptureInput {
    static func configure(_ engine: AVAudioEngine, deviceID: UInt32) throws -> AudioInputConfiguration {
        let selected = deviceID == 0 ? Microphones.defaultInputID() : deviceID
        if let error = SottoConfigureMicrophoneEngine(engine, selected) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
        guard let configuration = configuration(engine), configuration.isUsable, configuration.deviceID == selected else {
            throw SpeechError.microphoneUnavailable("Couldn’t use the selected microphone. Choose an available input in Voice settings.")
        }
        return configuration
    }
    static func configuration(_ engine: AVAudioEngine) -> AudioInputConfiguration? {
        let input = engine.inputNode
        guard let unit = input.audioUnit else { return nil }
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size) == noErr else { return nil }
        let format = input.inputFormat(forBus: 0).streamDescription.pointee
        return AudioInputConfiguration(deviceID: device, sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame, formatID: format.mFormatID, formatFlags: format.mFormatFlags, bytesPerFrame: format.mBytesPerFrame, bitsPerChannel: format.mBitsPerChannel)
    }
}
