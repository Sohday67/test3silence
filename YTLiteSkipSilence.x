//
//  YTLiteSkipSilence.x
//  Main tweak file: hooks YouTube's player to install the Skip Silence
//  audio tap, and registers a clean YTVideoOverlay toggle button.
//
//  Build-time dependencies:
//    - Theos + iPhoneOS16.5.sdk
//    - Vendor headers (PoomSmart/YouTubeHeader, PSHeader) - OPTIONAL.
//      The tweak uses runtime discovery so it builds even without them.
//
//  Runtime dependencies:
//    - com.ps.ytvideooverlay (for the toggle button)
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "SkipSilenceManager.h"
#import "SkipSilenceDefaults.h"
#import "NSBundle+YTSkipSilence.h"

// =============================================================================
#pragma mark - Constants
// =============================================================================

#define kSkipSilenceTweakKey @"SkipSilence"

// YTVideoOverlay metadata keys (mirror of PoomSmart/YTVideoOverlay/Init.h)
#define kYTVO_AccessibilityLabelKey    @"accessibilityLabel"
#define kYTVO_ToggleKey                @"toggle"
#define kYTVO_AsTextKey                @"asText"
#define kYTVO_SelectorKey              @"selector"
#define kYTVO_UpdateImageOnVisibleKey  @"updateImageOnVisible"
#define kYTVO_ExtraBooleanKeys         @"extraBooleanKeys"

// =============================================================================
#pragma mark - YTVideoOverlay registration helper (inlined)
// =============================================================================

// Equivalent to PoomSmart/YTVideoOverlay/Init.x's initYTVideoOverlay().
// We inline it so we don't need YTVideoOverlay's source at build time.
static void YTSInitVideoOverlay(NSString *tweakKey, NSDictionary *metadata) {
    // Try embedded (sideloaded) path first
    NSString *embedded =
        [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/YTVideoOverlay.dylib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:embedded]) {
        dlopen(embedded.UTF8String, RTLD_LAZY);
    }
    // Then jailbroken paths (rootless + classic)
    NSArray *jbPaths = @[
        @"/var/jb/usr/lib/TweakInject/YTVideoOverlay.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/YTVideoOverlay.dylib",
        @"/usr/lib/TweakInject/YTVideoOverlay.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/YTVideoOverlay.dylib",
    ];
    for (NSString *p in jbPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            dlopen(p.UTF8String, RTLD_LAZY);
            break;
        }
    }
    // Register our tweak with YTVideoOverlay via runtime discovery
    Class mgrCls = NSClassFromString(@"YTSettingsSectionItemManager");
    if (mgrCls == nil) return;

    SEL regSel = NSSelectorFromString(@"registerTweak:metadata:");
    if (![mgrCls respondsToSelector:regSel]) return;

    NSMethodSignature *sig = [mgrCls methodSignatureForSelector:regSel];
    if (sig == nil) return;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:mgrCls];
    [inv setSelector:regSel];
    [inv setArgument:&tweakKey  atIndex:2];
    [inv setArgument:&metadata  atIndex:3];
    [inv invoke];
}

// =============================================================================
#pragma mark - Image helpers
// =============================================================================

// Build a clean icon at runtime. Prefer bundled PNGs (predictable rendering
// across iOS versions); fall back to SF Symbols if missing; final fallback
// is a simple drawn circle so we never show a blank button.
static UIImage *YTSkipSilenceIcon(BOOL active) {
    UIImage *img = nil;

    // 1) Prefer bundled PNGs (shipped in YTLiteSkipSilence.bundle)
    @try {
        NSBundle *b = [NSBundle yts_defaultBundle];
        if (b) {
            NSString *n = active ? @"skipsilence_on" : @"skipsilence_off";
            NSString *p = [b pathForResource:n ofType:@"png"];
            if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                img = [UIImage imageWithContentsOfFile:p];
            }
        }
    } @catch (NSException *e) {}

    // 2) SF Symbols (iOS 13+)
    if (img == nil) {
        NSString *name = active ? @"speaker.wave.3.fill" : @"speaker.slash.fill";
        img = [UIImage systemImageNamed:name];
    }

    // 3) Last-resort procedural icon
    if (img == nil) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(28, 28), NO, 0);
        [[UIColor whiteColor] setFill];
        UIBezierPath *bp = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2, 2, 24, 24)];
        [bp fill];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// =============================================================================
#pragma mark - Runtime helper to access YTVideoOverlay's overlayButtons dict
// =============================================================================

// YTVideoOverlay attaches an NSMutableDictionary to each overlay view via
// associated objects, keyed by the property name "overlayButtons". We use
// objc_getAssociatedObject to read it back without needing the YTVideoOverlay
// header at compile time.
static UIButton *YTSGetOverlayButton(id overlayView) {
    if (overlayView == nil) return nil;
    id dict = objc_getAssociatedObject(overlayView, "overlayButtons");
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    id btn = dict[kSkipSilenceTweakKey];
    if ([btn isKindOfClass:[UIButton class]]) return btn;
    return nil;
}

// =============================================================================
#pragma mark - Top-row overlay button (YTMainAppControlsOverlayView)
// =============================================================================

%group Top

%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {
    if ([tweakId isEqualToString:kSkipSilenceTweakKey]) {
        return YTSkipSilenceIcon([SkipSilenceDefaults enabled]);
    }
    return %orig;
}

