//
//  NSBundle+YTSkipSilence.h
//  YTLiteSkipSilence
//
//  Resolves the YTLiteSkipSilence.bundle regardless of install layout
//  (jailbroken / rootless / roothide / sideloaded-embedded).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBundle (YTSkipSilence)
@property (class, nonatomic, readonly) NSBundle *yts_defaultBundle;
@end

NS_ASSUME_NONNULL_END
