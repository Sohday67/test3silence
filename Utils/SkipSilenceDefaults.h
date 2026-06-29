//
//  SkipSilenceDefaults.h
//  YTLiteSkipSilence
//
//  Thin wrapper around NSUserDefaults with the suite name
//  "com.dvntm.ytlite.skipsilence".
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define kSkipSilenceDefaultsSuite @"com.dvntm.ytlite.skipsilence"

// Setting keys (also used by YTVideoOverlay ExtraBooleanKeys & Settings.x rows)
extern NSString * const kSkipSilenceEnabledKey;
extern NSString * const kSkipSilenceThresholdKey;
extern NSString * const kSkipSilenceRateKey;
extern NSString * const kSkipSilenceHoldTimeKey;
extern NSString * const kSkipSilenceReleaseTimeKey;
extern NSString * const kSkipSilencePositionKey;
extern NSString * const kSkipSilenceShowSavedTimeKey;

@interface SkipSilenceDefaults : NSObject

+ (NSUserDefaults *)standardDefaults;

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

+ (NSTimeInterval)totalSavedSeconds;
+ (void)addSavedSeconds:(NSTimeInterval)delta;
+ (void)resetSavedSeconds;

@end

NS_ASSUME_NONNULL_END
