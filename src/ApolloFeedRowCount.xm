#import "ApolloCommon.h"
#import "ApolloClasses.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloFeedRowCountPolicy.h"

// When a page of posts lands, ListAdapter.performUpdates stores the freshly
// built post list in its `objects` ivar, diffs it, and runs a Texture batch.
// Inside that batch Texture asks -tableNode:numberOfRowsInSection:, and Apollo
// answers by rebuilding the whole list again (every loaded post: regex, title
// lowercasing, keyword filters) only to return its count, then queues one more
// full rebuild to refresh the empty view. Inside that one batch the count is
// already in `objects`, so the feed answers from there and skips both.
//
// Only PostsViewController feeds are covered: their list builder was audited
// to have no per-call side effects beyond one-time migrations that the
// performUpdates rebuild has already run. FriendsViewController drives the
// same adapter through a second batch path whose update block is supplied by
// the caller and may edit the model, which is why the window opens only after
// -[IGListIndexPathResult hasChanges]: performUpdates is the only caller of it
// in Apollo, and it goes straight from a YES into this batch.

@interface IGListIndexPathResult : NSObject
@property (nonatomic, copy, readonly) NSArray *inserts;
@property (nonatomic, copy, readonly) NSArray *deletes;
@end

@interface ASTableNode : NSObject
@property (nonatomic, weak) id dataSource;
@property (nonatomic, readonly, assign, getter=isNodeLoaded) BOOL nodeLoaded;
@end

typedef struct {
    bool armed;
    long inserts;
    long deletes;
} ApolloFRCArm;

typedef struct {
    bool open;
    bool poisoned;
    const void *adapter;
    const void *tableNode;
    long count;
} ApolloFRCWindow;

// Main thread only: hasChanges, Texture batches and Texture's data source
// calls all run there, and every entry point checks before touching these.
static ApolloFRCArm sArm;
static ApolloFRCWindow sWindow;
static unsigned sBatchDepth;

static ptrdiff_t sObjectsOffset = -1;
static ptrdiff_t sEmptyViewOffset = -1;

static long ApolloFRCObjectsCount(id adapter) {
    if (sObjectsOffset < 0 || !adapter) return -1;
    void *buffer = *(void **)((uint8_t *)(__bridge void *)adapter + sObjectsOffset);
    if (!buffer) return -1;
    return (long)ApolloSwiftArrayCount(buffer);
}

static bool ApolloFRCEmptyViewShown(id adapter) {
    if (sEmptyViewOffset < 0 || !adapter) return true;
    return *(void **)((uint8_t *)(__bridge void *)adapter + sEmptyViewOffset) != NULL;
}

