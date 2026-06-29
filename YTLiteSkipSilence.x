//
//  YTLiteSkipSilence.x
//  Main tweak file: hooks YouTube's player to install the Skip Silence
//  audio tap, and registers a clean YTVideoOverlay toggle button.
//
//  Architecture
//  ============
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  %ctor                                                          │
//  │   ├─ dlopen YTVideoOverlay.dylib                                │
//  │   ├─ initYTVideoOverlay(SkipSilenceKey, {…})                    │
//  │   ├─ %init(Top), %init(Bottom)                                  │
//  │   └─ sync tunables from defaults → SkipSilenceManager           │
//  │                                                                  │
//  │  AVPlayer hooks (Layer A — capture player→item association)     │
//  │   ├─ -[AVPlayer replaceCurrentItemWithPlayerItem:]               │
//  │   ├─ -[AVPlayer setRate:]   (captures YouTube-initiated rate)    │
//  │   └─ -[AVPlayerItem initWithAsset:]  (tap attach point)          │
//  │                                                                  │
//  │  YouTube hooks (Layer B — capture user-chosen normal rate)      │
//  │   ├─ -[YTPlayerViewController setPlaybackRate:]                  │
//  │   ├─ -[YTMainAppVideoPlayerOverlayViewController setPlaybackRate:]│
//  │   └─ -[YTPlayerViewController loadWithPlayerTransition:…]        │
//  │       → on video change, attach tap to new item                  │
//  │                                                                  │
//  │  YTVideoOverlay button hooks                                     │
//  │   ├─ YTMainAppControlsOverlayView     (top row, optional)        │
//  │   └─ YTInlinePlayerBarContainerView   (bottom row, default)      │
//  │       ├─ -buttonImage:               → on/off icon               │
//  │       └─ -didPressSkipSilence:       → toggle + icon swap        │
//  └──────────────────────────────────────────────────────────────────┘
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "SkipSilenceManager.h"
#import "SkipSilenceDefaults.h"
#import "NSBundle+YTSkipSilence.h"

// ---- YTVideoOverlay headers (vendored at build time) -----------------------
//
// We import these via the THEOS include path. If YTVideoOverlay's source is
// checked out as a sibling directory (the standard YTLite pattern), the
// Makefile's -I already adds ../YTVideoOverlay.  These two files declare the
// metadata keys and the initYTVideoOverlay() helper we need.
//
#ifdef __has_include
#if __has_include("YTVideoOverlay/Header.h")
#import "YTVideoOverlay/Header.h"
#elif __has_include(<YTVideoOverlay/Header.h>)
#import <YTVideoOverlay/Header.h>
#endif
#if __has_include("YTVideoOverlay/Init.x")
#import "YTVideoOverlay/Init.x"
#elif __has_include(<YTVideoOverlay/Init.x>)
#import <YTVideoOverlay/Init.x>
#endif
#endif

// ---- YouTube headers (vendored at build time via PoomSmart/YouTubeHeader) --
// We only need a handful of class names; declare forward @interfaces so the
// Logos hooks type-check without requiring the full header bag.
@class YTPlayerViewController, YTMainAppVideoPlayerOverlayViewController;
@class YTMainAppControlsOverlayView, YTInlinePlayerBarContainerView;
@class YTQTMButton;

@interface YTPlayerViewController : UIViewController
- (void)loadWithPlayerTransition:(id)arg playbackConfig:(id)cfg;
- (void)setPlaybackRate:(CGFloat)rate;
@property (nonatomic, readonly) NSString *contentVideoID;
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (void)setPlaybackRate:(CGFloat)rate;
- (CGFloat)currentPlaybackRate;
@end

@interface YTMainAppControlsOverlayView : UIView
@property (nonatomic, readonly) NSMutableDictionary *overlayButtons;
- (UIImage *)buttonImage:(NSString *)tweakId;
@end

@interface YTInlinePlayerBarContainerView : UIView
@property (nonatomic, readonly) NSMutableDictionary *overlayButtons;
- (UIImage *)buttonImage:(NSString *)tweakId;
@end

// =============================================================================
#pragma mark – Constants
// =============================================================================

#define kSkipSilenceTweakKey @"SkipSilence"

// =============================================================================
#pragma mark – Image helpers
// =============================================================================

// Build a clean icon at runtime. Prefer the bundled PNG assets (predictable
// rendering across iOS versions); fall back to SF Symbols if missing; final
// fallback is a simple drawn circle so we never show a blank button.
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

    // Always template so YouTube can tint appropriately.
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// =============================================================================
#pragma mark – Top-row overlay button (YTMainAppControlsOverlayView)
// =============================================================================
//
// Optional – only used if the user picks "Top" position in YTVideoOverlay
// settings (key: YTVideoOverlay-SkipSilence-Position == 0).
//

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

    // Swap icon on this button instance
    YTQTMButton *btn = self.overlayButtons[kSkipSilenceTweakKey];
    if ([btn respondsToSelector:@selector(setImage:forState:)]) {
        [btn setImage:YTSkipSilenceIcon(newState) forState:UIControlStateNormal];
    }
}

