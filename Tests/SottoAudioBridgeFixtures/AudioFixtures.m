#import "SottoAudioBridgeFixtures.h"
#import <SottoAudioBridge.h>

// Message-compatible stand-ins. No real audio engine, microphone, or Speech task.
@interface SottoInputFixture : NSObject
@property BOOL throwAtInstall;
@property BOOL receivedHardwareFormat;
@end
@implementation SottoInputFixture
- (AVAudioFormat *)inputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
}
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:1];
}
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    if (self.throwAtInstall) {
        [NSException raise:@"com.apple.coreaudio.avfaudio" format:@"Fixture format changed during installation"];
    }
    self.receivedHardwareFormat = format.sampleRate == 48000 && format.channelCount == 1;
}
@end

@interface SottoEngineFixture : NSObject
@end
@implementation SottoEngineFixture
- (void)prepare { [NSException raise:@"com.apple.coreaudio.avfaudio" format:@"Fixture prepare exception"]; }
- (void)stop { [NSException raise:@"com.apple.coreaudio.avfaudio" format:@"Fixture stop exception"]; }
@end

BOOL SottoTestUsesCurrentHardwareFormat(void) {
    SottoInputFixture *input = [SottoInputFixture new];
    NSError *error = SottoInstallMicrophoneTap((AVAudioInputNode *)input, ^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {});
    return error == nil && input.receivedHardwareFormat;
}
NSError *SottoTestTapException(void) {
    SottoInputFixture *input = [SottoInputFixture new];
    input.throwAtInstall = YES;
    return SottoInstallMicrophoneTap((AVAudioInputNode *)input, ^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {});
}
NSError *SottoTestPrepareException(void) { return SottoStartAudioEngine((AVAudioEngine *)[SottoEngineFixture new]); }
NSError *SottoTestStopException(void) { return SottoStopAudioEngine((AVAudioEngine *)[SottoEngineFixture new], YES); }
