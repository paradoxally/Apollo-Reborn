#import <UIKit/UIKit.h>

// Grabbing a list while it bounces past its edge leaves a UIKit scroll animation
// running into the new drag. It writes contentOffset after the drag on every
// frame, so the list sticks near the edge while the finger moves (~250 ms on the
// classic build). UIKit does not cancel it when the pan begins; do it here.
// A target added to panGestureRecognizer is not enough: Texture replaces the
// table's recognizer after it mounts.
%hook UIScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    BOOL begins = %orig;
    if (begins && recognizer == self.panGestureRecognizer) {
        if (@available(iOS 17.4, *)) {
            if (self.isScrollAnimating) [self setContentOffset:self.contentOffset animated:NO];
        }
    }
    return begins;
}
%end
