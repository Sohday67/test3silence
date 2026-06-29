//
//  SkipSilenceManager.m
//  YTLiteSkipSilence
//
//  Real-time silence detector + rate modulator, attached to YouTube's
//  AVPlayerItem via MTAudioProcessingTap. Algorithm inspired by Overcast's
//  OCAudioStreamer "skipSilences" / "silenceSkippingSpeed" pipeline.
//
//  NOTE: this is an independent reimplementation. The Overcast IPA was used
//  only as a behavioural reference; no code was copied verbatim.
//

#import "SkipSilenceManager.h"
#import "SkipSilenceDefaults.h"
#import <MediaToolbox/MediaToolbox.h>
#import <CoreMedia/CoreMedia.h>

// ---- tunables --------------------------------------------------------------
const NSUInteger   kSkipSilenceRMSWindowFrames   = 256;  // ~5 ms @ 48 kHz
const NSTimeInterval kSkipSilenceDefaultHoldTime   = 0.15;
const NSTimeInterval kSkipSilenceDefaultReleaseTime = 0.04;
const float         kSkipSilenceDefaultThresholdDBFS = -35.0f;
const float         kSkipSilenceDefaultSilenceRate   = 2.5f;

// ---- per-tap context -------------------------------------------------------

typedef struct {
    __unsafe_unretained SkipSilenceManager *manager;
    __unsafe_unretained AVPlayerItem        *item;
    float sampleRate;
} TapContext;

// ---- C callbacks (the tap invokes these directly) --------------------------

// Pending context — set immediately before MTAudioProcessingTapCreate and
// read by tapInitCallback (which is invoked synchronously during Create).
// We hold it via NSValue-wrapped pointers so ARC doesn't release the
// underlyings while the tap is being constructed.
static __weak SkipSilenceManager *sPendingManager = nil;
static __weak AVPlayerItem        *sPendingItem    = nil;

static void *tapInitCallback(MTAudioProcessingTapRef tap,
                             void *clientInfo,
                             void **tapStorageOut)
{
    TapContext *ctx = (TapContext *)calloc(1, sizeof(TapContext));
    ctx->manager = sPendingManager;
    ctx->item    = sPendingItem;
    ctx->sampleRate = 48000.0f;
    if (tapStorageOut) *tapStorageOut = ctx;
    return NULL; // we don't need an additional client storage return
}

static void tapFinalizeCallback(MTAudioProcessingTapRef tap, void *tapStorage)
{
    if (tapStorage) {
        free(tapStorage);
    }
}

static void tapPrepareCallback(MTAudioProcessingTapRef tap, void *tapStorage,
                               CMItemCount maxFrames,
                               const AudioStreamBasicDescription *processingFormat,
                               const AudioStreamBasicDescription *outputFormat)
{
    // Capture the actual sample rate so our time math is correct.
    TapContext *ctx = (TapContext *)tapStorage;
    if (ctx && processingFormat && processingFormat->mSampleRate > 0) {
        ctx->sampleRate = (float)processingFormat->mSampleRate;
        @synchronized (ctx->manager) {
            [ctx->manager->_itemToSampleRate setObject:@(ctx->sampleRate) forKey:ctx->item];
        }
    }
}

static void tapUnprepareCallback(MTAudioProcessingTapRef tap, void *tapStorage)
{
    (void)tap; (void)tapStorage;
}

