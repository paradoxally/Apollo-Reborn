#pragma once

// Decisions behind ApolloFeedRowCount.xm, kept free of ObjC so
// tests/feed_row_count_policy_tests.c can exercise every branch on the host.
// A wrong row count inside a Texture batch makes UIKit raise
// NSInternalInconsistencyException, so every input that is unknown or
// unexpected must resolve to "ask Apollo" (the hook's %orig).

#include <stdbool.h>

typedef enum {
    ApolloFeedRowCountWindowOpen = 0,
    ApolloFeedRowCountWindowNotMainThread,
    ApolloFeedRowCountWindowNested,
    ApolloFeedRowCountWindowNoCompletion,
    ApolloFeedRowCountWindowNodeNotLoaded,
    ApolloFeedRowCountWindowNotListAdapter,
    ApolloFeedRowCountWindowNotPostsOwner,
    ApolloFeedRowCountWindowObjectsUnreadable,
    ApolloFeedRowCountWindowPendingUnreadable,
    ApolloFeedRowCountWindowDiffMismatch,
    ApolloFeedRowCountWindowEmpty,
    ApolloFeedRowCountWindowVerdictCount
} ApolloFeedRowCountWindowVerdict;

// Facts gathered when ASTableNode starts a batch right after
// -[IGListIndexPathResult hasChanges] returned YES (only ListAdapter's
// performUpdates asks that question).
typedef struct {
    bool mainThread;
    unsigned batchDepthBefore;
    bool completionPresent;
    bool nodeLoaded;
    bool dataSourceIsListAdapter;
    bool ownerIsPostsViewController;
    long objectsCount;        // adapter's stored `objects`; < 0 when unreadable
    long pendingRowCount;     // Texture's committed rows before this batch; < 0 when unreadable
    long diffInserts;
    long diffDeletes;
} ApolloFeedRowCountWindowInput;

static inline ApolloFeedRowCountWindowVerdict ApolloFeedRowCountDecideWindow(ApolloFeedRowCountWindowInput in) {
    if (!in.mainThread) return ApolloFeedRowCountWindowNotMainThread;
    if (in.batchDepthBefore != 0) return ApolloFeedRowCountWindowNested;
    // performUpdates always hands Texture a completion; the caller-supplied
    // batch path (FriendsViewController) does not.
    if (!in.completionPresent) return ApolloFeedRowCountWindowNoCompletion;
    if (!in.nodeLoaded) return ApolloFeedRowCountWindowNodeNotLoaded;
    if (!in.dataSourceIsListAdapter) return ApolloFeedRowCountWindowNotListAdapter;
    if (!in.ownerIsPostsViewController) return ApolloFeedRowCountWindowNotPostsOwner;
    if (in.objectsCount < 0) return ApolloFeedRowCountWindowObjectsUnreadable;
    if (in.pendingRowCount < 0 || in.diffInserts < 0 || in.diffDeletes < 0) return ApolloFeedRowCountWindowPendingUnreadable;
    // The same equation UIKit enforces after the batch: rows before + inserts -
    // deletes must equal the rows reported afterwards.
    if (in.pendingRowCount + in.diffInserts - in.diffDeletes != in.objectsCount) return ApolloFeedRowCountWindowDiffMismatch;
    // Zero rows means Apollo's empty-view refresh has work to do; let %orig queue it.
    if (in.objectsCount == 0) return ApolloFeedRowCountWindowEmpty;
    return ApolloFeedRowCountWindowOpen;
}

typedef enum {
    ApolloFeedRowCountRowsFast = 0,
    ApolloFeedRowCountRowsNoWindow,
    ApolloFeedRowCountRowsPoisoned,
    ApolloFeedRowCountRowsNotMainThread,
    ApolloFeedRowCountRowsOtherAdapter,
    ApolloFeedRowCountRowsOtherTableNode,
    ApolloFeedRowCountRowsWrongSection,
    ApolloFeedRowCountRowsEmptyViewShown,
    ApolloFeedRowCountRowsObjectsChanged,
    ApolloFeedRowCountRowsVerdictCount
} ApolloFeedRowCountRowsVerdict;

typedef struct {
    bool windowOpen;
    bool windowPoisoned;
    bool mainThread;
    bool sameAdapter;
    bool sameTableNode;
    long section;
    bool emptyViewShown;
    long windowCount;
    long objectsCount;        // re-read at call time; < 0 when unreadable
} ApolloFeedRowCountRowsInput;

static inline ApolloFeedRowCountRowsVerdict ApolloFeedRowCountDecideRows(ApolloFeedRowCountRowsInput in) {
    if (!in.windowOpen) return ApolloFeedRowCountRowsNoWindow;
    if (in.windowPoisoned) return ApolloFeedRowCountRowsPoisoned;
    if (!in.mainThread) return ApolloFeedRowCountRowsNotMainThread;
    if (!in.sameAdapter) return ApolloFeedRowCountRowsOtherAdapter;
    if (!in.sameTableNode) return ApolloFeedRowCountRowsOtherTableNode;
    // ListAdapter reports exactly one section.
    if (in.section != 0) return ApolloFeedRowCountRowsWrongSection;
    // Apollo's skipped empty-view refresh would remove this view; keep it running.
    if (in.emptyViewShown) return ApolloFeedRowCountRowsEmptyViewShown;
    if (in.objectsCount < 0 || in.objectsCount != in.windowCount || in.windowCount <= 0) return ApolloFeedRowCountRowsObjectsChanged;
    return ApolloFeedRowCountRowsFast;
}
