#import "ApolloCommon.h"
#import "ApolloState.h"
#import "UserDefaultConstants.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// MARK: - Scroll Edge Effect Style (Liquid Glass, iOS 26+)
//
// iOS 26 introduced UIScrollView.topEdgeEffect/bottomEdgeEffect, a glass blur
// rendered where content scrolls under the nav/tab bars. iOS 26 defaults to a
// soft gradient blur; iOS 27 betas default to a hard cutoff with a dividing
// line, which some users find jarring. This lets users override the style
// (or hide the effect entirely) for Apollo's scrolling surfaces.
//
// UIScrollEdgeEffect/UIScrollEdgeEffectStyle are public iOS 26 SDK classes,
// but referencing them directly would create a hard class reference that
// could fail to bind on the pre-26 devices this tweak still targets. Access
// everything defensively via objc_getClass/objc_msgSend, mirroring the
// pattern used for other iOS 26-only APIs (see ApolloNativeActionMenus.xm).

static NSString *const ApolloScrollEdgeEffectStyleChangedNotification = @"ApolloScrollEdgeEffectStyleChangedNotification";

static id ApolloScrollEdgeEffectStyleObjectForMode(NSInteger mode) {
    Class styleClass = objc_getClass("UIScrollEdgeEffectStyle");
    if (!styleClass) return nil;

    SEL selector;
    switch (mode) {
        case ApolloScrollEdgeEffectStyleSoft: selector = NSSelectorFromString(@"softStyle"); break;
        case ApolloScrollEdgeEffectStyleHard: selector = NSSelectorFromString(@"hardStyle"); break;
        default: selector = NSSelectorFromString(@"automaticStyle"); break;
    }
    if (![styleClass respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(styleClass, selector);
}

static BOOL sLoggedScrollEdgeEffectDiagnostics = NO;

static void ApolloApplyScrollEdgeEffectToEdge(UIScrollView *scrollView, SEL edgeSelector, NSInteger mode) {
    if (![scrollView respondsToSelector:edgeSelector]) return;
    id effect = ((id (*)(id, SEL))objc_msgSend)(scrollView, edgeSelector);
    if (!effect) return;

    SEL setHiddenSelector = NSSelectorFromString(@"setHidden:");
    BOOL hasSetHidden = [effect respondsToSelector:setHiddenSelector];
    if (hasSetHidden) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, setHiddenSelector, mode == ApolloScrollEdgeEffectStyleHidden);
    }

    SEL setStyleSelector = NSSelectorFromString(@"setStyle:");
    id style = ApolloScrollEdgeEffectStyleObjectForMode(mode);
    BOOL hasSetStyle = (style != nil) && [effect respondsToSelector:setStyleSelector];
    if (hasSetStyle) {
        ((void (*)(id, SEL, id))objc_msgSend)(effect, setStyleSelector, style);
    }

    if (!sLoggedScrollEdgeEffectDiagnostics) {
        sLoggedScrollEdgeEffectDiagnostics = YES;
        ApolloLog(@"[ScrollEdgeEffect] applied mode=%ld effect=%@ setHidden=%d style=%@ setStyle=%d on %@",
                  (long)mode, effect, hasSetHidden, style, hasSetStyle, scrollView);
    }
}

// Declared in ApolloState.h; called from UIScrollView's didMoveToWindow hook in
// ApolloAutoHideTabBar.xm (a second %hook UIScrollView didMoveToWindow here would be a
// duplicate symbol that the Logos internal generator silently drops).
void ApolloApplyScrollEdgeEffectStyle(UIScrollView *scrollView) {
    if (!IsLiquidGlass()) return;

    SEL topSelector = NSSelectorFromString(@"topEdgeEffect");
    SEL bottomSelector = NSSelectorFromString(@"bottomEdgeEffect");
    if (![scrollView respondsToSelector:topSelector]) return;

    NSInteger mode = sScrollEdgeEffectStyle;
    ApolloApplyScrollEdgeEffectToEdge(scrollView, topSelector, mode);
    ApolloApplyScrollEdgeEffectToEdge(scrollView, bottomSelector, mode);
}

static void ApolloApplyScrollEdgeEffectStyleToViewTree(UIView *view) {
    if ([view isKindOfClass:[UIScrollView class]]) {
        ApolloApplyScrollEdgeEffectStyle((UIScrollView *)view);
    }
    for (UIView *subview in view.subviews) {
        ApolloApplyScrollEdgeEffectStyleToViewTree(subview);
    }
}

static void ApolloApplyScrollEdgeEffectStyleToAllScrollViews(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        ApolloApplyScrollEdgeEffectStyleToViewTree(window);
    }
}

%ctor {
    ApolloLog(@"[ScrollEdgeEffect] module loaded, mode=%ld liquidGlass=%d", (long)sScrollEdgeEffectStyle, IsLiquidGlass());
    [[NSNotificationCenter defaultCenter] addObserverForName:ApolloScrollEdgeEffectStyleChangedNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(__unused NSNotification *notification) {
        ApolloApplyScrollEdgeEffectStyleToAllScrollViews();
    }];
}
