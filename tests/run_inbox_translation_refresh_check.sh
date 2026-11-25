#!/bin/sh
set -eu

# A Translation settings change re-derives every inbox row we've seen. Texture
# keeps a row's node loaded after it scrolls away, so that set grows with the
# inbox scrolled through. Only rows in the preload range may request a
# translation there; the others request from didEnterPreloadState on return.

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloTranslation.xm"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

body=$(awk '/^static void ApolloInboxRefreshAllCells\(void\)/,/^}/' "$source_file")
[ -n "$body" ] || fail 'ApolloInboxRefreshAllCells is present'
printf '%s\n' "$body" | grep -F -q '@selector(isInPreloadState)' ||
    fail 'the refresh asks whether a row is in the preload range'
printf '%s\n' "$body" | grep -F -q 'if (inRange) ApolloInboxMaybeTranslateCell(cell);' ||
    fail 'only rows in range request a translation'
[ "$(printf '%s\n' "$body" | grep -c 'ApolloInboxMaybeTranslateCell(cell)')" -eq 1 ] ||
    fail 'no ungated translation request is left in the refresh'

hook=$(awk '/^%hook _TtC6Apollo13InboxCellNode/,/^%end/' "$source_file" |
       awk '/^- \(void\)didEnterPreloadState/,/^}/')
printf '%s\n' "$hook" | grep -F -q 'ApolloInboxMaybeTranslateCell(cell)' ||
    fail 'rows coming back into range still request from didEnterPreloadState'

echo "inbox_translation_refresh_check passed"