%new(v@:@)
- (void)didPressSkipSilence:(id)arg {
    BOOL newState = ![SkipSilenceDefaults enabled];
    [SkipSilenceDefaults setEnabled:newState];
    [SkipSilenceManager shared].enabled = newState;

    UIButton *btn = YTSGetOverlayButton(self);
    if ([btn respondsToSelector:@selector(setImage:forState:)]) {
        [btn setImage:YTSkipSilenceIcon(newState) forState:UIControlStateNormal];
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [g impactOccurred];
    }
}

%end

%end // %group Top

// =============================================================================
#pragma mark - Bottom-row overlay button (YTInlinePlayerBarContainerView)
// =============================================================================

%group Bottom

%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {
    if ([tweakId isEqualToString:kSkipSilenceTweakKey]) {
        return YTSkipSilenceIcon([SkipSilenceDefaults enabled]);
    }
    return %orig;
}

%new(v@:@)
- (void)didPressSkipSilence:(id)arg {
    BOOL newState = ![SkipSilenceDefaults enabled];
    [SkipSilenceDefaults setEnabled:newState];
    [SkipSilenceManager shared].enabled = newState;

    UIButton *btn = YTSGetOverlayButton(self);
    if ([btn respondsToSelector:@selector(setImage:forState:)]) {
        [btn setImage:YTSkipSilenceIcon(newState) forState:UIControlStateNormal];
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [g impactOccurred];
    }
}

%end

%end // %group Bottom

// =============================================================================
#pragma mark - AVPlayer / AVPlayerItem hooks (tap install site)
// =============================================================================

%hook AVPlayerItem

- (instancetype)initWithAsset:(AVAsset *)asset {
    AVPlayerItem *item = %orig;
    if (item && [SkipSilenceDefaults enabled]) {
        [[SkipSilenceManager shared] attachToPlayerItem:item];
    }
    return item;
}

- (instancetype)initWithAsset:(AVAsset *)asset
automaticallyLoadedAssetKeys:(NSArray<NSString *> *)automaticallyLoadedAssetKeys {
    AVPlayerItem *item = %orig;
    if (item && [SkipSilenceDefaults enabled]) {
        [[SkipSilenceManager shared] attachToPlayerItem:item];
    }
    return item;
}

- (void)dealloc {
    @try {
        [[SkipSilenceManager shared] detachFromPlayerItem:self];
    } @catch (NSException *e) {}
    %orig;
}

%end

%hook AVPlayer

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item && [SkipSilenceDefaults enabled]) {
        [[SkipSilenceManager shared] registerPlayer:self forItem:item];
        [[SkipSilenceManager shared] attachToPlayerItem:item];
    }
    AVPlayerItem *old = self.currentItem;
    if (old && old != item) {
        [[SkipSilenceManager shared] forgetPlayerForItem:old];
    }
}

- (void)setRate:(float)rate {
    SkipSilenceManager *mgr = [SkipSilenceManager shared];
    if (mgr.state == SkipSilenceStateInactive) {
        mgr.userPlaybackRate = rate;
    }
    %orig;
}

%end

// =============================================================================
#pragma mark - YouTube player hooks
// =============================================================================

%hook YTPlayerViewController

- (void)loadWithPlayerTransition:(id)transition playbackConfig:(id)cfg {
    %orig;
    SkipSilenceManager *mgr = [SkipSilenceManager shared];
    mgr.thresholdDBFS = [SkipSilenceDefaults thresholdDBFS];
    mgr.silenceRate   = [SkipSilenceDefaults silenceRate];
    mgr.holdTime      = [SkipSilenceDefaults holdTime];
    mgr.releaseTime   = [SkipSilenceDefaults releaseTime];
    mgr.enabled       = [SkipSilenceDefaults enabled];
}

- (void)setPlaybackRate:(CGFloat)rate {
    %orig;
    [SkipSilenceManager shared].userPlaybackRate = (float)rate;
}

%end

%hook YTMainAppVideoPlayerOverlayViewController

- (void)setPlaybackRate:(CGFloat)rate {
    %orig;
    [SkipSilenceManager shared].userPlaybackRate = (float)rate;
}

%end

// =============================================================================
#pragma mark - Tweak entry point
// =============================================================================

%ctor {
    @autoreleasepool {
        // Load tunables into the singleton up-front
        SkipSilenceManager *mgr = [SkipSilenceManager shared];
        mgr.enabled       = [SkipSilenceDefaults enabled];
        mgr.thresholdDBFS = [SkipSilenceDefaults thresholdDBFS];
        mgr.silenceRate   = [SkipSilenceDefaults silenceRate];
        mgr.holdTime      = [SkipSilenceDefaults holdTime];
        mgr.releaseTime   = [SkipSilenceDefaults releaseTime];

        // Register with YTVideoOverlay (inlined, runtime discovery)
        NSDictionary *metadata = @{
            kYTVO_AccessibilityLabelKey:   @"Skip Silence",
            kYTVO_SelectorKey:             @"didPressSkipSilence:",
            kYTVO_UpdateImageOnVisibleKey: @YES,
            kYTVO_ExtraBooleanKeys: @[
                kSkipSilenceEnabledKey,
                kSkipSilenceShowSavedTimeKey
            ],
        };
        YTSInitVideoOverlay(kSkipSilenceTweakKey, metadata);

        // Initialise all Logos groups
        %init();
        %init(Top);
        %init(Bottom);

        NSLog(@"[YTLiteSkipSilence] Loaded. enabled=%d threshold=%.1f dBFS rate=%.2fx",
              [SkipSilenceDefaults enabled],
              [SkipSilenceDefaults thresholdDBFS],
              [SkipSilenceDefaults silenceRate]);
    }
}
