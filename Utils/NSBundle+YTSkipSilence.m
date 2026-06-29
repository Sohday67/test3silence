//
//  NSBundle+YTSkipSilence.m
//  YTLiteSkipSilence
//

#import "NSBundle+YTSkipSilence.h"

#ifdef __has_include
#if __has_include(<roothide.h>)
#import <roothide.h>
#define HAVE_ROOTHIDE 1
#endif
#endif

@implementation NSBundle (YTSkipSilence)

+ (NSBundle *)yts_defaultBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *candidates = @[
            @"/var/jb/Library/Application Support/YTLiteSkipSilence.bundle",
            @"/Library/Application Support/YTLiteSkipSilence.bundle",
            [[NSBundle mainBundle] pathForResource:@"YTLiteSkipSilence" ofType:@"bundle"],
        ];
        for (NSString *p in candidates) {
            if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                bundle = [NSBundle bundleWithPath:p];
                if (bundle) return;
            }
        }
        bundle = [NSBundle mainBundle];
    });
    return bundle;
}

@end
