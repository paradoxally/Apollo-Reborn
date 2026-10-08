#!/bin/sh
# Host-side checks for ApolloAccountSubscriptions.m. The module is compiled next to
# stub ApolloCommon.h / ApolloAccountCredentials.h (quote includes resolve beside the
# source first), because the real ApolloCommon.h pulls in UIKit.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/apollo-account-subscriptions.XXXXXX")
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
cp "$repo/src/ApolloAccountSubscriptions.m" "$repo/src/ApolloAccountSubscriptions.h" "$build/"
# Intentional no-op ApolloLog: the harness links no logging and no check reads log output.
printf '#import <Foundation/Foundation.h>\n#define ApolloLog(...) do {} while (0)\n' > "$build/ApolloCommon.h"
printf '#import <Foundation/Foundation.h>\nid ApolloActiveAccountClient(void);\n' > "$build/ApolloAccountCredentials.h"
cp "$repo/tests/account_subscriptions_tests.m" "$build/"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -fsanitize=address,undefined -framework Foundation -I "$build" \
    "$build/ApolloAccountSubscriptions.m" "$build/account_subscriptions_tests.m" -o "$build/tests"
"$build/tests"
