//
//  ApolloAICloudClient.h
//  Apollo-Reborn
//
//  OpenAI-compatible cloud backend for AI summaries (bring-your-own-key).
//  Speaks the chat-completions wire format with SSE streaming against any
//  compatible endpoint (OpenAI, OpenRouter, Groq, ...). Exposes the same verb
//  shape as the on-device ApolloFoundationModels bridge so ApolloAISummary.xm
//  can route a request to either backend interchangeably.
//
//  Errors are mapped onto the bridge's stable code space (domain
//  ApolloAICloudErrorDomain): 6 = cancelled, 8 = context window exceeded,
//  plus cloud-specific codes 11 = auth (bad key), 12 = network/unreachable,
//  13 = provider/protocol error, 14 = rate limited. Cloud deliberately never
//  emits code 9 (the on-device transient-concurrency code) so the FM retry
//  loop in ApolloAISummary.xm cannot spin on cloud failures.
//

#import <Foundation/Foundation.h>

__BEGIN_DECLS

// YES when a cloud API key and base URL are configured (sCloudAIAPIKey /
// sCloudAIBaseURL). Gates the cloud-first path and the raised input caps.
BOOL ApolloAICloudConfigured(void);

extern NSString *const ApolloAICloudErrorDomain;

typedef NS_ENUM(NSInteger, ApolloAICloudErrorCode) {
    ApolloAICloudErrorCancelled = 6,       // matches the bridge's navigation-cancel code
    ApolloAICloudErrorContextWindow = 8,   // matches the bridge's context-window code
    ApolloAICloudErrorAuth = 11,
    ApolloAICloudErrorNetwork = 12,
    ApolloAICloudErrorProvider = 13,
    ApolloAICloudErrorRateLimited = 14,
};

__END_DECLS

@interface ApolloAICloudClient : NSObject

+ (instancetype)shared;

// Mirrors the bridge's summarize verb: `onPartial` fires repeatedly with the
// CUMULATIVE text as it streams; `onComplete` fires exactly once with the final
// text (or an error). Both callbacks are delivered on the main thread.
- (void)summarize:(NSString *)text
       identifier:(NSString *)identifier
     instructions:(NSString *)instructions
maximumResponseTokens:(NSInteger)maximumResponseTokens
        onPartial:(void (^)(NSString *partial))onPartial
       onComplete:(void (^)(NSString *final, NSError *error))onComplete;

// Cancels the in-flight request for `identifier`, if any. The request's
// onComplete fires once with error code 6 (cancelled).
- (void)cancelRequest:(NSString *)identifier;

@end
