#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Grabbing a list while it bounces past its edge leaves a UIKit scroll animation
// running into the new drag. It writes contentOffset after the drag on every
// frame, so the list sticks near the edge while the finger moves (~250 ms on the
// classic build). UIKit does not cancel it when the pan begins; do it here.
//
// The handler is attached from gestureRecognizerShouldBegin: because Texture
// replaces a table's recognizer after it mounts, so one attached earlier can be
// stale. The cancel itself waits for Began: by then isDragging is YES, which the
// native search bar's offset pins (ApolloSearchNativeBar.xm) require to stand
// down. Subclasses that override gestureRecognizerShouldBegin: without calling
// super (the Highlights carousel, feed gallery, spotlight) are not covered.
static char kApolloDragHandoffAttachedKey;

%hook UIScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    BOOL begins = %orig;
    if (begins && recognizer == self.panGestureRecognizer &&
        !objc_getAssociatedObject(recognizer, &kApolloDragHandoffAttachedKey)) {
        objc_setAssociatedObject(recognizer, &kApolloDragHandoffAttachedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [recognizer addTarget:self action:@selector(_apolloDragHandoffPanChanged:)];
    }
    return begins;
}

%new
- (void)_apolloDragHandoffPanChanged:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateBegan) return;
    if (@available(iOS 17.4, *)) {
        if (self.isScrollAnimating) [self setContentOffset:self.contentOffset animated:NO];
    }
}
%end
