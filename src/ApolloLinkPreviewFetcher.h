#import <Foundation/Foundation.h>

#import "ApolloLinkPreviewModel.h"

@interface ApolloLinkPreviewFetcher : NSObject

+ (void)requestPreviewForURL:(NSURL *)url completion:(void (^)(ApolloLinkPreview *preview))completion;
+ (BOOL)isTwitterURL:(NSURL *)url;
// YES when a cached preview is a weak stand-in (bot-wall page, slug/favicon
// fallback, stub academic entry) that deserves one refetch attempt this
// session. Consumes the per-URL retry token when it returns YES.
+ (BOOL)shouldRetryWeakCachedPreview:(ApolloLinkPreview *)cached forURL:(NSURL *)url;

@end

// Decode HTML entities (named + numeric, e.g. &laquo;->«, &raquo;->», &#8230;->…)
// for display-time callers in other translation units. The fetcher decodes these
// when it first stores metadata, but cached and *translated* link-card text bypass
// that path and would otherwise render raw — so the render choke point decodes too.
FOUNDATION_EXPORT NSString *ApolloLinkPreviewDecodeEntities(NSString *string);
