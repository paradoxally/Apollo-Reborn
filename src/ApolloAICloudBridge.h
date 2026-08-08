//
//  ApolloAICloudBridge.h
//  Cloud backend for AI summaries: an OpenAI-compatible chat-completions client
//  (OpenAI / OpenRouter / Google Gemini / custom base URL) with SSE streaming.
//
//  Mirrors the @objc surface of ApolloFoundationModels.swift exactly, so
//  ApolloAIBridge() in ApolloAISummary.xm can return either backend and every
//  call site works unchanged. Callbacks are always delivered on the main thread.
//
//  Error contract (NSError code, matching the FoundationModels bridge so
//  ApolloAIFriendlyError / the transient-retry check keep working):
//    5  = unknown
//    6  = cancelled (callers ignore silently)
//    8  = input too long for the model's context window
//    11 = auth/billing rejected (bad API key, out of credits)  [cloud-only]
//    12 = service unreachable / rejected request                 [cloud-only]
//    13 = model spent the whole response on internal reasoning,
//         leaving no visible summary                            [cloud-only]
//    14 = requested model is unavailable                        [cloud-only]
//    15 = provider quota/rate limit exhausted                   [cloud-only]
//  Code 9 (transient, retried in an unbounded loop by the caller) is never
//  emitted: a persistent HTTP 429/5xx would loop forever against a paid API.
//  Transient HTTP errors get ONE internal retry, then surface the final
//  provider failure through the mapped cloud error code above.
//
//  Two independent one-shot internal retries exist, and neither can chain into
//  the other more than once:
//    - transient status (429/5xx)  -> same request re-issued after a short delay
//    - HTTP 400 naming a parameter -> request re-issued with ONLY that parameter
//      adjusted (token-cap key swap, reasoning_effort remap/drop, temperature
//      drop), which is what lets OpenAI's reasoning models and arbitrary
//      self-hosted servers work without the user tuning anything.
//

#import <Foundation/Foundation.h>

extern NSString *const ApolloAICloudBridgeErrorDomain;

#ifdef __cplusplus
extern "C" {
#endif

// Effective model for the active cloud provider: the user's stored model if
// set, else the per-provider default (nil for "custom", which has no default).
// Exposed so settings can show the default as a placeholder.
NSString *ApolloAICloudDefaultModelForProvider(NSString *provider);
NSString *ApolloAICloudEffectiveModel(void);

// YES for one of apple|openai|openrouter|gemini|custom. Single source of truth
// for the sanitize step every entry point does (launch load, backup restore,
// settings picker).
BOOL ApolloAIProviderIsKnown(NSString *provider);

// YES when the active provider is a cloud one (i.e. anything but "apple").
BOOL ApolloAICloudProviderSelected(void);

// YES when the active cloud provider has everything it needs to run a request.
// Equivalent to availabilityStatus == 0, without instantiating the bridge.
BOOL ApolloAICloudConfigured(void);

// YES when the active provider's endpoint resolves to a usable URL. Distinct
// from ApolloAICloudConfigured(): only "custom" can fail this, and settings
// shows a specific "Invalid Base URL" status for it.
BOOL ApolloAICloudBaseURLIsValid(void);

// One-shot migration of this fork's pre-#674 single-endpoint cloud settings
// (AICloudAPIKey/BaseURL/Model) onto the per-provider keys. Call once at launch
// BEFORE reading the provider defaults. Idempotent.
void ApolloAIMigrateLegacyCloudKeys(void);

#ifdef __cplusplus
}
#endif

@interface ApolloAICloudBridge : NSObject

+ (instancetype)shared;

// 0 = configured and ready; 4 = not configured (missing key / base URL) —
// deliberately reuses the FM "framework absent" status so ApolloAISummary.xm's
// existing status==4 silent-skip path handles the unconfigured state.
- (NSInteger)availabilityStatus;
- (BOOL)isModelAvailable;

// Prewarm has no meaning over HTTP; both are no-ops kept for surface parity.
- (void)prepareSession:(NSString *)identifier instructions:(NSString *)instructions;
- (void)discardPreparedSession:(NSString *)identifier;

// Cancels the in-flight request for this identifier (completion fires once
// with error code 6, which callers ignore).
- (void)cancelRequest:(NSString *)identifier;

- (void)summarize:(NSString *)text
       identifier:(NSString *)identifier
     instructions:(NSString *)instructions
maximumResponseTokens:(NSInteger)maximumResponseTokens
        onPartial:(void (^)(NSString *partial))onPartial
       onComplete:(void (^)(NSString *final, NSError *error))onComplete;

@end
