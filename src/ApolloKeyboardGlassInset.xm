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
#import <objc/runtime.h>

#import "ApolloCommon.h"

@interface _TtC6Apollo20QuickBarKeyboardView : UIView
@end

// Sub-point overlap is rounding, not coverage.
static const CGFloat kApolloKeyboardGlassEpsilon = 0.5;

// A MEASURED CONSTANT, and the one number here that is not derived at runtime.
//
// keyboardLayoutGuide describes a logical box, not where a keyboard actually
// paints, and third-party keyboards miss by more than Apple's does. Measured on
// an iPhone 17 Pro Max, same composer, same build: Apple's keyboard leaves
// 6.3pt between the toolbar glyphs and the panel, Microsoft SwiftKey leaves
// 3.0pt. The icons are fully drawn either way — this is the bar's background
// padding being eaten, not its contents — but the bar reads noticeably thinner.
//
// There is no in-process way to derive it. The keyboard renders out of process:
// there is no UIRemoteKeyboardWindow to measure, and Apple's own panel paints
// full width (1.0 -> 439.0) while its guide claims a 20pt inset, so even the
// guide's shape cannot stand in for the paint. So this is a deliberate magic
// number, applied ONLY to non-Apple keyboards and only on top of an already
// armed correction. A different third-party keyboard may want a different
// value; re-measure rather than assuming this one transfers.
static const CGFloat kApolloKeyboardGlassThirdPartyExtraLift = 3.3;
// Last delta reported to the log, so a settled bar does not reprint the same
// line on every layout pass.
static CGFloat sApolloKeyboardGlassLoggedDelta = -1.0;

#pragma mark - Keyboard identity

// sendAction:to:nil walks the responder chain, so this is the supported way to
// reach the first responder without a private API.
static __weak UIResponder *sApolloKeyboardGlassFoundResponder = nil;

@interface UIResponder (ApolloKeyboardGlass)
- (void)apolloKeyboardGlassCaptureResponder:(id)sender;
@end

@implementation UIResponder (ApolloKeyboardGlass)
- (void)apolloKeyboardGlassCaptureResponder:(__unused id)sender {
    sApolloKeyboardGlassFoundResponder = self;
}
@end

// Whether the keyboard on screen is a third-party extension rather than Apple's.
// Apple's input modes carry a locale-shaped identifier ("en_US@sw=QWERTY;hw=Automatic");
// a keyboard extension's is its bundle identifier, so the "@sw=" marker separates
// them. Unknown means "assume Apple" — the extra lift is opt-in, and guessing the
// other way would move the one configuration already confirmed correct.
static BOOL ApolloKeyboardGlassThirdPartyKeyboardActive(void) {
    sApolloKeyboardGlassFoundResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(apolloKeyboardGlassCaptureResponder:)
                                             to:nil
                                           from:nil
                                       forEvent:nil];
    UITextInputMode *mode = sApolloKeyboardGlassFoundResponder.textInputMode;
    if (!mode) return NO;
    NSString *identifier = nil;
    @try {
        identifier = [mode valueForKey:@"identifier"];
    } @catch (__unused NSException *exception) {
        return NO;
    }
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return NO;
    return ![identifier containsString:@"@sw="];
}

// The classification is kept PER BAR, not in one process-global flag: on iPad and
// visionOS several scenes are live at once, and a global would let a bar
// attaching in one scene restamp the answer another scene is about to use.
//
// It is still resolved at most once per bar per keyboard change — the responder
// walk is far too costly to repeat inside -setFrame:, which runs on every frame
// of the keyboard transition. A generation counter, bumped when the input mode
// changes, is what invalidates the cache without needing to enumerate live bars.
static char kApolloKeyboardGlassThirdPartyKey;
static char kApolloKeyboardGlassGenerationKey;
static NSUInteger sApolloKeyboardGlassInputModeGeneration = 1;

