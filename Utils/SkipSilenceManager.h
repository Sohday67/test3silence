//
//  SkipSilenceManager.h
//  YTLiteSkipSilence
//
//  Real-time skip-silence + voice-boost audio engine for YouTube's AVPlayer.
//
//  Algorithm inspired by Overcast's OCAudioStreamer / OCVoiceBoostLookahead.c:
//      • A look-ahead RMS envelope follower detects silent regions in the
//        incoming PCM audio from YouTube's AVPlayerItem.
//      • When the rolling RMS drops below a configurable dBFS threshold for
//        longer than a hold-time (default 150 ms), the player's playback
//        rate is bumped to a "silence speed" (default 2.5x).
//      • When the RMS rises back above the threshold for longer than a
//        release-time (default 40 ms), the user's normal rate is restored.
//
//  Implementation detail:
//      Audio is intercepted via MTAudioProcessingTap attached to the
//      AVPlayerItem.audioMix – the only Apple-sanctioned way to read PCM
//      samples off a vanilla AVPlayer without re-hosting playback.
//
//  The Overcast IPA was used as a behavioural reference; this file is an
//  independent reimplementation for personal use.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <MediaToolbox/MediaToolbox.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark – Tunables

/// RMS window length (frames per measurement). At 48 kHz stereo this is ~3 ms.
/// Smaller = more reactive but noisier; larger = smoother but laggier.
extern const NSUInteger kSkipSilenceRMSWindowFrames;

/// How long (seconds) RMS must stay below threshold before we speed up.
/// Preserves natural inter-word pauses (Overcast ships ~150 ms).
extern const NSTimeInterval kSkipSilenceDefaultHoldTime;

/// How long (seconds) RMS must stay above threshold before we slow down.
/// Prevents chatter on noisy speech (Overcast ships ~40 ms).
extern const NSTimeInterval kSkipSilenceDefaultReleaseTime;

/// Default silence threshold in dBFS (Breaker/Overcast convention).
/// Quieter than this is considered "silent".
extern const float kSkipSilenceDefaultThresholdDBFS;

/// Default rate applied to silent regions (Overcast ~2.5x).
extern const float kSkipSilenceDefaultSilenceRate;

#pragma mark – SkipSilenceState

typedef NS_ENUM(NSInteger, SkipSilenceState) {
    SkipSilenceStateInactive = 0, // tap installed, monitoring but not currently silencing
    SkipSilenceStateSilencing      // currently speeding through a silent region
};

#pragma mark – SkipSilenceManager

@interface SkipSilenceManager : NSObject

/// Shared singleton. Safe to call from any thread.
+ (instancetype)shared;

/// Master switch. When NO, all taps are detached and rate is restored.
/// YTVideoOverlay button toggles this; settings pane also writes here.
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

// ---- tunables (user-facing, mirrored to NSUserDefaults) --------------------

/// Threshold in dBFS. Default -35. Range -60..-10.
@property (nonatomic, assign) float thresholdDBFS;

/// Speed applied during silent regions. Default 2.5. Range 1.5..4.0.
@property (nonatomic, assign) float silenceRate;

/// Hold time before activating silence-speed. Default 0.15 s.
@property (nonatomic, assign) NSTimeInterval holdTime;

/// Release time before restoring normal rate. Default 0.04 s.
@property (nonatomic, assign) NSTimeInterval releaseTime;

// ---- runtime state ---------------------------------------------------------

/// Current detector state (KVO-observable for the icon to swap on/off).
@property (nonatomic, readonly) SkipSilenceState state;

/// The user's chosen "normal" rate, learned from YouTube's setPlaybackRate:.
/// We restore to this when silence ends.
@property (nonatomic, assign) float userPlaybackRate;

// ---- lifecycle -------------------------------------------------------------

/// Attach the MTAudioProcessingTap to a YouTube AVPlayerItem.
/// Idempotent – safe to call multiple times on the same item.
- (void)attachToPlayerItem:(AVPlayerItem *)item;

/// Detach the tap from a specific item (called on AVPlayerItem deallocation /
/// when YouTube swaps to the next video).
- (void)detachFromPlayerItem:(AVPlayerItem *)item;

/// Detach all taps (master-disable / video-change sweep).
- (void)detachAll;

/// Capture the AVPlayer that owns an item (used to set .rate).
- (void)registerPlayer:(AVPlayer *)player forItem:(AVPlayerItem *)item;

/// Forget the AVPlayer↔item association.
- (void)forgetPlayerForItem:(AVPlayerItem *)item;

@end

NS_ASSUME_NONNULL_END
