// Shares compiled NSRegularExpression instances across identical (pattern, options) requests.
//
// Apollo compiles the same patterns again for every post it processes, on the main thread,
// while the feed scrolls; ICU's compile is most of that cost. NSRegularExpression is immutable
// and documented thread-safe, so one compiled instance can serve every caller.
//
// This module must stay ahead of every other NSRegularExpression initWithPattern hook in the
// Makefile: the first-installed hook is the innermost, so the cache only ever wraps the real
// compile and the pattern-rewriting hooks above it (ApolloMedia, ApolloSportsClips,
// ApolloRedgifsSubdomainFix) still see and rewrite every request.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ApolloCommon.h"

static NSCache<NSString *, NSRegularExpression *> *ApolloRegexCompileCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        // Patterns built per item (usernames, subreddit names) would otherwise grow it without bound.
        cache.countLimit = 256;
    });
    return cache;
}

%hook NSRegularExpression

- (instancetype)initWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {
    // A subclass may carry state of its own, so only plain instances are shared.
    if (!pattern || object_getClass(self) != [NSRegularExpression class]) return %orig;

    NSString *key = [NSString stringWithFormat:@"%lu|%@", (unsigned long)options, pattern];
    NSCache *cache = ApolloRegexCompileCache();
    NSRegularExpression *cached = [cache objectForKey:key];
    if (cached) return cached;

    NSRegularExpression *compiled = %orig;
    if (compiled) [cache setObject:compiled forKey:key];
    return compiled;
}

%end

%ctor {
    %init;
}
