//
//  SkipSilenceManager.h
//  YTLiteSkipSilence
//
//  Real-time skip-silence audio engine for YouTube's AVPlayer.
//
//  Algorithm inspired by Overcast's OCAudioStreamer / OCVoiceBoostLookahead.c:
//    - A look-ahead RMS envelope follower detects silent regions in the
//      incoming PCM audio from YouTube's AVPlayerItem.
//    - When the rolling RMS drops below a configurable dBFS threshold for
//      longer than a hold-time (default 150 ms), the player's playback
//      rate is bumped to a "silence speed" (default 2.5x).
//    - When the RMS rises back above the threshold for longer than a
//      release-time (default 40 ms), the user's normal rate is restored.
//
//  Audio is intercepted via MTAudioProcessingTap attached to the
//  AVPlayerItem.audioMix - the only Apple-sanctioned way to read PCM
//  samples off a vanilla AVPlayer without re-hosting playback.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kSkipSilenceRMSWindowFrames;
extern const NSTimeInterval kSkipSilenceDefaultHoldTime;
extern const NSTimeInterval kSkipSilenceDefaultReleaseTime;
extern const float kSkipSilenceDefaultThresholdDBFS;
extern const float kSkipSilenceDefaultSilenceRate;

typedef NS_ENUM(NSInteger, SkipSilenceState) {
    SkipSilenceStateInactive = 0,
    SkipSilenceStateSilencing
};

@interface SkipSilenceManager : NSObject

+ (instancetype)shared;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

@property (nonatomic, assign) float thresholdDBFS;
@property (nonatomic, assign) float silenceRate;
@property (nonatomic, assign) NSTimeInterval holdTime;
@property (nonatomic, assign) NSTimeInterval releaseTime;

@property (nonatomic, readonly) SkipSilenceState state;
@property (nonatomic, assign) float userPlaybackRate;

- (void)attachToPlayerItem:(AVPlayerItem *)item;
- (void)detachFromPlayerItem:(AVPlayerItem *)item;
- (void)detachAll;
- (void)registerPlayer:(AVPlayer *)player forItem:(AVPlayerItem *)item;
- (void)forgetPlayerForItem:(AVPlayerItem *)item;

@end

NS_ASSUME_NONNULL_END
