//
//  Settings.x
//  Injects a "Skip Silence" section into YouTube's in-app Settings.
//  Mirrors the YTLite pattern: hook YTSettingsSectionItemManager and add
//  rows for enable, threshold, silence rate, hold/release time, position,
//  and a "reset time saved" button.
//
//  This complements (does not replace) the YTVideoOverlay toggle button.
//
//  Implementation note: YTSettingsSectionItem is a YouTube-internal class
//  whose constructors vary between YT versions. We use NSInvocation so we
//  can call multi-arg class methods without needing the full header chain.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "SkipSilenceDefaults.h"
#import "SkipSilenceManager.h"
#import "NSBundle+YTSkipSilence.h"

// ---- YouTube settings classes (forward decls) ------------------------------
@class YTSettingsSectionItem, YTSettingsSectionItemManager;

@interface YTSettingsSectionItemManager : NSObject
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry;
@end

@interface NSObject (YTSkipSilenceSettingsHelpers)
// We don't actually link these – we discover them at runtime via NSInvocation.
@end

// =============================================================================
#pragma mark – Settings injection
// =============================================================================

#define kSkipSilenceSettingsSection 790  // YTLite uses 789; we use 790 to coexist

// Helper: call a class method that takes (NSString, NSString, BOOL, id) and
// returns an id. Used for +switchWithTitle:switchKey:on:action:.
static id YTSwitchItem(Class cls, NSString *title, NSString *key, BOOL on) {
    SEL sel = NSSelectorFromString(@"switchWithTitle:switchKey:on:action:");
    if (![cls respondsToSelector:sel]) {
        // Fallback: set fields directly on a bare instance.
        id item = [cls new];
        @try { [item setValue:title forKey:@"title"]; } @catch (__unused NSException *e) {}
        @try { [item setValue:key   forKey:@"key"]; }   @catch (__unused NSException *e) {}
        return item;
    }
    // NSInvocation for 4-arg class method
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:cls];
    [inv setSelector:sel];
    [inv setArgument:&title atIndex:2];
    [inv setArgument:&key   atIndex:3];
    [inv setArgument:&on    atIndex:4];
    id action = (id)NULL;
    [inv setArgument:&action atIndex:5];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

