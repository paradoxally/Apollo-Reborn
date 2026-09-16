// ApolloKeyboardGlassInset.xm
//
// iOS 27 hides the bottom few points of the composer quick bar (photo, GIF,
// link, B, I, ...) behind the keyboard, so the icons read as flat bottomed —
// issues #825 and #1087.
//
// What actually happens, measured on a real iOS 27 device (iPhone 17 Pro Max,
// 2026-09-16). Apollo is linked against the iOS 16.2 SDK, so iOS runs it
// compatibility-scaled: the app's own screen is 430x932 inside a 440x956
// display. Two surfaces then disagree about where the keyboard starts:
//
//   reported (UIKeyboardFrameEndUserInfoKey)  (0, 602)  440 wide — DEVICE points
//   keyboardLayoutGuide                     (20, 593.7) 390 wide — app points
//   QuickBarKeyboardView                     (0, 557)  430x45   — app points
//
// The bar's bottom edge lands on 602 — the reported top's raw number, consumed
// as if it were app points. The keyboard really starts at 593.7, so the bottom
// 8.3pt of the bar sits inside the keyboard's own area and the glass panel
// paints over it. The same identity holds at every step of the raise
// animation (bar bottom 881 / 657 / 602 against reported 881 / 657 / 602), so
// this is systematic, not a transient.
//
// The correction therefore measures rather than assumes:
//
//     delta = bar.maxY - keyboardLayoutGuide.top
//
// and only when the guide's top falls STRICTLY INSIDE the bar's own span. That
// guard is what makes this safe everywhere else:
//
//   * Keyboard down, bar resting above it: guide top == bar.maxY exactly, so
//     it is not strictly inside and nothing moves (measured: 898 vs 853-898).
//   * Keyboard hiding: the guide's top sits ABOVE the bar, not inside it
//     (measured: 875.5 vs 911-956), so the bar is left alone on the way out.
//   * Where UIKit reports honestly — the Liquid Glass variant, which is iOS 26
//     linked and runs unscaled, and every iOS 26 and earlier build — the guide
//     top coincides with the bar's top or bottom rather than cutting through
//     it, so the delta never arms. Confirmed on the iOS 27.0 simulator: the
//     glass variant reports 592 from both surfaces, and a probe accessory bar
//     on the classic variant put the guide's top exactly on the bar's top.
//
// The fix moves the bar's whole frame up by the delta rather than growing it
// and re-insetting its content. Both land the bar's top in the same place, but
// QuickBarKeyboardView is a Swift view whose internal layout this tweak does
// not own: growing the bounds only lifts the icons by as much as Apollo's own
// constraints happen to pass on (half the delta if they centre, none if they
// pin to the bottom). Moving the frame lifts the icons by exactly the delta
// whatever those constraints do, and leaves no gap — the bar's new bottom edge
// lands precisely on the keyboard's true top.
//
// The correction is applied in -setFrame:, against the frame UIKit passes in,
// which is always UIKit's own uncorrected placement. That makes it idempotent
// and free of feedback: feeding an already-corrected frame back through leaves
// the guide's top sitting on the bar's bottom edge, which fails the strictly-
// inside test and is passed through untouched.

#import <UIKit/UIKit.h>
#import <math.h>

#import "ApolloCommon.h"

@interface _TtC6Apollo20QuickBarKeyboardView : UIView
@end

// Sub-point overlap is rounding, not coverage.
static const CGFloat kApolloKeyboardGlassEpsilon = 0.5;
// Last delta reported to the log, so a settled bar does not reprint the same
// line on every layout pass.
static CGFloat sApolloKeyboardGlassLoggedDelta = -1.0;

#pragma mark - Measurement

// The app's own window, not the keyboard's: keyboardLayoutGuide only tracks the
// keyboard for a view in the hierarchy the keyboard is covering. Apollo's is a
// UIWindow subclass (Apollo.ThemeableWindow), so this cannot test for an exact
// class. The bar itself lives in UITextEffectsWindow, which is why the guide
// has to be read from the app's side and converted across.
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

// Top of the region the keyboard really covers, in window coordinates, or
// CGFLOAT_MAX when UIKit has no opinion yet. Window coordinates are shared
// across the app and text-effects windows even while the app is
// compatibility-scaled, which is what makes this comparable with the bar.
static CGFloat ApolloKeyboardGlassGuideTopInWindow(void) {
    if (@available(iOS 15.0, *)) {
        UIWindow *window = ApolloKeyboardGlassAppWindow();
        UIView *view = window.rootViewController.view ?: window;
        if (!view) return CGFLOAT_MAX;
        // layoutFrame only resolves after a layout pass; the guide otherwise
        // still reads zero on the very event that created it.
        UILayoutGuide *guide = view.keyboardLayoutGuide;
        [view layoutIfNeeded];
        CGRect frame = guide.layoutFrame;
        if (CGRectIsEmpty(frame)) return CGFLOAT_MAX;
        return CGRectGetMinY([view convertRect:frame toView:nil]);
    }
    return CGFLOAT_MAX;
}

// How far UIKit has parked the bar inside the keyboard's own area, or 0 when it
// has not. `frame` is UIKit's placement in the bar's superview coordinates.
static CGFloat ApolloKeyboardGlassOverlapForFrame(UIView *bar, CGRect frame) {
    UIView *superview = bar.superview;
    if (!superview || !bar.window) return 0.0;

    CGFloat guideTop = ApolloKeyboardGlassGuideTopInWindow();
    if (guideTop == CGFLOAT_MAX) return 0.0;

    CGRect inWindow = [superview convertRect:frame toView:nil];
    CGFloat top = CGRectGetMinY(inWindow);
    CGFloat bottom = CGRectGetMaxY(inWindow);

    // Strictly inside: the keyboard's top edge has to CUT THROUGH the bar. A
    // guide sitting on either edge is the healthy resting arrangement, and a
    // guide above the bar entirely is the keyboard on its way out.
    if (!(top < guideTop && guideTop < bottom)) return 0.0;

    CGFloat delta = bottom - guideTop;
    // A delta at or beyond the bar's own height would mean the bar is entirely
    // swallowed, which is a bad reading rather than a keyboard.
    if (delta < kApolloKeyboardGlassEpsilon || delta >= CGRectGetHeight(inWindow)) return 0.0;
    return delta;
}

#pragma mark - Hooks

%hook _TtC6Apollo20QuickBarKeyboardView

- (void)setFrame:(CGRect)frame {
    CGFloat delta = ApolloKeyboardGlassOverlapForFrame((UIView *)self, frame);
    if (delta > 0.0) {
        if (fabs(delta - sApolloKeyboardGlassLoggedDelta) >= kApolloKeyboardGlassEpsilon) {
            sApolloKeyboardGlassLoggedDelta = delta;
            // Always-on: this is the one line that explains a mis-placed bar in
            // a user's log export without needing verbose logging turned on.
            ApolloLogAlways(@"[KeyboardGlass] lifted quick bar by %.1fpt "
                             "(bar %.1f-%.1f, keyboard top %.1f)",
                            delta, CGRectGetMinY(frame), CGRectGetMaxY(frame),
                            CGRectGetMaxY(frame) - delta);
        }
        frame.origin.y -= delta;
    } else if (sApolloKeyboardGlassLoggedDelta > 0.0) {
        sApolloKeyboardGlassLoggedDelta = -1.0;
    }
    %orig(frame);
}

%end
