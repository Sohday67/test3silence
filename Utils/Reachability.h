/*
 *  Reachability.h
 *  From Tony Million's reachability - trimmed for YTLiteSkipSilence.
 *  Public domain (https://github.com/tonymillion/Reachability).
 */

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

@class Reachability;

typedef void (^NetworkReachable)(Reachability *r);
typedef void (^NetworkUnreachable)(Reachability *r);

@interface Reachability : NSObject

@property (nonatomic, copy) NetworkReachable reachableBlock;
@property (nonatomic, copy) NetworkUnreachable unreachableBlock;

+ (instancetype)reachabilityWithHostname:(NSString *)hostname;
+ (instancetype)reachabilityForInternetConnection;

@property (nonatomic, readonly) BOOL reachable;
@property (nonatomic, readonly) SCNetworkReachabilityFlags flags;

- (BOOL)startNotifier;
- (void)stopNotifier;

@end