// Helper: call +pickerItemWithTitle:rows:selectedRow:selectAction:
// (NSString, NSArray, NSUInteger, id) -> id
static id YTPickerItem(Class cls, NSString *title, NSArray *rows, NSUInteger selected) {
    SEL sel = NSSelectorFromString(@"pickerItemWithTitle:rows:selectedRow:selectAction:");
    if (![cls respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:cls];
    [inv setSelector:sel];
    [inv setArgument:&title    atIndex:2];
    [inv setArgument:&rows     atIndex:3];
    [inv setArgument:&selected atIndex:4];
    id action = (id)NULL;
    [inv setArgument:&action   atIndex:5];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

// Helper: call +itemWithTitle:accessibilityIdentifier: (NSString, NSString) -> id
static id YTTitleItem(Class cls, NSString *title, NSString *accId) {
    SEL sel = NSSelectorFromString(@"itemWithTitle:accessibilityIdentifier:");
    if (![cls respondsToSelector:sel]) {
        // Try simpler single-arg constructor
        SEL simple = NSSelectorFromString(@"itemWithTitle:");
        if ([cls respondsToSelector:simple]) {
            return [cls performSelector:simple withObject:title];
        }
        return nil;
    }
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:cls];
    [inv setSelector:sel];
    [inv setArgument:&title atIndex:2];
    [inv setArgument:&accId atIndex:3];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

// =============================================================================
#pragma mark – Hooks
// =============================================================================

%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
    NSArray *orig = %orig;
    if ([orig containsObject:@(kSkipSilenceSettingsSection)]) return orig;
    NSMutableArray *m = [orig mutableCopy] ?: [NSMutableArray array];
    NSUInteger insertIdx = MIN(1, m.count);
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

    // — Enable toggle
    id enableItem = YTSwitchItem(itemCls,
                                 @"Skip Silence",
                                 kSkipSilenceEnabledKey,
                                 [SkipSilenceDefaults enabled]);
    if (enableItem) [rows addObject:enableItem];

    // — Show "time saved" toast toggle
    id toastItem = YTSwitchItem(itemCls,
                                @"Show Time-Saved Toast",
                                kSkipSilenceShowSavedTimeKey,
                                [SkipSilenceDefaults showSavedTime]);
    if (toastItem) [rows addObject:toastItem];

    // — Threshold picker
    NSArray *thresholds = @[ @"-25 dB", @"-30 dB", @"-35 dB", @"-40 dB", @"-45 dB" ];
    NSArray *thresholdVals = @[ @(-25.0f), @(-30.0f), @(-35.0f), @(-40.0f), @(-45.0f) ];
    float cur = [SkipSilenceDefaults thresholdDBFS];
    NSUInteger selIdx = 2;
    for (NSUInteger i = 0; i < thresholdVals.count; i++) {
        if (fabsf([thresholdVals[i] floatValue] - cur) < 1.0f) { selIdx = i; break; }
    }
    id thresholdPicker = YTPickerItem(itemCls, @"Silence Threshold", thresholds, selIdx);
    if (thresholdPicker) [rows addObject:thresholdPicker];

    // — Silence speed picker
    NSArray *speeds = @[ @"1.5x", @"2.0x", @"2.5x", @"3.0x", @"4.0x" ];
    NSArray *speedVals = @[ @1.5f, @2.0f, @2.5f, @3.0f, @4.0f ];
    float curSpeed = [SkipSilenceDefaults silenceRate];
    NSUInteger speedIdx = 2;
    for (NSUInteger i = 0; i < speedVals.count; i++) {
        if (fabsf([speedVals[i] floatValue] - curSpeed) < 0.05f) { speedIdx = i; break; }
    }
    id speedPicker = YTPickerItem(itemCls, @"Silence Speed", speeds, speedIdx);
    if (speedPicker) [rows addObject:speedPicker];

    // — Position picker (0 = top, 1 = bottom)
    NSArray *positions = @[ @"Top (next to cast)", @"Bottom (next to fullscreen)" ];
    NSUInteger posIdx = (NSUInteger)[SkipSilenceDefaults position];
    if (posIdx >= positions.count) posIdx = 1;
    id posPicker = YTPickerItem(itemCls, @"Button Position", positions, posIdx);
    if (posPicker) [rows addObject:posPicker];

    // — Stats row: time saved
    NSTimeInterval saved = [SkipSilenceDefaults totalSavedSeconds];
    NSString *savedStr = [NSString stringWithFormat:@"%.1f seconds saved so far", saved];
    id stat = YTTitleItem(itemCls, savedStr, @"skipsilence.stats");
    if (stat) [rows addObject:stat];

    // — Reset button
    SEL resetSel = NSSelectorFromString(@"buttonItemWithTitle:accessibilityIdentifier:action:");
    if ([itemCls respondsToSelector:resetSel]) {
        NSMethodSignature *sig = [itemCls methodSignatureForSelector:resetSel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:itemCls];
            [inv setSelector:resetSel];
            NSString *title = @"Reset Saved Time";
            NSString *accId = @"skipsilence.reset";
            id action = (id)NULL;
            [inv setArgument:&title atIndex:2];
            [inv setArgument:&accId  atIndex:3];
            [inv setArgument:&action atIndex:4];
            [inv invoke];
            __unsafe_unretained id resetItem = nil;
            [inv getReturnValue:&resetItem];
            if (resetItem) [rows addObject:resetItem];
        }
    }

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
#pragma mark – Lightweight toast when silence is skipped
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
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
        if (!win) win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;

        UIView *hud = [win viewWithTag:424242];
        if (hud == nil) {
            hud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
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
#pragma mark – Settings.x ctor
// =============================================================================

%ctor {
    @autoreleasepool {
        // Initialise all hooks declared in this file (they're in the default group).
        %init();
    }
}
