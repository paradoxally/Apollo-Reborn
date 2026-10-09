#!/bin/sh
set -eu

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloFastStringContains.m"
build=$(mktemp -d "${TMPDIR:-/tmp}/apollo-fast-contains.XXXXXX")
trap 'rm -rf "$build"' EXIT INT TERM

fail() {
    printf 'fast_string_contains_source_check: %s\n' "$1" >&2
    exit 1
}

# Compares the fast path with the host's Foundation `contains`, which is the
# same swift-foundation implementation the device runs.
cp "$test_root/tests/fast_string_contains_tests.swift" "$build/main.swift"
xcrun --sdk macosx swiftc -O \
    -module-name ApolloFastStringContainsTests \
    "$test_root/src/ApolloFastStringContains.swift" \
    "$build/main.swift" \
    -o "$build/fast-string-contains-tests"
"$build/fast-string-contains-tests"

grep -Fq 'if (selfType == sStringMetadata && otherType == sStringMetadata) {' "$source_file" || \
    fail 'only String/String calls may take the fast path'
grep -Fq 'if (decided >= 0) return decided == 1;' "$source_file" || \
    fail 'a deferred decision must fall through to Foundation'
grep -Fq 'class_getImageName(ApolloClassPostsViewController)' "$source_file" || \
    fail 'the rebind must target the image that defines Apollo'"'"'s classes (LiveContainer loads Apollo as a dylib)'
if grep -Fq 'MH_EXECUTE' "$source_file"; then
    fail 'do not pick the image by MH_EXECUTE; under LiveContainer that is the host'
fi
if grep -En 'rebind_symbols\(' "$source_file"; then
    fail 'use rebind_symbols_image on Apollo only, never a global rebind'
fi

echo "fast_string_contains_source_check passed"