static void tapProcessCallback(MTAudioProcessingTapRef tap, void *tapStorage,
                               CMItemCount numberFrames,
                               MTAudioProcessingTapFlags flags,
                               AudioBufferList *bufferListInOut,
                               CMItemCount *numberFramesOut,
                               MTAudioProcessingTapFlags *flagsOut)
{
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames,
                                                         bufferListInOut,
                                                         flagsOut,
                                                         NULL,
                                                         numberFramesOut);
    if (status != noErr || bufferListInOut == NULL) {
        return;
    }

    TapContext *ctx = (TapContext *)tapStorage;
    if (ctx == NULL || ctx->manager == nil || ctx->item == nil) {
        return;
    }
    SkipSilenceManager *mgr = ctx->manager;
    AVPlayerItem        *item = ctx->item;
    float sampleRate = ctx->sampleRate > 0 ? ctx->sampleRate : 48000.0f;

    // Compute RMS across all channels & frames in this buffer.
    double sumSq = 0.0;
    UInt64 totalSamples = 0;
    for (UInt32 bufIdx = 0; bufIdx < bufferListInOut->mNumberBuffers; bufIdx++) {
        AudioBuffer *ab = &bufferListInOut->mBuffers[bufIdx];
        if (ab->mData == NULL || ab->mDataByteSize == 0) continue;
        // Try Float32 first (most common). If the format isn't Float32 we
        // still treat the bytes as Float32 — worst case the RMS is wrong
        // for one buffer, which is harmless for our state machine.
        UInt32 framesHere = ab->mDataByteSize / sizeof(Float32);
        Float32 *p = (Float32 *)ab->mData;
        for (UInt32 i = 0; i < framesHere; i++) {
            float s = p[i];
            sumSq += (double)s * (double)s;
            totalSamples++;
        }
    }
    if (totalSamples == 0) return;

    double rms = sqrt(sumSq / (double)totalSamples);
    float dbfs = (rms > 1e-9) ? 20.0f * (float)log10(rms) : -160.0f;

    NSTimeInterval bufferDuration = (NSTimeInterval)totalSamples / (NSTimeInterval)sampleRate;
    [mgr feedSample:dbfs duration:bufferDuration forItem:item];
}

// ---- class -----------------------------------------------------------------

@interface SkipSilenceManager ()
{
    dispatch_queue_t _queue;                       // serialises all tap setup/teardown
    NSMapTable<AVPlayerItem *, NSValue *> *_itemToTap;     // value wraps MTAudioProcessingTapRef
    NSMapTable<AVPlayerItem *, AVPlayer *> *_itemToPlayer;
    NSMapTable<AVPlayerItem *, NSNumber *> *_itemToSampleRate;
    NSMapTable<AVPlayerItem *, NSMutableDictionary *> *_itemState;
}

@property (nonatomic, assign) SkipSilenceState state;
@property (nonatomic, strong) NSMutableSet<AVPlayer *> *activePlayers;
@end

// Per-item state keys (held in _itemState dict)
static NSString * const kStateBelowSinceKey  = @"belowSince";
static NSString * const kStateAboveSinceKey  = @"aboveSince";
static NSString * const kStateCurrentRateKey = @"currentRate";

@implementation SkipSilenceManager

+ (instancetype)shared {
    static SkipSilenceManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SkipSilenceManager new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.dvntm.ytlite.skipsilence", DISPATCH_QUEUE_SERIAL);
        _itemToTap        = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
                                                  valueOptions:NSMapTableStrongMemory];
        _itemToPlayer     = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
                                                  valueOptions:NSMapTableObjectPointerPersonality];
        _itemToSampleRate = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
                                                  valueOptions:NSMapTableStrongMemory];
        _itemState        = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
                                                  valueOptions:NSMapTableStrongMemory];
        _activePlayers    = [NSMutableSet set];
        _userPlaybackRate = 1.0f;
        _enabled = [SkipSilenceDefaults enabled];
        [self loadTunablesFromDefaults];
    }
    return self;
}

- (void)loadTunablesFromDefaults {
    _thresholdDBFS = [SkipSilenceDefaults thresholdDBFS];
    _silenceRate   = [SkipSilenceDefaults silenceRate];
    _holdTime      = [SkipSilenceDefaults holdTime];
    _releaseTime   = [SkipSilenceDefaults releaseTime];
}

#pragma mark – public properties

- (void)setEnabled:(BOOL)enabled {
    @synchronized (self) {
        if (_enabled == enabled) return;
        _enabled = enabled;
    }
    [SkipSilenceDefaults setEnabled:enabled];
    if (!enabled) {
        [self detachAll];
        // Restore user rate on all players we touched
        NSArray<AVPlayer *> *players;
        @synchronized (self) {
            players = [self->_activePlayers allObjects];
            [self->_activePlayers removeAllObjects];
        }
        float userRate = self.userPlaybackRate;
        for (AVPlayer *p in players) {
            @try { p.rate = userRate; } @catch (NSException *e) {}
        }
    }
}