%end // %hook YTMainAppControlsOverlayView

%end // %group Top

// =============================================================================
#pragma mark – Bottom-row overlay button (YTInlinePlayerBarContainerView)
// =============================================================================
//
// Default – sits next to the fullscreen button, exactly where YouQuality /
// YouPiP put their buttons.
//

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

    YTQTMButton *btn = self.overlayButtons[kSkipSilenceTweakKey];
    if ([btn respondsToSelector:@selector(setImage:forState:)]) {
        [btn setImage:YTSkipSilenceIcon(newState) forState:UIControlStateNormal];
    }

    // Haptic feedback – subtle, like YouTube's own buttons
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [g impactOccurred];
    }
}

%end // %hook YTInlinePlayerBarContainerView

%end // %group Bottom

// =============================================================================
#pragma mark – AVPlayer / AVPlayerItem hooks (tap install site)
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
    // Detach our tap before YouTube tears down the item.
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
    // Forget the previous item's player mapping
    AVPlayerItem *old = self.currentItem;
    if (old && old != item) {
        [[SkipSilenceManager shared] forgetPlayerForItem:old];
    }
}

- (void)setRate:(float)rate {
    // Capture YouTube's intended rate when it's the user-initiated one.
    // We distinguish YouTube's own rate set from our silence-rate set by
    // checking whether we're currently in the silencing state.
    SkipSilenceManager *mgr = [SkipSilenceManager shared];
    if (mgr.state == SkipSilenceStateInactive) {
        // This is a user / YouTube-initiated rate change; remember it as
        // the "normal" rate we should restore to after silence.
        mgr.userPlaybackRate = rate;
    }
    %orig;
}

%end

// =============================================================================
#pragma mark – YouTube player hooks
// =============================================================================

%hook YTPlayerViewController

- (void)loadWithPlayerTransition:(id)transition playbackConfig:(id)cfg {
    %orig;
    // A new video loaded. Defer tap attach until the AVPlayerItem appears
    // (the AVPlayerItem hook will catch it; we just synchronise tunables).
    SkipSilenceManager *mgr = [SkipSilenceManager shared];
    mgr.thresholdDBFS = [SkipSilenceDefaults thresholdDBFS];
    mgr.silenceRate   = [SkipSilenceDefaults silenceRate];
    mgr.holdTime      = [SkipSilenceDefaults holdTime];
    mgr.releaseTime   = [SkipSilenceDefaults releaseTime];
    mgr.enabled       = [SkipSilenceDefaults enabled];
}

- (void)setPlaybackRate:(CGFloat)rate {
    %orig;
    // YouTube's user-facing rate control. Capture as the "normal" rate so
    // we can restore to it when silence ends.
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
#pragma mark – Tweak entry point
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

        // ---- Register with YTVideoOverlay -----------------------------------
        // Try both the embedded (sideloaded) and jailbroken dylib paths.
        NSString *embedded =
            [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/YTVideoOverlay.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:embedded]) {
            dlopen(embedded.UTF8String, RTLD_LAZY);
        }
        // Rootless + classic jailbreak
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

        // Call +[YTSettingsSectionItemManager registerTweak:metadata:] if present.
        Class mgrCls = NSClassFromString(@"YTSettingsSectionItemManager");
        if (mgrCls && [mgrCls respondsToSelector:@selector(registerTweak:metadata:)]) {
            // Use the Init.x helper if available; otherwise fall through to a manual call.
            NSDictionary *metadata = @{
                @"accessibilityLabel": @"Skip Silence",
                @"selector":           @"didPressSkipSilence:",
                @"updateImageOnVisible": @YES,
                // ToggleKey: NO – let YTVideoOverlay render its own on/off
                // switch in its settings section; we still own the actual
                // state via SkipSilenceDefaults.
                @"extraBooleanKeys":   @[
                    kSkipSilenceEnabledKey,
                    kSkipSilenceShowSavedTimeKey
                ],
            };
            [mgrCls performSelector:@selector(registerTweak:metadata:)
                         withObject:kSkipSilenceTweakKey
                         withObject:metadata];
        }

        // ---- Initialise Logos groups ---------------------------------------
        // %init() with no args initialises the default group (the AVPlayerItem,
        // AVPlayer, YTPlayerViewController, YTMainAppVideoPlayerOverlayViewController
        // hooks below — they're not wrapped in %group).
        %init();
        %init(Top);
        %init(Bottom);

        NSLog(@"[YTLiteSkipSilence] Loaded. enabled=%d threshold=%.1f dBFS rate=%.2fx",
              [SkipSilenceDefaults enabled],
              [SkipSilenceDefaults thresholdDBFS],
              [SkipSilenceDefaults silenceRate]);
    }
}
