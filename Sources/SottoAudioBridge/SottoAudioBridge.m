#import "SottoAudioBridge.h"
#import <math.h>
#import <AudioToolbox/AudioToolbox.h>

static NSError *SottoAudioFailure(void) {
    return [NSError errorWithDomain:@"org.sotto.mac.audio" code:1 userInfo:@{
        NSLocalizedDescriptionKey: @"The microphone changed format while starting. Recording was stopped safely. Try again, or choose another microphone in Voice settings."
    }];
}

NSError *SottoConfigureMicrophoneEngine(AVAudioEngine *engine, UInt32 deviceID) {
    @try {
        // Configure the input HAL directly without touching outputNode (which
        // triggers canPerformIO errors on input-only mics) and disable output
        // IO so Bluetooth headphones are not pulled into duplex/HFP routing.
        AudioUnit input = engine.inputNode.audioUnit;
        if (!input || deviceID == 0) { return SottoAudioFailure(); }
        UInt32 disabled = 0, enabled = 1;
        if (AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, sizeof(disabled)) != noErr ||
            AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled)) != noErr ||
            AudioUnitSetProperty(input, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, sizeof(deviceID)) != noErr) {
            return SottoAudioFailure();
        }
        UInt32 actual = 0, size = sizeof(actual);
        UInt32 outEnabled = 1, outSize = sizeof(outEnabled);
        if (AudioUnitGetProperty(input, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &size) != noErr ||
            actual != deviceID ||
            AudioUnitGetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &outEnabled, &outSize) != noErr ||
            outEnabled != 0) {
            return SottoAudioFailure();
        }
        return nil;
    } @catch (NSException *exception) {
        return SottoAudioFailure();
    }
}

NSError *SottoInstallMicrophoneTap(AVAudioInputNode *input, AVAudioNodeTapBlock block) {
    @try {
        // The hardware input format is authoritative; the output/client format
        // can still describe the previous Bluetooth rate during a route change.
        AVAudioFormat *format = [input inputFormatForBus:0];
        if (!isfinite(format.sampleRate) || format.sampleRate <= 0 || format.channelCount == 0) {
            return SottoAudioFailure();
        }
        [input installTapOnBus:0 bufferSize:1024 format:format block:block];
        return nil;
    } @catch (NSException *exception) {
        // No hardware details or captured audio are included in the error.
        return SottoAudioFailure();
    }
}

NSError *SottoStartAudioEngine(AVAudioEngine *engine) {
    @try {
        [engine prepare];
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) { return error ?: SottoAudioFailure(); }
        return nil;
    } @catch (NSException *exception) {
        return SottoAudioFailure();
    }
}

NSError *SottoStopAudioEngine(AVAudioEngine *engine, BOOL removeTap) {
    @try {
        [engine stop];
        if (removeTap) { [engine.inputNode removeTapOnBus:0]; }
        return nil;
    } @catch (NSException *exception) {
        return SottoAudioFailure();
    }
}
