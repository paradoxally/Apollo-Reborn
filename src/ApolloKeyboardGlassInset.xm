// ApolloKeyboardGlassInset.xm
//
// MEASUREMENT BUILD — this module changes no geometry. It only records where
// UIKit puts the composer quick bar and where UIKit says the keyboard starts,
// so the iOS 27 overlap in issues #825 and #1087 can be derived from a real
// device instead of guessed.
//
// The bug: on iOS 27 the bottom few points of Apollo's composer quick bar
// (photo, GIF, link, B, I, ...) sit behind the keyboard's glass panel, so the
// icons read as flat bottomed. Apollo's bar is an inputAccessoryView, which
// means UIKit positions it — rewriting the keyboard notification (the fix that
// works for apps that position their own bar) cannot move it. Any correction
// has to act on the bar's own geometry.
//
// What is already established by measurement on the iOS 27.0 (24A434)
// simulator, iPhone Air, so it is not re-derived on device:
//
//   * A build linked against the iOS 26 SDK (the Liquid Glass variant, sdk
//     19.0) runs at native size and its reported keyboard frame and
//     keyboardLayoutGuide agree exactly (both 592 on a 912pt screen). That
//     variant is immune, which matches #1087 being filed against non-glass.
//   * A build linked against sdk 16.2 (the classic variant) is
//     compatibility-scaled: UIScreen.mainScreen.bounds reads 393x852 inside a
//     420x912 screen, and keyboard notification rects arrive in UNSCALED
//     device points (the rect is 420 wide). Those are different coordinate
//     spaces, so any reported-vs-guide comparison has to convert first.
//   * Attaching a known 46pt accessory bar showed keyboardLayoutGuide's top
//     lands exactly on that bar's TOP (507.3 for both). The guide INCLUDES the
//     input accessory view. So `bar.maxY - guideTop` measures the bar's own
//     height, not the overlap, and cannot be the correction.
//   * On that simulator the glass panel's top edge meets the accessory bar's
//     bottom exactly — nothing is covered. The bug does not reproduce there,
//     which is why this measurement has to come off a real device.
//
// Each line below carries every candidate pair at once, so a single keyboard
// raise shows which surface actually disagrees on the affected device.

#import <UIKit/UIKit.h>
#import <math.h>

#import "ApolloCommon.h"

@interface _TtC6Apollo20QuickBarKeyboardView : UIView
@end

// Last frame carried by a keyboard notification, in whatever coordinate space
// UIKit handed it over in.
static CGRect sApolloKeyboardGlassReportedFrame;
static BOOL sApolloKeyboardGlassHaveReported = NO;
// Dedup key for the bar snapshot: layoutSubviews fires far too often to log
// unconditionally, and a settled bar produces an identical line every pass.
static CGFloat sApolloKeyboardGlassLastBarTop = CGFLOAT_MAX;
static CGFloat sApolloKeyboardGlassLastGuideTop = CGFLOAT_MAX;

#pragma mark - Measurement

// The app's own window, not the keyboard's: keyboardLayoutGuide only tracks the
// keyboard for a view in the hierarchy the keyboard is covering. Apollo's is a
// UIWindow subclass (Apollo.ThemeableWindow), so this cannot test for an exact
// class.
static UIWindow *ApolloKeyboardGlassAppWindow(void) {
    UIWindow *fallback = nil;
    for (UIWindow *window in ApolloAllWindows()) {
        if (window.hidden || window.alpha < 0.01) continue;
        NSString *name = NSStringFromClass(window.class);
        if ([name containsString:@"Keyboard"] || [name containsString:@"TextEffects"]) continue;
        if (window.isKeyWindow) return window;
        if (!fallback) fallback = window;
    }
    return fallback;
}

// keyboardLayoutGuide's frame in window coordinates, or CGRectNull when UIKit
// has no opinion yet.
static CGRect ApolloKeyboardGlassGuideFrame(void) {
    if (@available(iOS 15.0, *)) {
        UIWindow *window = ApolloKeyboardGlassAppWindow();
        UIView *view = window.rootViewController.view ?: window;
        if (!view) return CGRectNull;
        // layoutFrame only resolves after a layout pass; the guide otherwise
        // still reads zero on the very notification that created it.
        UILayoutGuide *guide = view.keyboardLayoutGuide;
        [view layoutIfNeeded];
        CGRect frame = guide.layoutFrame;
        if (CGRectIsEmpty(frame)) return CGRectNull;
        return [view convertRect:frame toView:nil];
    }
    return CGRectNull;
}

