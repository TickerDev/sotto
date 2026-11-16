#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Contain AVFoundation's Objective-C exceptions at the framework boundary.
FOUNDATION_EXPORT NSError * _Nullable SottoConfigureMicrophoneEngine(AVAudioEngine *engine, UInt32 deviceID);
FOUNDATION_EXPORT NSError * _Nullable SottoInstallMicrophoneTap(AVAudioInputNode *input, AVAudioNodeTapBlock block);
FOUNDATION_EXPORT NSError * _Nullable SottoStartAudioEngine(AVAudioEngine *engine);
FOUNDATION_EXPORT NSError * _Nullable SottoStopAudioEngine(AVAudioEngine *engine, BOOL removeTap);
NS_ASSUME_NONNULL_END
