#!/bin/sh
set -eu

# ApolloDuoHollaWrapperFrame clamps the Saved! wrapper to the safe band: the
# result is the frame's overlap with the band. Both edges are clamped before
# the frame changes (reading the right edge after moving the origin widened
# the wrapper), and a frame with no overlap gets width 0, never a negative one.
#
# The clamp lines are copied out of the source and run on sample frames, so
# this checks what the code computes, not how it is spelled.

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloDuoRail.xm"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

body=$(awk '/^static CGRect ApolloDuoHollaWrapperFrame\(/,/^}/' "$source_file")
[ -n "$body" ] || fail 'ApolloDuoHollaWrapperFrame is present'

# From the early return (frame already inside the band) to the final return.
clamp=$(printf '%s\n' "$body" | awk '
    /CGRectGetMaxX\(frame\) <= maxX\)\) return frame;/ { on = 1; next }
    on && /return frame;/ { exit }
    on { print }')
[ -n "$clamp" ] || fail 'the clamp lines after the early return are present'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/clamp.m" <<EOF
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <math.h>

static CGRect Clamp(CGRect frame, CGFloat minX, CGFloat maxX) {
$clamp
    return frame;
}

static int failures = 0;
static void Expect(const char *name, CGRect frame, CGFloat minX, CGFloat maxX, CGFloat x, CGFloat w) {
    CGRect r = Clamp(frame, minX, maxX);
    if (fabs(r.origin.x - x) > 0.001 || fabs(r.size.width - w) > 0.001) {
        printf("FAIL: %s: got x=%g w=%g, want x=%g w=%g\n", name, r.origin.x, r.size.width, x, w);
        failures++;
    }
}

int main(void) {
    Expect("left edge clipped", CGRectMake(0, 0, 300, 10), 50, 350, 50, 250);
    Expect("right edge clipped", CGRectMake(100, 0, 300, 10), 50, 350, 100, 250);
    Expect("both edges clipped", CGRectMake(0, 0, 400, 10), 50, 350, 50, 300);
    Expect("empty frame left of the band", CGRectMake(0, 0, 0, 10), 20, 350, 20, 0);
    Expect("frame entirely left of the band", CGRectMake(-100, 0, 50, 10), 20, 350, 20, 0);
    Expect("frame entirely right of the band", CGRectMake(400, 0, 50, 10), 20, 350, 400, 0);
    return failures ? 1 : 0;
}
EOF
xcrun --sdk macosx clang -fobjc-arc -framework Foundation -framework CoreGraphics -o "$work/clamp" "$work/clamp.m" ||
    fail 'the copied clamp compiles'
"$work/clamp" || fail 'the clamp gives the overlap with the safe band'

echo "duo_holla_clamp_check passed"
