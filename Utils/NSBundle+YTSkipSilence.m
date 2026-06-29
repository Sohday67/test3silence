//
//  NSBundle+YTSkipSilence.m
//  YTLiteSkipSilence
//

#import "NSBundle+YTSkipSilence.h"

// Optional rootless / roothide support
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
        NSString *path = nil;

#ifdef HAVE_ROOTHIDE
        // rootless / roothide: /var/jb/Library/Application Support/...
        path = [NSString stringWithUTF8String:jbroot("/Library/Application Support/YTLiteSkipSilence.bundle")];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            bundle = [NSBundle bundleWithPath:path];
            return;
        }
#endif

        // rootless jailbreaks (palera1n / Dopamine / ElleKit)
        NSArray *rootlessPaths = @[
            @"/var/jb/Library/Application Support/YTLiteSkipSilence.bundle",
            @"/var/jb/Library/Application Support/YTLiteSkipSilence.bundle",
        ];
        for (NSString *p in rootlessPaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                bundle = [NSBundle bundleWithPath:p];
                if (bundle) return;
            }
        }

        // Classic jailbreak layout
        NSString *classic = @"/Library/Application Support/YTLiteSkipSilence.bundle";
        if ([[NSFileManager defaultManager] fileExistsAtPath:classic]) {
            bundle = [NSBundle bundleWithPath:classic];
            if (bundle) return;
        }

        // Sideloaded / embedded (TrollStore, AltStore, etc.)
        NSString *embedded = [[NSBundle mainBundle] pathForResource:@"YTLiteSkipSilence" ofType:@"bundle"];
        if (embedded && [[NSFileManager defaultManager] fileExistsAtPath:embedded]) {
            bundle = [NSBundle bundleWithPath:embedded];
            if (bundle) return;
        }

        // Final fallback: main bundle (symbols may be missing but app won't crash)
        bundle = [NSBundle mainBundle];
    });
    return bundle;
}

@end