static NSString *ApolloKeyboardGlassRectString(CGRect rect) {
    if (CGRectIsNull(rect)) return @"none";
    return [NSString stringWithFormat:@"(%.1f,%.1f %.1fx%.1f)",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

// One line with every candidate pair on it, so whichever surface disagrees on
// the affected device is visible without needing a second capture.
static void ApolloKeyboardGlassLog(UIView *bar, NSString *reason) {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGRect guide = ApolloKeyboardGlassGuideFrame();
    CGRect reported = sApolloKeyboardGlassHaveReported
        ? sApolloKeyboardGlassReportedFrame : CGRectNull;
    CGRect barFrame = CGRectNull;
    if (bar.window) barFrame = [bar convertRect:bar.bounds toView:nil];

    // The classic variant is compatibility-scaled, so a notification rect can
    // be wider than the app's own screen. Report the ratio rather than a
    // pre-converted number, so the raw values stay auditable.
    CGFloat spaceRatio = (!CGRectIsNull(reported) && CGRectGetWidth(screen) > 0.5)
        ? CGRectGetWidth(reported) / CGRectGetWidth(screen) : 1.0;
    BOOL haveBoth = !CGRectIsNull(barFrame) && !CGRectIsNull(guide);

    ApolloLogAlways(@"[KeyboardGlass] %@ screen=%@ reported=%@ guide=%@ bar=%@ "
                     "ratio=%.4f barTop-guideTop=%.1f barBottom-guideTop=%.1f",
                    reason,
                    ApolloKeyboardGlassRectString(screen),
                    ApolloKeyboardGlassRectString(reported),
                    ApolloKeyboardGlassRectString(guide),
                    ApolloKeyboardGlassRectString(barFrame),
                    spaceRatio,
                    haveBoth ? CGRectGetMinY(barFrame) - CGRectGetMinY(guide) : (CGFloat)NAN,
                    haveBoth ? CGRectGetMaxY(barFrame) - CGRectGetMinY(guide) : (CGFloat)NAN);
}

// layoutSubviews runs on every pass; only a bar or guide that actually moved is
// worth a line.
static void ApolloKeyboardGlassLogBarIfMoved(UIView *bar, NSString *reason) {
    if (!bar.window) return;
    CGRect barFrame = [bar convertRect:bar.bounds toView:nil];
    CGRect guide = ApolloKeyboardGlassGuideFrame();
    CGFloat barTop = CGRectGetMinY(barFrame);
    CGFloat guideTop = CGRectIsNull(guide) ? CGFLOAT_MAX : CGRectGetMinY(guide);
    if (fabs(barTop - sApolloKeyboardGlassLastBarTop) < 0.5 &&
        fabs(guideTop - sApolloKeyboardGlassLastGuideTop) < 0.5) return;
    sApolloKeyboardGlassLastBarTop = barTop;
    sApolloKeyboardGlassLastGuideTop = guideTop;
    ApolloKeyboardGlassLog(bar, reason);
}

#pragma mark - Hooks

%hook _TtC6Apollo20QuickBarKeyboardView

- (void)didMoveToWindow {
    %orig;
    sApolloKeyboardGlassLastBarTop = CGFLOAT_MAX;
    ApolloKeyboardGlassLogBarIfMoved((UIView *)self, @"bar-didMoveToWindow");
}

- (void)layoutSubviews {
    %orig;
    ApolloKeyboardGlassLogBarIfMoved((UIView *)self, @"bar-layout");
}

%end

%ctor {
    for (NSNotificationName name in @[UIKeyboardWillShowNotification,
                                      UIKeyboardDidShowNotification,
                                      UIKeyboardWillHideNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name
                                                       object:nil
                                                        queue:NSOperationQueue.mainQueue
                                                   usingBlock:^(NSNotification *note) {
            NSValue *end = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            if (![end isKindOfClass:NSValue.class]) return;
            sApolloKeyboardGlassReportedFrame = end.CGRectValue;
            sApolloKeyboardGlassHaveReported = YES;
            // Reset the dedup so the bar re-logs against the new keyboard.
            sApolloKeyboardGlassLastBarTop = CGFLOAT_MAX;
            ApolloKeyboardGlassLog(nil, note.name);
        }];
    }
    // Touch the guide once the app has a window, so UIKit is already tracking
    // it before the first keyboard raise rather than resolving to zero on it.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                   object:nil
                                                    queue:NSOperationQueue.mainQueue
                                               usingBlock:^(__unused NSNotification *note) {
        if (@available(iOS 15.0, *)) {
            UIWindow *window = ApolloKeyboardGlassAppWindow();
            UIView *view = window.rootViewController.view ?: window;
            (void)view.keyboardLayoutGuide;
        }
    }];
    ApolloLogAlways(@"[KeyboardGlass] measurement module loaded");
}
