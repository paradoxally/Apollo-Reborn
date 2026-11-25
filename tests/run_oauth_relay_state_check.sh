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

printf '%s\n' "$hook" | grep -F -q 'NSString *expectedState = sRelayedSafariSignInState;' ||
    fail 'the expected state is the one captured when the relay was armed'

# The relay is armed in -[SFSafariViewController initWithURL:configuration:],
# which returns before kARSafariFallbackURL is set (that key marks a page to
# swap for the sheet), so the state has to be captured right there.
init=$(awk '/^- \(instancetype\)initWithURL:\(NSURL \*\)URL configuration:/,/^}/' "$source_file")
arm_line=$(printf '%s\n' "$init" | grep -n -F 'sRelayedSafariSignInPage = result;' | cut -d: -f1)
capture_line=$(printf '%s\n' "$init" | grep -n -F 'sRelayedSafariSignInState = [ApolloOAuthStateOfURL(URL) copy];' | cut -d: -f1)
[ -n "$arm_line" ] && [ -n "$capture_line" ] || fail 'arming the relay captures the authorize URL state'
[ "$((capture_line - arm_line))" -le 2 ] || fail 'the state is captured alongside the relayed page'

# Every place that disarms the relay forgets its state too.
disarms=$(grep -c -F 'sRelayedSafariSignInRedirectURI = nil;' "$source_file")
clears=$(grep -c -F 'sRelayedSafariSignInState = nil;' "$source_file")
[ "$disarms" -eq "$clears" ] || fail "each relay disarm clears its state ($disarms disarms, $clears clears)"

echo "oauth_relay_state_check passed"
