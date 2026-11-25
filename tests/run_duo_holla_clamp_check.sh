#!/bin/sh
set -eu

# ApolloDuoHollaWrapperFrame clamps the Saved! wrapper to the safe band. The
# right edge has to be read before the origin moves: read after, it is shifted
# right by the clipped amount and the wrapper grows instead of shrinking.

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloDuoRail.xm"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

body=$(awk '/^static CGRect ApolloDuoHollaWrapperFrame\(/,/^}/' "$source_file")
[ -n "$body" ] || fail 'ApolloDuoHollaWrapperFrame is present'

right_line=$(printf '%s\n' "$body" | grep -n -F 'CGFloat right = MIN(CGRectGetMaxX(frame), maxX);' | cut -d: -f1)
origin_line=$(printf '%s\n' "$body" | grep -n -F 'frame.origin.x = MAX(CGRectGetMinX(frame), minX);' | cut -d: -f1)
[ -n "$right_line" ] && [ -n "$origin_line" ] || fail 'the clamp reads the right edge and moves the origin'
[ "$right_line" -lt "$origin_line" ] || fail 'the right edge is read before the origin moves'
printf '%s\n' "$body" | grep -F -q 'frame.size.width = right - frame.origin.x;' ||
    fail 'the width ends at the right edge read before the move'

echo "duo_holla_clamp_check passed"
