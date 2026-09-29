// Host-side checks for ApolloAccountSubscriptions.m: a subscription change Reddit
// confirmed before the account's list loaded is held, then applied once the list
// arrives, and never fabricates a list or leaks onto another account.
#import <Foundation/Foundation.h>
#import "ApolloAccountSubscriptions.h"

@interface FakeUser : NSObject
@property (nonatomic, copy) NSArray *subscribedSubreddits;
@property (nonatomic, copy) NSString *identifier;
@end
@implementation FakeUser
@end

@interface FakeClient : NSObject
@property (nonatomic, strong) FakeUser *currentUser;
@end
@implementation FakeClient
@end

static FakeClient *sActive;
id ApolloActiveAccountClient(void) { return sActive; }

static int sFailures;
#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); sFailures++; } else { printf("PASS: %s\n", msg); } } while (0)

static void Spin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

static FakeClient *Client(NSArray *list) {
    FakeClient *c = [FakeClient new];
    c.currentUser = [FakeUser new];
    c.currentUser.identifier = @"abc";
    c.currentUser.subscribedSubreddits = list;
    return c;
}

int main(void) {
    @autoreleasepool {
        __block int posts = 0;
        [[NSNotificationCenter defaultCenter] addObserverForName:ApolloSubscribedSubredditsUpdatedNotification object:nil queue:nil
                                                      usingBlock:^(__unused NSNotification *n) { posts++; }];
        BOOL subscribed = NO;

        sActive = Client(@[@"Apple"]);
        ApolloAccountApplySubscriptionChange(@"r/AskReddit", YES);
        CHECK([sActive.currentUser.subscribedSubreddits containsObject:@"AskReddit"] && posts == 1, "loaded list is updated and announced at once");

        sActive = Client(nil);
        posts = 0;
        ApolloAccountApplySubscriptionChange(@"AskReddit", YES);
        CHECK(sActive.currentUser.subscribedSubreddits == nil && posts == 0, "unloaded list is not fabricated from one name");
        CHECK(!ApolloAccountSubscriptionListState(@"AskReddit", &subscribed), "state stays unknown until the list loads");

        posts = 0;
        sActive.currentUser.subscribedSubreddits = @[@"Apple"];
        CHECK(sActive.currentUser.subscribedSubreddits.count == 1, "nothing is applied inside Apollo's own setter call");
        Spin();
        NSArray *list = sActive.currentUser.subscribedSubreddits;
        CHECK(list.count == 2 && [list containsObject:@"Apple"] && [list containsObject:@"AskReddit"] && posts == 1,
              "held change lands once Apollo assigns the loaded list, with no broadcast needed");

        sActive = Client(nil);
        ApolloAccountApplySubscriptionChange(@"Swift", YES);
        ApolloAccountApplySubscriptionChange(@"Swift", NO);
        ApolloAccountApplySubscriptionChange(@"iOS", YES);
        sActive.currentUser.subscribedSubreddits = @[@"Swift"];
        CHECK(ApolloAccountSubscriptionListState(@"iOS", &subscribed) && subscribed, "a lookup applies held changes once the list is there");
        CHECK(![sActive.currentUser.subscribedSubreddits containsObject:@"Swift"], "the latest held change per name wins");

        FakeClient *first = Client(nil);
        sActive = first;
        ApolloAccountApplySubscriptionChange(@"Rust", YES);
        FakeClient *second = Client(@[@"Go"]);
        sActive = second;
        CHECK(ApolloAccountSubscriptionListState(@"Rust", &subscribed) && !subscribed, "a held change never lands on another account");
        Spin();
        CHECK(![second.currentUser.subscribedSubreddits containsObject:@"Rust"], "assigning another account's list leaves the held change alone");
        first.currentUser.subscribedSubreddits = @[];
        Spin();
        CHECK([first.currentUser.subscribedSubreddits containsObject:@"Rust"], "it lands on its own account once that list loads, even while inactive");

        sActive = Client(@[@"AskReddit"]);
        posts = 0;
        ApolloAccountApplySubscriptionChange(@"askreddit", YES);
        CHECK(posts == 0 && sActive.currentUser.subscribedSubreddits.count == 1, "an agreeing list is left alone");
    }
    if (sFailures) { fprintf(stderr, "%d failure(s)\n", sFailures); return 1; }
    printf("account_subscriptions_tests passed\n");
    return 0;
}
