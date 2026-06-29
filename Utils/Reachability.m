/*
 *  Reachability.m
 *  From Tony Million's reachability - trimmed for YTLiteSkipSilence.
 *  Public domain (https://github.com/tonymillion/Reachability).
 */

#import "Reachability.h"

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    Reachability *r = (__bridge Reachability *)info;
    if (r == nil) return;
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    if (reachable) {
        if (r.reachableBlock) r.reachableBlock(r);
    } else {
        if (r.unreachableBlock) r.unreachableBlock(r);
    }
}

@interface Reachability ()
@property (nonatomic, assign) SCNetworkReachabilityRef reachabilityRef;
@end

@implementation Reachability

- (void)dealloc {
    [self stopNotifier];
    if (_reachabilityRef) CFRelease(_reachabilityRef);
}

+ (instancetype)reachabilityWithHostname:(NSString *)hostname {
    Reachability *r = [[Reachability alloc] init];
    r.reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String]);
    return r;
}

+ (instancetype)reachabilityForInternetConnection {
    Reachability *r = [[Reachability alloc] init];
    struct sockaddr_in zeroAddr;
    bzero(&zeroAddr, sizeof(zeroAddr));
    zeroAddr.sin_len = sizeof(zeroAddr);
    zeroAddr.sin_family = AF_INET;
    r.reachabilityRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zeroAddr);
    return r;
}

- (BOOL)startNotifier {
    if (!self.reachabilityRef) return NO;
    SCNetworkReachabilityContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
    if (SCNetworkReachabilitySetCallback(self.reachabilityRef, ReachabilityCallback, &ctx)) {
        if (SCNetworkReachabilityScheduleWithRunLoop(self.reachabilityRef, CFRunLoopGetMain(), kCFRunLoopDefaultMode)) {
            return YES;
        }
    }
    return NO;
}

- (void)stopNotifier {
    if (self.reachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(self.reachabilityRef, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    }
}

- (BOOL)reachable {
    SCNetworkReachabilityFlags f = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &f)) return NO;
    return (f & kSCNetworkReachabilityFlagsReachable) != 0;
}

- (SCNetworkReachabilityFlags)flags {
    SCNetworkReachabilityFlags f = 0;
    SCNetworkReachabilityGetFlags(self.reachabilityRef, &f);
    return f;
}

@end
