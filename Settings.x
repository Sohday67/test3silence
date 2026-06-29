//
//  Settings.x
//  Injects a "Skip Silence" section into YouTube's in-app Settings.
//
//  This complements (does not replace) the YTVideoOverlay toggle button.
//  We use only runtime discovery so we don't depend on YouTube version
//  specifics at compile time.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "SkipSilenceDefaults.h"
#import "SkipSilenceManager.h"
#import "NSBundle+YTSkipSilence.h"

#define kSkipSilenceSettingsSection 790

// =============================================================================
#pragma mark - Switch item builder
// =============================================================================

// Build a YTSettingsSectionItem switch row using the most common constructor.
// Falls back gracefully if the constructor signature differs.
static id YTSwitchItem(Class cls, NSString *title, NSString *key) {
    if (!cls) return nil;

    // Try: +switchWithTitle:switchKey:on:action:
    SEL sel = NSSelectorFromString(@"switchWithTitle:switchKey:on:action:");
    if ([cls respondsToSelector:sel]) {
        NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:cls];
            [inv setSelector:sel];
            BOOL on = [[SkipSilenceDefaults standardDefaults] boolForKey:key];
            id action = (id)NULL;
            [inv setArgument:&title atIndex:2];
            [inv setArgument:&key   atIndex:3];
            [inv setArgument:&on    atIndex:4];
            [inv setArgument:&action atIndex:5];
            [inv invoke];
            __unsafe_unretained id result = nil;
            [inv getReturnValue:&result];
            return result;
        }
    }

    // Fallback: bare instance + KVC
    id item = [cls new];
    @try { [item setValue:title forKey:@"title"]; } @catch (__unused NSException *e) {}
    @try { [item setValue:key   forKey:@"key"]; }   @catch (__unused NSException *e) {}
    return item;
}

// Build a simple title-only item.
static id YTTitleItem(Class cls, NSString *title) {
    if (!cls) return nil;
    SEL simple = NSSelectorFromString(@"itemWithTitle:");
    if ([cls respondsToSelector:simple]) {
        return [cls performSelector:simple withObject:title];
    }
    id item = [cls new];
    @try { [item setValue:title forKey:@"title"]; } @catch (__unused NSException *e) {}
    return item;
}

// =============================================================================
#pragma mark - Settings injection hooks
// =============================================================================

%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
    NSArray *orig = %orig;
    if (orig == nil) orig = @[];
    if ([orig containsObject:@(kSkipSilenceSettingsSection)]) return orig;
    NSMutableArray *m = [orig mutableCopy];
    NSUInteger insertIdx = MIN(1u, (unsigned)m.count);
    [m insertObject:@(kSkipSilenceSettingsSection) atIndex:insertIdx];
    return [m copy];
}
%end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateSkipSilenceSectionWithEntry:(id)entry {
    NSMutableArray *rows = [NSMutableArray array];
    Class itemCls = NSClassFromString(@"YTSettingsSectionItem");
    if (!itemCls) return;

    // Master toggle
    id enableItem = YTSwitchItem(itemCls, @"Skip Silence", kSkipSilenceEnabledKey);
    if (enableItem) [rows addObject:enableItem];

    // Show toast toggle
    id toastItem = YTSwitchItem(itemCls, @"Show Time-Saved Toast", kSkipSilenceShowSavedTimeKey);
    if (toastItem) [rows addObject:toastItem];

    // Stats readout
    NSTimeInterval saved = [SkipSilenceDefaults totalSavedSeconds];
    NSString *savedStr = [NSString stringWithFormat:@"%.1f seconds saved so far", saved];
    id stat = YTTitleItem(itemCls, savedStr);
    if (stat) [rows addObject:stat];

    // Threshold & speed presets - rendered as title items so the user can see
    // current values; full picker UI requires the YouTube picker constructor
    // which varies between versions.
    float curThresh = [SkipSilenceDefaults thresholdDBFS];
    NSString *threshStr = [NSString stringWithFormat:@"Silence Threshold: %.0f dBFS", curThresh];
    id threshItem = YTTitleItem(itemCls, threshStr);
    if (threshItem) [rows addObject:threshItem];

    float curSpeed = [SkipSilenceDefaults silenceRate];
    NSString *speedStr = [NSString stringWithFormat:@"Silence Speed: %.1fx", curSpeed];
    id speedItem = YTTitleItem(itemCls, speedStr);
    if (speedItem) [rows addObject:speedItem];

    NSString *helpStr = @"Tip: adjust threshold/speed via YTVideoOverlay settings or NSUserDefaults suite com.dvntm.ytlite.skipsilence";
    id helpItem = YTTitleItem(itemCls, helpStr);
    if (helpItem) [rows addObject:helpItem];

    // Hand rows to YouTube's container
    id sectionItems = [entry valueForKey:@"sectionItems"];
    if ([sectionItems respondsToSelector:@selector(addObjectsFromArray:)]) {
        [sectionItems addObjectsFromArray:rows];
    }
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == kSkipSilenceSettingsSection) {
        [self updateSkipSilenceSectionWithEntry:entry];
    } else {
        %orig;
    }
}

%end

// =============================================================================
#pragma mark - Lightweight toast when silence is skipped
// =============================================================================

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([SkipSilenceDefaults showSavedTime]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yts_silenceStateChanged:)
                                                     name:@"YTSkipSilenceStateChanged"
                                                   object:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"YTSkipSilenceStateChanged"
                                                  object:nil];
}

%new(v@:@)
- (void)yts_silenceStateChanged:(NSNotification *)n {
    SkipSilenceState s = (SkipSilenceState)[[n.userInfo[@"state"] integerValue] integerValue];
    if (s != SkipSilenceStateSilencing) return;
    if (![SkipSilenceDefaults showSavedTime]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
                for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                    if (w.isKeyWindow) { win = w; break; }
                }
                if (win) break;
            }
        }
        if (!win) win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;

        UIView *hud = [win viewWithTag:424242];
        if (hud == nil) {
            hud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 36)];
            hud.tag = 424242;
            hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
            hud.layer.cornerRadius = 8;
            hud.layer.masksToBounds = YES;
            hud.center = CGPointMake(win.center.x, win.bounds.size.height * 0.25);
            UILabel *l = [[UILabel alloc] initWithFrame:hud.bounds];
            l.tag = 424243;
            l.textColor = [UIColor whiteColor];
            l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            l.textAlignment = NSTextAlignmentCenter;
            l.adjustsFontSizeToFitWidth = YES;
            [hud addSubview:l];
            [win addSubview:hud];
        }
        UILabel *l = [hud viewWithTag:424243];
        NSTimeInterval saved = [SkipSilenceDefaults totalSavedSeconds];
        l.text = [NSString stringWithFormat:@"Skip Silence: %.1fs saved", saved];
        hud.alpha = 1.0;
        [UIView animateWithDuration:0.3 delay:0.7 options:0 animations:^{
            hud.alpha = 0.0;
        } completion:nil];
    });
}
%end

// =============================================================================
#pragma mark - Settings.x ctor
// =============================================================================

%ctor {
    @autoreleasepool {
        %init();
    }
}
