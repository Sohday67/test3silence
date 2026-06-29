//
//  SkipSilenceDefaults.h
//  YTLiteSkipSilence
//
//  Thin wrapper around NSUserDefaults with the suite name "com.dvntm.ytlite.skipsilence".
//  Mirrors the pattern YTLite uses (YTLUserDefaults / ytlBool / ytlSetBool).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define kSkipSilenceDefaultsSuite @"com.dvntm.ytlite.skipsilence"

// Setting keys (also used by YTVideoOverlay ExtraBooleanKeys & Settings.x rows)
extern NSString * const kSkipSilenceEnabledKey;       // BOOL master toggle
extern NSString * const kSkipSilenceThresholdKey;     // float, dBFS, default -35
extern NSString * const kSkipSilenceRateKey;          // float, default 2.5
extern NSString * const kSkipSilenceHoldTimeKey;      // float seconds, default 0.15
extern NSString * const kSkipSilenceReleaseTimeKey;   // float seconds, default 0.04
extern NSString * const kSkipSilencePositionKey;      // int 0=top, 1=bottom (YTVideoOverlay)
extern NSString * const kSkipSilenceShowSavedTimeKey; // BOOL - show "Xs saved" toast

@interface SkipSilenceDefaults : NSObject

+ (NSUserDefaults *)standardDefaults;

// Typed accessors
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;

+ (float)thresholdDBFS;
+ (void)setThresholdDBFS:(float)v;

+ (float)silenceRate;
+ (void)setSilenceRate:(float)v;

+ (float)holdTime;
+ (void)setHoldTime:(float)v;

+ (float)releaseTime;
+ (void)setReleaseTime:(float)v;

+ (NSInteger)position;       // 0 = top, 1 = bottom
+ (void)setPosition:(NSInteger)p;

+ (BOOL)showSavedTime;
+ (void)setShowSavedTime:(BOOL)b;

// Cumulative seconds of audio skipped (persisted across launches)
+ (NSTimeInterval)totalSavedSeconds;
+ (void)addSavedSeconds:(NSTimeInterval)delta;
+ (void)resetSavedSeconds;

@end

NS_ASSUME_NONNULL_END
