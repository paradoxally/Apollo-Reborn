#include <stdio.h>
#include <stdlib.h>

#include "ApolloFeedRowCountPolicy.h"

#define CHECK(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "feed_row_count_policy_tests: %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        exit(1); \
    } \
} while (0)

static ApolloFeedRowCountWindowInput page_load(void) {
    return (ApolloFeedRowCountWindowInput){
        .mainThread = true,
        .batchDepthBefore = 0,
        .completionPresent = true,
        .nodeLoaded = true,
        .dataSourceIsListAdapter = true,
        .ownerIsPostsViewController = true,
        .objectsCount = 52,
        .pendingRowCount = 26,
        .diffInserts = 26,
        .diffDeletes = 0,
    };
}

static ApolloFeedRowCountRowsInput row_call(void) {
    return (ApolloFeedRowCountRowsInput){
        .windowOpen = true,
        .windowPoisoned = false,
        .mainThread = true,
        .sameAdapter = true,
        .sameTableNode = true,
        .section = 0,
        .emptyViewShown = false,
        .windowCount = 52,
        .objectsCount = 52,
    };
}

static void test_window(void) {
    ApolloFeedRowCountWindowInput in = page_load();
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowOpen);

    in = page_load(); in.mainThread = false;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNotMainThread);

    in = page_load(); in.batchDepthBefore = 1;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNested);

    in = page_load(); in.completionPresent = false;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNoCompletion);

    in = page_load(); in.nodeLoaded = false;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNodeNotLoaded);

    in = page_load(); in.dataSourceIsListAdapter = false;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNotListAdapter);

    in = page_load(); in.ownerIsPostsViewController = false;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowNotPostsOwner);

    in = page_load(); in.objectsCount = -1;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowObjectsUnreadable);

    in = page_load(); in.pendingRowCount = -1;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowPendingUnreadable);

    in = page_load(); in.diffInserts = -1;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowPendingUnreadable);

    // One row off in either direction must never open the window.
    in = page_load(); in.objectsCount = 53;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowDiffMismatch);
    in = page_load(); in.objectsCount = 51;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowDiffMismatch);

    // Hiding a post: one delete, nothing inserted.
    in = page_load(); in.pendingRowCount = 52; in.diffInserts = 0; in.diffDeletes = 1; in.objectsCount = 51;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowOpen);

    // Pull to refresh replacing the whole page.
    in = page_load(); in.pendingRowCount = 260; in.diffInserts = 26; in.diffDeletes = 260; in.objectsCount = 26;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowOpen);

    // First load into an empty table.
    in = page_load(); in.pendingRowCount = 0; in.diffInserts = 26; in.objectsCount = 26;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowOpen);

    // Everything filtered away: Apollo must show its empty view.
    in = page_load(); in.pendingRowCount = 26; in.diffInserts = 0; in.diffDeletes = 26; in.objectsCount = 0;
    CHECK(ApolloFeedRowCountDecideWindow(in) == ApolloFeedRowCountWindowEmpty);
}

static void test_rows(void) {
    ApolloFeedRowCountRowsInput in = row_call();
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsFast);

    in = row_call(); in.windowOpen = false;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsNoWindow);

    in = row_call(); in.windowPoisoned = true;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsPoisoned);

    in = row_call(); in.mainThread = false;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsNotMainThread);

    in = row_call(); in.sameAdapter = false;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsOtherAdapter);

    in = row_call(); in.sameTableNode = false;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsOtherTableNode);

    in = row_call(); in.section = 1;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsWrongSection);
    in = row_call(); in.section = -1;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsWrongSection);

    in = row_call(); in.emptyViewShown = true;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsEmptyViewShown);

    in = row_call(); in.objectsCount = 53;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsObjectsChanged);
    in = row_call(); in.objectsCount = -1;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsObjectsChanged);
    in = row_call(); in.windowCount = 0; in.objectsCount = 0;
    CHECK(ApolloFeedRowCountDecideRows(in) == ApolloFeedRowCountRowsObjectsChanged);
}

int main(void) {
    test_window();
    test_rows();
    printf("feed_row_count_policy_tests passed\n");
    return 0;
}
