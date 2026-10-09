#!/bin/sh
set -eu

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloFeedRowCount.xm"
build=$(mktemp -d "${TMPDIR:-/tmp}/apollo-feed-row-count.XXXXXX")
trap 'rm -rf "$build"' EXIT INT TERM

fail() {
    printf 'feed_row_count_source_check: %s\n' "$1" >&2
    exit 1
}

xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
    -fsanitize=address,undefined \
    -I "$test_root/src" \
    "$test_root/tests/feed_row_count_policy_tests.c" \
    -o "$build/feed-row-count-tests"
"$build/feed-row-count-tests"

# A wrong row count inside a Texture batch is an uncaught UIKit exception, so
# the hooks must keep failing closed to Apollo's own answer.
grep -Fq 'if (!sWindow.open) return %orig;' "$source_file" || \
    fail 'row-count hook must call Apollo when no window is open'
grep -Fq 'if (verdict != ApolloFeedRowCountRowsFast) {' "$source_file" || \
    fail 'row-count hook must call Apollo for every non-fast verdict'
grep -Fq 'if (!changed || ![NSThread isMainThread]) return changed;' "$source_file" || \
    fail 'the hasChanges arm must be main-thread only'
grep -Fq '[owner isMemberOfClass:ApolloClassPostsViewController]' "$source_file" || \
    fail 'the window must be limited to PostsViewController feeds'
grep -Fq '[adapter isMemberOfClass:ApolloClassListAdapter]' "$source_file" || \
    fail 'the window must be limited to ListAdapter-owned table nodes'
grep -Fq 'if (sWindow.open) sWindow.poisoned = true;' "$source_file" || \
    fail 'a nested batch must poison an open window'
if grep -En 'numberOfRowsInSection:0\]|0x1[0-9a-f]{8}' "$source_file"; then
    fail 'use pendingMap (no initial reload) and no hardcoded Apollo addresses'
fi

echo "feed_row_count_source_check passed"
