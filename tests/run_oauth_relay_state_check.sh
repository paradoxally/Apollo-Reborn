#!/bin/sh
set -eu

# The Safari sign-in relay (SceneDelegate scene:openURLContexts:) hands a
# redirect to the sign-in session. Any app can open the redirect URI, so the
# relay must only take a callback whose OAuth state matches the authorize URL
# the Safari page loaded, and must check it before it disarms itself, so a
# forged callback can't use up the relay ahead of Reddit's real one.

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/Tweak.xm"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

hook=$(awk '/^- \(void\)scene:\(UIScene \*\)scene openURLContexts:/,/^}/' "$source_file")
[ -n "$hook" ] || fail 'the SceneDelegate openURLContexts relay hook is present'

check_line=$(printf '%s\n' "$hook" | grep -n -F 'ApolloOAuthStateOfURL(callbackURL)' | head -1 | cut -d: -f1)
disarm_line=$(printf '%s\n' "$hook" | grep -n -F 'sRelayedSafariSignInPage = nil;' | head -1 | cut -d: -f1)
complete_line=$(printf '%s\n' "$hook" | grep -n -F 'authCompletion(callbackURL, nil)' | head -1 | cut -d: -f1)
[ -n "$check_line" ] || fail 'the relay compares the callback state'
[ -n "$disarm_line" ] && [ -n "$complete_line" ] || fail 'the relay still disarms and completes'
[ "$check_line" -lt "$disarm_line" ] || fail 'the state is checked before the relay disarms'
[ "$check_line" -lt "$complete_line" ] || fail 'the state is checked before the sign-in completes'

printf '%s\n' "$hook" | grep -F -q 'ApolloOAuthStateOfURL(objc_getAssociatedObject(page, &kARSafariFallbackURL))' ||
    fail 'the expected state comes from the authorize URL the Safari page loaded'

echo "oauth_relay_state_check passed"