static long ApolloFRCPendingRowCount(id tableNode) {
    SEL dataControllerSel = @selector(dataController);
    SEL pendingMapSel = @selector(pendingMap);
    SEL itemsSel = @selector(numberOfItemsInSection:);
    if (![tableNode respondsToSelector:dataControllerSel]) return -1;
    id dataController = ((id (*)(id, SEL))objc_msgSend)(tableNode, dataControllerSel);
    if (![dataController respondsToSelector:pendingMapSel]) return -1;
    id pendingMap = ((id (*)(id, SEL))objc_msgSend)(dataController, pendingMapSel);
    if (![pendingMap respondsToSelector:itemsSel]) return -1;
    return (long)((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(pendingMap, itemsSel, 0);
}

// Restores the depth and closes a window this frame opened on every exit,
// including an exception unwinding out of %orig.
struct ApolloFRCBatchScope {
    bool openedWindow = false;
    ApolloFRCBatchScope() { sBatchDepth++; }
    ~ApolloFRCBatchScope() {
        sBatchDepth--;
        if (openedWindow) sWindow = (ApolloFRCWindow){0};
    }
};

%hook IGListIndexPathResult

- (BOOL)hasChanges {
    BOOL changed = %orig;
    if (!changed || ![NSThread isMainThread]) return changed;
    sArm = (ApolloFRCArm){
        .armed = true,
        .inserts = (long)self.inserts.count,
        .deletes = (long)self.deletes.count,
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        sArm.armed = false;
    });
    return changed;
}

%end

%hook ASTableNode

- (void)performBatchAnimated:(BOOL)animated updates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    if (![NSThread isMainThread]) {
        %orig;
        return;
    }
    ApolloFRCArm arm = sArm;
    sArm.armed = false;
    if (sWindow.open) sWindow.poisoned = true;

    unsigned depthBefore = sBatchDepth;
    ApolloFRCBatchScope scope;
    if (arm.armed) {
        ApolloFeedRowCountWindowInput input = {
            .mainThread = true,
            .batchDepthBefore = depthBefore,
            .completionPresent = completion != nil,
            .nodeLoaded = false,
            .objectsCount = -1,
            .pendingRowCount = -1,
            .diffInserts = arm.inserts,
            .diffDeletes = arm.deletes,
        };
        id adapter = nil;
        if (depthBefore == 0 && completion) {
            input.nodeLoaded = self.isNodeLoaded;
            adapter = input.nodeLoaded ? self.dataSource : nil;
            input.dataSourceIsListAdapter = ApolloClassListAdapter && [adapter isMemberOfClass:ApolloClassListAdapter];
            if (input.dataSourceIsListAdapter) {
                id owner = ApolloReadSwiftWeakObjectIvar(adapter, "dataSource");
                input.ownerIsPostsViewController = ApolloClassPostsViewController && [owner isMemberOfClass:ApolloClassPostsViewController];
            }
            if (input.ownerIsPostsViewController) {
                input.objectsCount = ApolloFRCObjectsCount(adapter);
                input.pendingRowCount = ApolloFRCPendingRowCount(self);
            }
        }
        ApolloFeedRowCountWindowVerdict verdict = ApolloFeedRowCountDecideWindow(input);
        if (verdict == ApolloFeedRowCountWindowOpen) {
            sWindow = (ApolloFRCWindow){
                .open = true,
                .adapter = (__bridge const void *)adapter,
                .tableNode = (__bridge const void *)self,
                .count = input.objectsCount,
            };
            scope.openedWindow = true;
        } else if (input.dataSourceIsListAdapter) {
            ApolloLog(@"[FeedRowCount] batch not covered: verdict=%d objects=%ld pending=%ld +%ld -%ld",
                      (int)verdict, input.objectsCount, input.pendingRowCount, arm.inserts, arm.deletes);
        }
    }
    %orig;
}

%end

%hook _TtC6Apollo11ListAdapter

- (long long)tableNode:(id)tableNode numberOfRowsInSection:(long long)section {
    if (!sWindow.open) return %orig;
    bool mainThread = [NSThread isMainThread];
    bool sameAdapter = mainThread && (__bridge const void *)self == sWindow.adapter;
    ApolloFeedRowCountRowsInput input = {
        .windowOpen = true,
        .windowPoisoned = sWindow.poisoned,
        .mainThread = mainThread,
        .sameAdapter = sameAdapter,
        .sameTableNode = mainThread && (__bridge const void *)tableNode == sWindow.tableNode,
        .section = (long)section,
        .emptyViewShown = sameAdapter ? ApolloFRCEmptyViewShown(self) : true,
        .windowCount = sWindow.count,
        .objectsCount = sameAdapter ? ApolloFRCObjectsCount(self) : -1,
    };
    ApolloFeedRowCountRowsVerdict verdict = ApolloFeedRowCountDecideRows(input);
    if (verdict != ApolloFeedRowCountRowsFast) {
        ApolloLog(@"[FeedRowCount] row count via Apollo: verdict=%d", (int)verdict);
        return %orig;
    }
    return sWindow.count;
}

%end

%ctor {
    if (!ApolloClassListAdapter || !ApolloClassPostsViewController) return;
    sObjectsOffset = ApolloIvarOffset(ApolloClassListAdapter, "objects");
    sEmptyViewOffset = ApolloIvarOffset(ApolloClassListAdapter, "emptyView");
    if (sObjectsOffset < 0 || sEmptyViewOffset < 0) {
        ApolloLog(@"[FeedRowCount] ListAdapter ivars missing (objects=%td emptyView=%td); hooks not installed",
                  sObjectsOffset, sEmptyViewOffset);
        return;
    }
    %init;
}