static BOOL ApolloKeyboardGlassBarIsThirdParty(UIView *bar) {
    if (!bar) return NO;
    NSNumber *cached = objc_getAssociatedObject(bar, &kApolloKeyboardGlassThirdPartyKey);
    NSNumber *generation = objc_getAssociatedObject(bar, &kApolloKeyboardGlassGenerationKey);
    if (cached && generation.unsignedIntegerValue == sApolloKeyboardGlassInputModeGeneration) {
        return cached.boolValue;
    }
    BOOL thirdParty = ApolloKeyboardGlassThirdPartyKeyboardActive();
    objc_setAssociatedObject(bar, &kApolloKeyboardGlassThirdPartyKey, @(thirdParty),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kApolloKeyboardGlassGenerationKey,
                             @(sApolloKeyboardGlassInputModeGeneration),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return thirdParty;
}

#pragma mark - Measurement

// The app's own window, not the keyboard's: keyboardLayoutGuide only tracks the
// keyboard for a view in the hierarchy the keyboard is covering. Apollo's is a
// UIWindow subclass (Apollo.ThemeableWindow), so this cannot test for an exact
// class. The bar itself lives in UITextEffectsWindow, which is why the guide
// has to be read from the app's side and converted across.
//
// Scoped to the bar's OWN scene. Apollo runs multi-window on iPad and visionOS,
// where a scene-blind walk can hand back a window from a different scene and
// measure a keyboard that is not the one covering this bar — either missing a
// real overlap or inventing one.
//
// A nil scene falls back to the scene-blind walk rather than declining to
// measure. The bar lives in UITextEffectsWindow, and refusing to correct
// wherever that window turns out to have no scene would trade a verified fix
// for an unverified assumption; with no scene there is also nothing to
// disambiguate, so the blind walk is the best answer available.
static UIWindow *ApolloKeyboardGlassAppWindow(UIWindowScene *scene) {
    UIWindow *fallback = nil;
    for (UIWindow *window in ApolloAllWindows()) {
        if (scene && window.windowScene != scene) continue;
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
static CGFloat ApolloKeyboardGlassGuideTopInWindow(UIWindowScene *scene) {
    if (@available(iOS 15.0, *)) {
        UIWindow *window = ApolloKeyboardGlassAppWindow(scene);
        UIView *view = window.rootViewController.view ?: window;
        if (!view) return CGFLOAT_MAX;
        UILayoutGuide *guide = view.keyboardLayoutGuide;
        CGRect frame = guide.layoutFrame;
        // The guide reads back zero until the first layout pass resolves it, so
        // one pass is forced to prime it and never again. Forcing it on every
        // read would put a full root-view layout inside UIKit's keyboard
        // animation, which is the whole frame budget; -didMoveToWindow primes
        // it earlier anyway, so this is a fallback rather than the usual path.
        if (CGRectIsEmpty(frame)) {
            [view layoutIfNeeded];
            frame = guide.layoutFrame;
            if (CGRectIsEmpty(frame)) return CGFLOAT_MAX;
        }
        return CGRectGetMinY([view convertRect:frame toView:nil]);
    }
    return CGFLOAT_MAX;
}

// Resolve the guide once the bar joins a window, so the priming layout pass
// above happens off the keyboard animation's critical path.
static void ApolloKeyboardGlassPrimeGuide(UIView *bar) {
    if (@available(iOS 15.0, *)) {
        UIWindow *window = ApolloKeyboardGlassAppWindow(bar.window.windowScene);
        UIView *view = window.rootViewController.view ?: window;
        if (!view) return;
        if (CGRectIsEmpty(view.keyboardLayoutGuide.layoutFrame)) [view layoutIfNeeded];
    }
}

// How far UIKit has parked the bar inside the keyboard's own area, or 0 when it
// has not. `frame` is UIKit's placement in the bar's superview coordinates.
static CGFloat ApolloKeyboardGlassOverlapForFrame(UIView *bar, CGRect frame) {
    UIView *superview = bar.superview;
    if (!superview || !bar.window) return 0.0;

    CGFloat guideTop = ApolloKeyboardGlassGuideTopInWindow(bar.window.windowScene);
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
    // Rides on top of an armed correction rather than arming one of its own, so a
    // keyboard this tweak has no quarrel with is never nudged.
    if (ApolloKeyboardGlassBarIsThirdParty(bar)) {
        CGFloat padded = delta + kApolloKeyboardGlassThirdPartyExtraLift;
        if (padded < CGRectGetHeight(inWindow)) delta = padded;
    }
    return delta;
}

#pragma mark - Hooks

%hook _TtC6Apollo20QuickBarKeyboardView

- (void)didMoveToWindow {
    %orig;
    ApolloKeyboardGlassPrimeGuide((UIView *)self);
    // A reused bar can come back attached to a different composer under a
    // different keyboard, so drop the cached answer and let the next frame
    // resolve it once.
    objc_setAssociatedObject(self, &kApolloKeyboardGlassThirdPartyKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setFrame:(CGRect)frame {
    CGFloat delta = ApolloKeyboardGlassOverlapForFrame((UIView *)self, frame);
    if (delta > 0.0) {
        if (fabs(delta - sApolloKeyboardGlassLoggedDelta) >= kApolloKeyboardGlassEpsilon) {
            sApolloKeyboardGlassLoggedDelta = delta;
            // Always-on: this is the one line that explains a mis-placed bar in
            // a user's log export without needing verbose logging turned on.
            ApolloLogAlways(@"[KeyboardGlass] lifted quick bar by %.1fpt "
                             "(bar %.1f-%.1f, keyboard top %.1f, third-party kb %@)",
                            delta, CGRectGetMinY(frame), CGRectGetMaxY(frame),
                            CGRectGetMaxY(frame) - delta,
                            ApolloKeyboardGlassBarIsThirdParty((UIView *)self) ? @"yes" : @"no");
        }
        frame.origin.y -= delta;
    } else if (sApolloKeyboardGlassLoggedDelta > 0.0) {
        sApolloKeyboardGlassLoggedDelta = -1.0;
    }
    %orig(frame);
}

%end

%ctor {
    // The globe key swaps keyboards without the bar leaving its window, so the
    // cached answer has to follow the input mode as well as the bar's lifecycle.
    [NSNotificationCenter.defaultCenter
        addObserverForName:UITextInputCurrentInputModeDidChangeNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
        sApolloKeyboardGlassInputModeGeneration++;
    }];
}
