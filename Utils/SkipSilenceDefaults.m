//
//  SkipSilenceDefaults.m
//  YTLiteSkipSilence
//

#import "SkipSilenceDefaults.h"

NSString * const kSkipSilenceEnabledKey       = @"skipSilenceEnabled";
NSString * const kSkipSilenceThresholdKey     = @"skipSilenceThresholdDBFS";
NSString * const kSkipSilenceRateKey          = @"skipSilenceSilenceRate";
NSString * const kSkipSilenceHoldTimeKey      = @"skipSilenceHoldTime";
NSString * const kSkipSilenceReleaseTimeKey   = @"skipSilenceReleaseTime";
NSString * const kSkipSilencePositionKey      = @"skipSilencePosition";
NSString * const kSkipSilenceShowSavedTimeKey = @"skipSilenceShowSavedTime";
static NSString * const kSkipSilenceTotalSavedKey = @"skipSilenceTotalSavedSeconds";

@implementation SkipSilenceDefaults

+ (NSUserDefaults *)standardDefaults {
    static NSUserDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:kSkipSilenceDefaultsSuite];
        NSDictionary *seed = @{
            kSkipSilenceEnabledKey:       @NO,
            kSkipSilenceThresholdKey:     @(-35.0f),
            kSkipSilenceRateKey:          @2.5f,
            kSkipSilenceHoldTimeKey:      @0.15f,
            kSkipSilenceReleaseTimeKey:   @0.04f,
            kSkipSilencePositionKey:      @1,
            kSkipSilenceShowSavedTimeKey: @YES,
            kSkipSilenceTotalSavedKey:    @0.0
        };
        [defaults registerDefaults:seed];
    });
    return defaults;
}

+ (BOOL)enabled                  { return [[self standardDefaults] boolForKey:kSkipSilenceEnabledKey]; }
+ (void)setEnabled:(BOOL)v       { [[self standardDefaults] setBool:v forKey:kSkipSilenceEnabledKey]; }

+ (float)thresholdDBFS           { return [[self standardDefaults] floatForKey:kSkipSilenceThresholdKey]; }
+ (void)setThresholdDBFS:(float)v{ [[self standardDefaults] setFloat:v forKey:kSkipSilenceThresholdKey]; }

+ (float)silenceRate             { return [[self standardDefaults] floatForKey:kSkipSilenceRateKey]; }
+ (void)setSilenceRate:(float)v  { [[self standardDefaults] setFloat:v forKey:kSkipSilenceRateKey]; }

+ (float)holdTime                { return [[self standardDefaults] floatForKey:kSkipSilenceHoldTimeKey]; }
+ (void)setHoldTime:(float)v     { [[self standardDefaults] setFloat:v forKey:kSkipSilenceHoldTimeKey]; }

+ (float)releaseTime             { return [[self standardDefaults] floatForKey:kSkipSilenceReleaseTimeKey]; }
+ (void)setReleaseTime:(float)v  { [[self standardDefaults] setFloat:v forKey:kSkipSilenceReleaseTimeKey]; }

+ (NSInteger)position            { return [[self standardDefaults] integerForKey:kSkipSilencePositionKey]; }
+ (void)setPosition:(NSInteger)p { [[self standardDefaults] setInteger:p forKey:kSkipSilencePositionKey]; }

+ (BOOL)showSavedTime            { return [[self standardDefaults] boolForKey:kSkipSilenceShowSavedTimeKey]; }
+ (void)setShowSavedTime:(BOOL)b { [[self standardDefaults] setBool:b forKey:kSkipSilenceShowSavedTimeKey]; }

+ (NSTimeInterval)totalSavedSeconds {
    return [[self standardDefaults] doubleForKey:kSkipSilenceTotalSavedKey];
}
+ (void)addSavedSeconds:(NSTimeInterval)delta {
    double v = [self totalSavedSeconds] + delta;
    if (v < 0) v = 0;
    [[self standardDefaults] setDouble:v forKey:kSkipSilenceTotalSavedKey];
}
+ (void)resetSavedSeconds {
    [[self standardDefaults] setDouble:0.0 forKey:kSkipSilenceTotalSavedKey];
}

@end