- (void)setThresholdDBFS:(float)thresholdDBFS {
    _thresholdDBFS = thresholdDBFS;
    [SkipSilenceDefaults setThresholdDBFS:thresholdDBFS];
}
- (void)setSilenceRate:(float)silenceRate {
    _silenceRate = MAX(1.0f, MIN(4.0f, silenceRate));
    [SkipSilenceDefaults setSilenceRate:_silenceRate];
}
- (void)setHoldTime:(NSTimeInterval)holdTime {
    _holdTime = MAX(0.0, holdTime);
    [SkipSilenceDefaults setHoldTime:_holdTime];
}
- (void)setReleaseTime:(NSTimeInterval)releaseTime {
    _releaseTime = MAX(0.0, releaseTime);
    [SkipSilenceDefaults setReleaseTime:_releaseTime];
}

- (void)setUserPlaybackRate:(float)userPlaybackRate {
    if (userPlaybackRate <= 0.05f) return;
    @synchronized (self) {
        _userPlaybackRate = userPlaybackRate;
    }
}

#pragma mark – tap lifecycle

- (void)attachToPlayerItem:(AVPlayerItem *)item {
    if (item == nil) return;
    if (!self.enabled) return;

    dispatch_async(_queue, ^{
        @synchronized (self) {
            if ([self->_itemToTap objectForKey:item] != nil) return; // already attached
        }

        // Audio tracks may not be available immediately. Retry if needed.
        NSArray<AVAssetTrack *> *audioTracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
        if (audioTracks.count == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           self->_queue, ^{
                [self attachToPlayerItem:item];
            });
            return;
        }

        // Set up the pending context for the synchronous init callback.
        sPendingManager = self;
        sPendingItem    = item;

        MTAudioProcessingTapCallbacks callbacks = {0};
        callbacks.version    = kMTAudioProcessingTapCallbacksVersion_0;
        callbacks.init       = tapInitCallback;
        callbacks.finalize   = tapFinalizeCallback;
        callbacks.prepare    = tapPrepareCallback;
        callbacks.unprepare  = tapUnprepareCallback;
        callbacks.process    = tapProcessCallback;

        MTAudioProcessingTapRef tap = NULL;
        OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                     kMTAudioProcessingTapCreationFlag_PreEffects,
                                                     &tap);
        sPendingManager = nil;
        sPendingItem    = nil;

        if (status != noErr || tap == NULL) {
            return;
        }

        // Attach via AVAudioMix
        AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
        NSMutableArray *params = [NSMutableArray array];
        for (AVAssetTrack *t in audioTracks) {
            AVMutableAudioMixInputParameters *p =
                [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:t];
            p.audioTapProcessor = tap;
            [params addObject:p];
        }
        mix.inputParameters = params;
        item.audioMix = mix;

        @synchronized (self) {
            // Wrap the tap pointer in NSValue so NSMapTable can retain it.
            NSValue *tapVal = [NSValue valueWithPointer:tap];
            [self->_itemToTap setObject:tapVal forKey:item];
            NSMutableDictionary *st = [NSMutableDictionary dictionary];
            st[kStateBelowSinceKey]  = [NSNull null];
            st[kStateAboveSinceKey]  = [NSNull null];
            st[kStateCurrentRateKey] = @(1.0f);
            [self->_itemState setObject:st forKey:item];
        }
        // The tap is now retained by the audioMix; release our local ref.
        CFRelease(tap);
    });
}

- (void)detachFromPlayerItem:(AVPlayerItem *)item {
    if (item == nil) return;
    dispatch_async(_queue, ^{
        @synchronized (self) {
            if ([self->_itemToTap objectForKey:item] == nil) return;
            // Clearing the audioMix releases the tap.
            item.audioMix = nil;
            [self->_itemToTap removeObjectForKey:item];
            [self->_itemToPlayer removeObjectForKey:item];
            [self->_itemToSampleRate removeObjectForKey:item];
            [self->_itemState removeObjectForKey:item];
        }
        [self restoreUserRateForItem:item];
    });
}

- (void)detachAll {
    dispatch_async(_queue, ^{
        NSArray<AVPlayerItem *> *items;
        @synchronized (self) {
            items = [self->_itemToTap allKeys];
        }
        for (AVPlayerItem *it in items) {
            [self detachFromPlayerItem:it];
        }
    });
}

- (void)registerPlayer:(AVPlayer *)player forItem:(AVPlayerItem *)item {
    if (!player || !item) return;
    @synchronized (self) {
        [_itemToPlayer setObject:player forKey:item];
        [_activePlayers addObject:player];
    }
}

- (void)forgetPlayerForItem:(AVPlayerItem *)item {
    @synchronized (self) {
        [_itemToPlayer removeObjectForKey:item];
    }
}

- (void)restoreUserRateForItem:(AVPlayerItem *)item {
    AVPlayer *player;
    @synchronized (self) {
        player = [_itemToPlayer objectForKey:item];
    }
    if (player) {
        @try { player.rate = self.userPlaybackRate; } @catch (NSException *e) {}
    }
}

#pragma mark – detector state machine

- (void)feedSample:(float)dbfs
          duration:(NSTimeInterval)duration
           forItem:(AVPlayerItem *)item
{
    if (!self.enabled) return;

    NSMutableDictionary *st;
    @synchronized (self) {
        st = [_itemState objectForKey:item];
        if (!st) {
            st = [NSMutableDictionary dictionary];
            st[kStateBelowSinceKey] = [NSNull null];
            st[kStateAboveSinceKey] = [NSNull null];
            st[kStateCurrentRateKey] = @(1.0f);
            [_itemState setObject:st forKey:item];
        }
    }

    NSDate *now = [NSDate date];
    BOOL isSilent = (dbfs < self.thresholdDBFS);

    NSDate *belowSince = [st[kStateBelowSinceKey] isKindOfClass:[NSDate class]] ? st[kStateBelowSinceKey] : nil;
    NSDate *aboveSince = [st[kStateAboveSinceKey] isKindOfClass:[NSDate class]] ? st[kStateAboveSinceKey] : nil;

    if (isSilent) {
        if (!belowSince) {
            st[kStateBelowSinceKey] = now;
            st[kStateAboveSinceKey] = [NSNull null];
        }
    } else {
        if (!aboveSince) {
            st[kStateAboveSinceKey] = now;
            st[kStateBelowSinceKey] = [NSNull null];
        }
    }

    float currentRate = [st[kStateCurrentRateKey] floatValue];
    float targetRate  = currentRate;

    NSDate *belowNow = [st[kStateBelowSinceKey] isKindOfClass:[NSDate class]] ? st[kStateBelowSinceKey] : nil;
    NSDate *aboveNow = [st[kStateAboveSinceKey] isKindOfClass:[NSDate class]] ? st[kStateAboveSinceKey] : nil;

    if (belowNow) {
        NSTimeInterval silentFor = [now timeIntervalSinceDate:belowNow];
        if (silentFor >= self.holdTime && currentRate < self.silenceRate - 0.01f) {
            targetRate = self.silenceRate;
        }
    } else if (aboveNow) {
        NSTimeInterval loudFor = [now timeIntervalSinceDate:aboveNow];
        if (loudFor >= self.releaseTime && currentRate > self.userPlaybackRate + 0.01f) {
            targetRate = self.userPlaybackRate;
        }
    }

    if (fabsf(targetRate - currentRate) > 0.01f) {
        NSTimeInterval bufferDurationCopy = duration;
        float trCopy = targetRate;
        AVPlayerItem *itemCopy = item;
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (self) {
                [self applyRate:trCopy toItem:itemCopy];
            }
            if (trCopy > self.userPlaybackRate + 0.01f) {
                NSTimeInterval saved = (NSTimeInterval)(trCopy - self.userPlaybackRate)
                                       / (NSTimeInterval)trCopy
                                       * bufferDurationCopy;
                if (saved > 0) {
                    [SkipSilenceDefaults addSavedSeconds:saved];
                }
            }
        });
        st[kStateCurrentRateKey] = @(targetRate);
    }

    SkipSilenceState newState = (currentRate > self.userPlaybackRate + 0.01f)
                                ? SkipSilenceStateSilencing
                                : SkipSilenceStateInactive;
    if (newState != self.state) {
        [self willChangeValueForKey:@"state"];
        self.state = newState;
        [self didChangeValueForKey:@"state"];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"YTSkipSilenceStateChanged"
                          object:self
                        userInfo:@{ @"state": @(newState) }];
    }
}

- (void)applyRate:(float)rate toItem:(AVPlayerItem *)item {
    AVPlayer *player = [_itemToPlayer objectForKey:item];
    if (player) {
        @try { player.rate = rate; } @catch (NSException *e) {}
    }
}

@end
