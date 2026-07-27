//
//  ApolloAICloudBridge.m
//  See ApolloAICloudBridge.h for the surface/error contract. All internal state
//  is confined to a serial queue that doubles as the NSURLSession delegate
//  queue, so delegate callbacks and public entry points never race.
//
//  Provider shaping: OpenRouter and Gemini have provider-specific reasoning
//  controls and are otherwise sent the plain OpenAI chat-completions shape.
//  OpenAI and "custom" instead go through the model-family shaping below
//  (max_completion_tokens + a reasoning_effort floor for gpt-5*/o-series,
//  temperature=0 otherwise), because OpenAI's reasoning models reject
//  `max_tokens` outright and self-hosted servers vary. Anything the shaping
//  gets wrong is repaired by the one-shot targeted 400 retry.
//
//  Privacy: never log the API key, the request body, or any streamed text —
//  diagnostics are identifier/status/byte-count only, matching the
//  "never log generated text" discipline in ApolloAISummary.xm.
//

#import "ApolloAICloudBridge.h"
#import "ApolloCommon.h"
#import "ApolloState.h"
#import "UserDefaultConstants.h"

NSString *const ApolloAICloudBridgeErrorDomain = @"ApolloAICloudBridge";

// Error codes shared with the FoundationModels bridge contract.
static const NSInteger kCloudErrorCancelled = 6;
static const NSInteger kCloudErrorContextWindow = 8;
static const NSInteger kCloudErrorAuth = 11;
static const NSInteger kCloudErrorService = 12;
static const NSInteger kCloudErrorReasoningOnly = 13;
static const NSInteger kCloudErrorRateLimited = 14;

// Providers can return large error pages; keep enough for diagnostics and the
// non-streamed JSON fallback without buffering a runaway body.
static const NSUInteger kCloudMaxBufferedBody = 512 * 1024;

#pragma mark - Provider configuration

BOOL ApolloAIProviderIsKnown(NSString *provider) {
    return [provider isEqualToString:@"apple"] || [provider isEqualToString:@"openai"] ||
           [provider isEqualToString:@"openrouter"] || [provider isEqualToString:@"gemini"] ||
           [provider isEqualToString:@"custom"];
}

BOOL ApolloAICloudProviderSelected(void) {
    return sAISummaryProvider.length > 0 && ![sAISummaryProvider isEqualToString:@"apple"];
}

NSString *ApolloAICloudDefaultModelForProvider(NSString *provider) {
    if ([provider isEqualToString:@"openai"]) return @"gpt-5.4-mini";
    if ([provider isEqualToString:@"openrouter"]) return @"meta-llama/llama-3.3-70b-instruct:free";
    if ([provider isEqualToString:@"gemini"]) return @"gemini-2.5-flash";
    return nil; // custom: no sensible default, the user must name a model
}

static NSString *CloudAPIKey(void) {
    if ([sAISummaryProvider isEqualToString:@"openai"]) return sOpenAIAPIKey;
    if ([sAISummaryProvider isEqualToString:@"openrouter"]) return sOpenRouterAPIKey;
    if ([sAISummaryProvider isEqualToString:@"gemini"]) return sGeminiAPIKey;
    if ([sAISummaryProvider isEqualToString:@"custom"]) return sCustomAIAPIKey;
    return nil;
}

NSString *ApolloAICloudEffectiveModel(void) {
    NSString *stored = nil;
    if ([sAISummaryProvider isEqualToString:@"openai"]) stored = sOpenAIAIModel;
    else if ([sAISummaryProvider isEqualToString:@"openrouter"]) stored = sOpenRouterAIModel;
    else if ([sAISummaryProvider isEqualToString:@"gemini"]) stored = sGeminiAIModel;
    else if ([sAISummaryProvider isEqualToString:@"custom"]) stored = sCustomAIModel;
    return stored.length > 0 ? stored : ApolloAICloudDefaultModelForProvider(sAISummaryProvider);
}

#pragma mark Custom base URL safety

// YES only for a literal dotted-quad IPv4 address: exactly four all-numeric
// octets, each 0-255, no leading zeros (inet-style resolvers treat "010" as
// octal, so "010.1.2.3" could connect somewhere other than 10.1.2.3).
// Hostnames like "10.evil.com" or "127.0.0.1.evil.com" must NOT parse — they
// resolve wherever their owner points them.
static BOOL CloudParseIPv4(NSString *host, NSInteger octets[4]) {
    NSArray<NSString *> *parts = [host componentsSeparatedByString:@"."];
    if (parts.count != 4) return NO;
    for (NSUInteger i = 0; i < 4; i++) {
        NSString *part = parts[i];
        if (part.length == 0 || part.length > 3) return NO;
        if (part.length > 1 && [part hasPrefix:@"0"]) return NO;
        for (NSUInteger j = 0; j < part.length; j++) {
            unichar c = [part characterAtIndex:j];
            if (c < '0' || c > '9') return NO;
        }
        NSInteger value = part.integerValue;
        if (value > 255) return NO;
        octets[i] = value;
    }
    return YES;
}

// Loopback / RFC1918-LAN / mDNS hosts — the places a local model server
// (Ollama, LM Studio, llama.cpp, vLLM) legitimately lives. Private IP ranges
// are only honored for literal IPv4 addresses; name lookups (other than mDNS
// .local, which never resolves through public DNS) can point anywhere.
static BOOL CloudHostIsLocal(NSString *host) {
    NSString *h = host.lowercaseString;
    if ([h isEqualToString:@"localhost"] || [h isEqualToString:@"::1"] || [h hasSuffix:@".local"]) return YES;
    NSInteger o[4];
    if (!CloudParseIPv4(h, o)) return NO;
    if (o[0] == 127 || o[0] == 10) return YES;                 // loopback, 10/8
    if (o[0] == 192 && o[1] == 168) return YES;                // 192.168/16
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return YES;   // 172.16/12
    return NO;
}

// Chat-completions endpoint for the active provider, nil when unconfigurable.
// Only "custom" can fail: its URL is user-entered, and a malformed one must be
// reported as a config error rather than dying later as a generic transport
// failure that hides which setting is wrong. http:// is permitted only for
// local hosts — the request carries the API key and the post/comment text,
// which must not cross the open internet in cleartext.
static NSURL *CloudEndpointURL(void) {
    if ([sAISummaryProvider isEqualToString:@"openai"]) {
        return [NSURL URLWithString:@"https://api.openai.com/v1/chat/completions"];
    }
    if ([sAISummaryProvider isEqualToString:@"openrouter"]) {
        return [NSURL URLWithString:@"https://openrouter.ai/api/v1/chat/completions"];
    }
    if ([sAISummaryProvider isEqualToString:@"gemini"]) {
        // Gemini's OpenAI-compatibility endpoint (Bearer auth with the Gemini API key).
        return [NSURL URLWithString:@"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"];
    }
    if ([sAISummaryProvider isEqualToString:@"custom"]) {
        NSString *base = [sCustomAIBaseURL stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (base.length == 0) return nil;
        while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        // Accept both a bare base URL (https://api.example.com/v1) and a full
        // chat-completions path pasted verbatim.
        if (![base hasSuffix:@"/chat/completions"]) {
            base = [base stringByAppendingString:@"/chat/completions"];
        }
        NSURL *url = [NSURL URLWithString:base];
        NSString *scheme = url.scheme.lowercaseString;
        BOOL schemeOK = [scheme isEqualToString:@"https"] ||
                        ([scheme isEqualToString:@"http"] && CloudHostIsLocal(url.host));
        return (schemeOK && url.host.length > 0) ? url : nil;
    }
    return nil;
}

BOOL ApolloAICloudBaseURLIsValid(void) {
    return CloudEndpointURL() != nil;
}

BOOL ApolloAICloudConfigured(void) {
    if (!ApolloAICloudProviderSelected()) return NO;
    return CloudAPIKey().length > 0 && CloudEndpointURL() != nil &&
           ApolloAICloudEffectiveModel().length > 0;
}

#pragma mark Legacy settings migration

void ApolloAIMigrateLegacyCloudKeys(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Idempotent via an explicit marker rather than by inspecting the new keys:
    // a user who migrates and later clears their key must not have the legacy
    // values resurrected on the next launch. Set the marker up front so a bail
    // below still counts as "migration considered".
    if ([defaults boolForKey:UDKeyAICloudLegacyMigrationDone]) return;
    [defaults setBool:YES forKey:UDKeyAICloudLegacyMigrationDone];

    NSString *(^trimmed)(NSString *) = ^NSString *(NSString *udKey) {
        id v = [defaults objectForKey:udKey];
        if (![v isKindOfClass:[NSString class]]) return nil;
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length > 0 ? s : nil;
    };

    // No stored key means the feature was never configured. (The pre-#674 build
    // registered an EMPTY-string default for this key and only ever *wrote* it
    // from the settings screen, so "absent or empty" is reliably the untouched
    // state rather than a real credential.)
    NSString *legacyKey = trimmed(UDKeyLegacyAICloudAPIKey);
    if (!legacyKey) return;

    // An explicit non-apple provider means the user has already been through
    // the new settings screen; their choice there wins over anything legacy.
    NSString *existingProvider = [defaults stringForKey:UDKeyAISummaryProvider];
    if (existingProvider.length > 0 && ![existingProvider isEqualToString:@"apple"]) return;

    NSString *legacyBaseURL = trimmed(UDKeyLegacyAICloudBaseURL);
    NSString *legacyModel = trimmed(UDKeyLegacyAICloudModel);

    // The old default base URL was OpenAI's and was *registered* rather than
    // written, so an absent value also means OpenAI. Anything else the user
    // typed becomes a "custom" endpoint and keeps behaving exactly as before.
    NSString *normalizedBase = legacyBaseURL.lowercaseString;
    while ([normalizedBase hasSuffix:@"/"]) {
        normalizedBase = [normalizedBase substringToIndex:normalizedBase.length - 1];
    }
    BOOL isOpenAI = normalizedBase.length == 0 ||
                    [normalizedBase isEqualToString:@"https://api.openai.com/v1"];

    if (isOpenAI) {
        [defaults setObject:legacyKey forKey:UDKeyOpenAIAPIKey];
        if (legacyModel) [defaults setObject:legacyModel forKey:UDKeyOpenAIAIModel];
        [defaults setObject:@"openai" forKey:UDKeyAISummaryProvider];
    } else {
        [defaults setObject:legacyKey forKey:UDKeyCustomAIAPIKey];
        [defaults setObject:legacyBaseURL forKey:UDKeyCustomAIBaseURL];
        if (legacyModel) [defaults setObject:legacyModel forKey:UDKeyCustomAIModel];
        [defaults setObject:@"custom" forKey:UDKeyAISummaryProvider];
    }
    ApolloLog(@"[AICloud] migrated pre-#674 cloud settings onto provider '%@'",
              isOpenAI ? @"openai" : @"custom");
}

#pragma mark Model-family shaping (OpenAI / custom)

// "openai/gpt-5-mini" (OpenRouter style) -> "gpt-5-mini" for family detection.
static NSString *CloudBareModelName(NSString *model) {
    NSRange slash = [model rangeOfString:@"/" options:NSBackwardsSearch];
    return slash.location == NSNotFound ? model : [model substringFromIndex:NSMaxRange(slash)];
}

// Reasoning-model families spend "thinking" tokens before the first streamed
// byte and reject sampling params: gpt-5*, and o<digit>* (o1/o3/o4-mini...).
static BOOL CloudIsReasoningModel(NSString *model) {
    NSString *bare = CloudBareModelName(model).lowercaseString;
    if ([bare hasPrefix:@"gpt-5"]) return YES;
    // Explicit '0'..'9' bounds: characterAtIndex returns a unichar, and passing
    // values outside unsigned char to isdigit() is undefined behavior.
    unichar second = bare.length >= 2 ? [bare characterAtIndex:1] : 0;
    if (bare.length >= 2 && [bare characterAtIndex:0] == 'o' &&
        second >= '0' && second <= '9') return YES;
    return NO;
}

// Lowest reasoning effort each family accepts — thinking latency/cost is pure
// waste for a 3-sentence summary. Dotted gpt-5.x models (gpt-5.1+) renamed
// "minimal" to "none"; the original gpt-5 family only knows "minimal"; the
// o-series (o1/o3/o4-mini) never had either, so "low" is its floor. Predicting
// this correctly avoids a wasted 400+retry roundtrip on every request for the
// default model; the one-shot retry stays as the net for models it mispredicts.
static NSString *CloudDefaultReasoningEffort(NSString *model) {
    NSString *bare = CloudBareModelName(model).lowercaseString;
    if ([bare hasPrefix:@"gpt-5."]) return @"none";
    if ([bare hasPrefix:@"gpt-5"]) return @"minimal";
    return @"low";
}

// Retry-override keys (values adjusting the primary shape after a 400 that
// names the offending parameter — see CloudRetryOverridesForError):
//   kCloudOverrideSwapTokenKey    -> @YES to use the token-cap key the primary
//                                    shape did NOT send
//   kCloudOverrideReasoningEffort -> NSString replacement, or NSNull to drop
//   kCloudOverrideDropTemperature -> @YES to drop temperature
//   kCloudOverrideFullStrip       -> @YES for the drop-everything shape
static NSString *const kCloudOverrideSwapTokenKey = @"swapTokenKey";
static NSString *const kCloudOverrideReasoningEffort = @"reasoningEffort";
static NSString *const kCloudOverrideDropTemperature = @"dropTemperature";
static NSString *const kCloudOverrideFullStrip = @"fullStrip";

// Maps a parsed 400 ("param" + message, both optional) to targeted overrides
// for the one-shot retry. Returns the full-strip fallback when the offending
// parameter can't be identified. Fixing ONLY what the provider complained
// about keeps the rest of the tuning intact (a blind full-strip swapped the
// token key too, which itself 400s on newer models that reject max_tokens).
static NSDictionary *CloudRetryOverridesForError(NSString *param, NSString *message) {
    NSString *lowerMessage = message.lowercaseString ?: @"";
    NSString *subject = param.length > 0 ? param.lowercaseString : lowerMessage;

    // The primary shape only ever sends ONE of the two token-cap keys, so an
    // error naming either can only mean "the key you sent is wrong" — swap to
    // the other. No need to work out which key the message is complaining
    // about vs suggesting ("'max_tokens' is not supported... Use
    // 'max_completion_tokens' instead" names both).
    if ([subject containsString:@"max_tokens"] || [subject containsString:@"max_completion_tokens"]) {
        return @{kCloudOverrideSwapTokenKey: @YES};
    }
    if ([subject containsString:@"reasoning_effort"] || [lowerMessage containsString:@"reasoning_effort"]) {
        // Newer models renamed the lowest effort "minimal" -> "none"; use it
        // when the error's supported-values list offers it, else drop the knob.
        if ([lowerMessage containsString:@"'none'"]) {
            return @{kCloudOverrideReasoningEffort: @"none"};
        }
        return @{kCloudOverrideReasoningEffort: [NSNull null]};
    }
    if ([subject containsString:@"temperature"]) {
        return @{kCloudOverrideDropTemperature: @YES};
    }
    return @{kCloudOverrideFullStrip: @YES};
}

#pragma mark - Per-request state

@interface ApolloAICloudRequest : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableString *accumulated;  // streamed content so far
@property (nonatomic, strong) NSMutableData *lineBuffer;     // partial SSE line carry-over
@property (nonatomic, strong) NSMutableData *rawBody;        // capped whole body (errors / non-streamed fallback)
@property (nonatomic, assign) NSInteger httpStatus;
@property (nonatomic, copy) NSString *retryAfterHeader;
@property (nonatomic, copy) NSString *lastPartialVisible; // last partial actually delivered
@property (nonatomic, copy) NSString *finishReason;       // finish_reason from the final chunk, if any
@property (nonatomic, assign) BOOL sawDone;               // saw `data: [DONE]`
@property (nonatomic, assign) BOOL streamedErrorObject;   // saw a top-level {"error": ...} SSE payload
@property (nonatomic, assign) BOOL droppedOversizedLine;  // an SSE line blew past the cap and was discarded
@property (nonatomic, assign) BOOL retriedTransient;      // the 429/5xx re-issue was used
@property (nonatomic, assign) BOOL retriedParameters;     // the 400 parameter-adjust re-issue was used
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, copy) void (^onPartial)(NSString *partial);
@property (nonatomic, copy) void (^onComplete)(NSString *final, NSError *error);
// Retained request material so either retry can rebuild the request.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *instructions;
@property (nonatomic, assign) NSInteger maximumResponseTokens;
@property (nonatomic, strong) NSDictionary *overrides; // current parameter overrides, nil = primary shape
@end

@implementation ApolloAICloudRequest
@end

#pragma mark - Bridge

@interface ApolloAICloudBridge () <NSURLSessionDataDelegate>
@end

@implementation ApolloAICloudBridge {
    NSURLSession *_session;
    dispatch_queue_t _stateQueue; // serial; also the session delegate queue's underlying queue
    NSMutableDictionary<NSString *, ApolloAICloudRequest *> *_requestsByIdentifier;
    NSMutableDictionary<NSNumber *, ApolloAICloudRequest *> *_requestsByTask;
}

+ (instancetype)shared {
    static ApolloAICloudBridge *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _stateQueue = dispatch_queue_create("com.apollo-reborn.aicloud", DISPATCH_QUEUE_SERIAL);
        NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
        delegateQueue.maxConcurrentOperationCount = 1;
        delegateQueue.underlyingQueue = _stateQueue;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        // For a streaming response the request timeout is the inter-chunk idle
        // timeout. It must outlast a whole thinking phase, not just a network
        // hiccup: Gemini streams NOTHING while a reasoning model thinks
        // (thoughts are excluded from its OpenAI-compat stream, but arrive
        // before any content), whereas OpenRouter keeps the stream warm with
        // keep-alive comments regardless. It must also stay BELOW the summary
        // module's cloud watchdog, so a stall produces this bridge's specific
        // error card rather than the watchdog's generic "took too long".
        config.timeoutIntervalForRequest = 60.0;
        config.timeoutIntervalForResource = 180.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:delegateQueue];
        _requestsByIdentifier = [NSMutableDictionary dictionary];
        _requestsByTask = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark Availability

- (NSInteger)availabilityStatus {
    // 4 = unconfigured: reuses the FM "framework absent" status so the summary
    // module's existing silent-skip path covers "cloud selected but no key yet".
    return ApolloAICloudConfigured() ? 0 : 4;
}

- (BOOL)isModelAvailable {
    return [self availabilityStatus] == 0;
}

#pragma mark No-op session prewarm (nothing to prewarm over HTTP)

- (void)prepareSession:(NSString *)identifier instructions:(NSString *)instructions {}
- (void)discardPreparedSession:(NSString *)identifier {}

#pragma mark Cancellation

- (void)cancelRequest:(NSString *)identifier {
    if (identifier.length == 0) return;
    dispatch_async(_stateQueue, ^{
        ApolloAICloudRequest *state = self->_requestsByIdentifier[identifier];
        if (!state) return;
        [state.task cancel];
        // Finish immediately rather than waiting for didCompleteWithError —
        // this also covers either retry's wait window, where the previous task
        // has already completed and cancelling it would be a no-op (the pending
        // retry checks state.finished and won't fire). The finished flag makes
        // the later delegate callback a harmless no-op.
        [self finishState:state final:nil errorCode:kCloudErrorCancelled message:@"cancelled"];
    });
}

#pragma mark Request building

// Builds the request body for the active provider. overrides=nil is the primary
// shape; with overrides, only the named parameter is adjusted (see
// CloudRetryOverridesForError).
static NSData *CloudRequestBody(NSString *text, NSString *instructions,
                                NSInteger maximumResponseTokens, NSDictionary *overrides) {
    NSString *model = ApolloAICloudEffectiveModel() ?: @"";
    NSMutableArray *messages = [NSMutableArray array];
    if (instructions.length > 0) {
        [messages addObject:@{@"role": @"system", @"content": instructions}];
    }
    [messages addObject:@{@"role": @"user", @"content": text ?: @""}];

    // Reasoning/thinking tokens count against the token cap on every provider,
    // so the caller's ~80-110-token visible-summary budget starves any thinking
    // model: it burns the whole cap reasoning and the actual summary arrives
    // empty ("In 1") or truncated mid-thought. The prompt instructions are what
    // bound the visible length; the cap is only a runaway guard, so give it
    // generous headroom. Custom gets a smaller one: local servers (Ollama /
    // llama.cpp / vLLM) reject prompt+cap beyond the loaded model's context
    // window, and 2k stays inside even a 4k-context model.
    BOOL isCustom = [sAISummaryProvider isEqualToString:@"custom"];
    BOOL isOpenAI = [sAISummaryProvider isEqualToString:@"openai"];
    NSInteger tokenBudget = MAX(isCustom ? 2048 : 4096, maximumResponseTokens * 8);

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:@{
        @"model": model,
        @"messages": messages,
        @"stream": @YES,
    }];

    // The full-strip fallback sends NO optional params at all — including the
    // token cap, whose key might itself be what the provider objected to.
    BOOL fullStrip = [overrides[kCloudOverrideFullStrip] boolValue];
    if (fullStrip) {
        return [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    }

    if (isOpenAI || isCustom) {
        // Model-family shaping. OpenAI's gpt-5 family and o-series reject
        // `max_tokens` outright (they require max_completion_tokens) and reject
        // `temperature`; sending the wrong one is a hard 400, not a warning.
        BOOL reasoning = CloudIsReasoningModel(model);
        NSString *tokenKey = reasoning ? @"max_completion_tokens" : @"max_tokens";
        if ([overrides[kCloudOverrideSwapTokenKey] boolValue]) {
            tokenKey = reasoning ? @"max_tokens" : @"max_completion_tokens";
        }
        payload[tokenKey] = @(tokenBudget);
        if (reasoning) {
            id effort = overrides[kCloudOverrideReasoningEffort] ?: CloudDefaultReasoningEffort(model);
            if (![effort isKindOfClass:[NSNull class]]) payload[@"reasoning_effort"] = effort;
        } else if (![overrides[kCloudOverrideDropTemperature] boolValue]) {
            payload[@"temperature"] = @0;
        }
    } else {
        payload[@"max_tokens"] = @(tokenBudget);
        if ([sAISummaryProvider isEqualToString:@"openrouter"]) {
            // Keep reasoning out of the response entirely: some hosts (notably
            // free tiers) otherwise stream chain-of-thought as ordinary content
            // deltas. "exclude" is the one universally-supported reasoning
            // control — it never *enables* reasoning on hybrid models (unlike
            // "effort", whose presence implies enabled:true) and, unlike
            // effort:"none", is not rejected by mandatory-reasoning models.
            payload[@"reasoning"] = @{@"exclude": @YES};
        } else if ([sAISummaryProvider isEqualToString:@"gemini"]) {
            // Turn thinking off where Gemini permits it — only the 2.5 Flash
            // family does; 2.5 Pro and Gemini 3 reject "none" outright, so gate
            // on the model and let those think inside the enlarged cap (their
            // thoughts stay out of the OpenAI-compat stream by default).
            NSString *normalizedModel = model.lowercaseString;
            if ([normalizedModel hasPrefix:@"models/"]) normalizedModel = [normalizedModel substringFromIndex:7];
            if ([normalizedModel hasPrefix:@"gemini-2.5-flash"]) {
                payload[@"reasoning_effort"] = @"none";
            }
        }
    }

    return [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
}

// nil when the active provider can't produce a usable request right now.
static NSURLRequest *CloudURLRequestForState(ApolloAICloudRequest *state) {
    NSString *apiKey = CloudAPIKey();
    NSURL *endpoint = CloudEndpointURL();
    if (apiKey.length == 0 || !endpoint) return nil;

    NSData *body = CloudRequestBody(state.text, state.instructions,
                                    state.maximumResponseTokens, state.overrides);
    if (!body) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    if ([sAISummaryProvider isEqualToString:@"openrouter"]) {
        // OpenRouter's recommended attribution headers (used for their rankings).
        [request setValue:@"https://github.com/Apollo-Reborn/Apollo-Reborn" forHTTPHeaderField:@"HTTP-Referer"];
        [request setValue:@"Apollo Reborn" forHTTPHeaderField:@"X-Title"];
    }
    return request;
}

#pragma mark Summarize

- (void)summarize:(NSString *)text
       identifier:(NSString *)identifier
     instructions:(NSString *)instructions
maximumResponseTokens:(NSInteger)maximumResponseTokens
        onPartial:(void (^)(NSString *partial))onPartial
       onComplete:(void (^)(NSString *final, NSError *error))onComplete {
    if (!onComplete) return;

    ApolloAICloudRequest *state = [[ApolloAICloudRequest alloc] init];
    state.identifier = identifier ?: @"";
    state.text = text;
    state.instructions = instructions;
    state.maximumResponseTokens = maximumResponseTokens;
    state.accumulated = [NSMutableString string];
    state.lineBuffer = [NSMutableData data];
    state.rawBody = [NSMutableData data];
    state.onPartial = onPartial;
    state.onComplete = onComplete;

    NSURLRequest *request = CloudURLRequestForState(state);
    if (!request) {
        // Normally unreachable (availabilityStatus gates first), but a base URL
        // edited to something unparseable mid-flight lands here. Report as the
        // "check the endpoint" error so the router can fall back to on-device.
        ApolloLog(@"[AICloud] request %@ aborted: provider unconfigured or base URL invalid", state.identifier);
        NSError *error = [NSError errorWithDomain:ApolloAICloudBridgeErrorDomain
                                             code:kCloudErrorService
                                         userInfo:@{NSLocalizedDescriptionKey: @"Cloud AI provider is not configured"}];
        dispatch_async(dispatch_get_main_queue(), ^{ onComplete(nil, error); });
        return;
    }

    NSString *model = ApolloAICloudEffectiveModel();
    NSString *provider = sAISummaryProvider;
    NSUInteger inputChars = text.length;
    dispatch_async(_stateQueue, ^{
        // A newer request for the same identifier supersedes the old one
        // (mirrors the FoundationModels bridge, which cancels the prior task).
        ApolloAICloudRequest *previous = self->_requestsByIdentifier[state.identifier];
        if (previous) {
            [previous.task cancel];
            previous.finished = YES;
        }
        [self startTaskForState:state request:request];
        ApolloLog(@"[AICloud] request %@ started (provider=%@ model=%@, %lu input chars)",
                  state.identifier, provider, model, (unsigned long)inputChars);
    });
}

// _stateQueue only. Resets per-attempt accumulation and starts a task.
- (void)startTaskForState:(ApolloAICloudRequest *)state request:(NSURLRequest *)request {
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    state.task = task;
    state.httpStatus = 0;
    state.retryAfterHeader = nil;
    state.sawDone = NO;
    state.streamedErrorObject = NO;
    state.droppedOversizedLine = NO;
    state.finishReason = nil;
    state.lastPartialVisible = nil;
    [state.lineBuffer setLength:0];
    [state.rawBody setLength:0];
    [state.accumulated setString:@""];
    _requestsByIdentifier[state.identifier] = state;
    _requestsByTask[@(task.taskIdentifier)] = state;
    [task resume];
}

#pragma mark Completion plumbing (_stateQueue only)

- (void)finishState:(ApolloAICloudRequest *)state final:(NSString *)final errorCode:(NSInteger)code message:(NSString *)message {
    if (!state || state.finished) return;
    state.finished = YES;
    [_requestsByTask removeObjectForKey:@(state.task.taskIdentifier)];
    if (_requestsByIdentifier[state.identifier] == state) {
        [_requestsByIdentifier removeObjectForKey:state.identifier];
    }
    void (^onComplete)(NSString *, NSError *) = state.onComplete;
    state.onComplete = nil;
    state.onPartial = nil;
    if (!onComplete) return;
    if (final) {
        dispatch_async(dispatch_get_main_queue(), ^{ onComplete(final, nil); });
        return;
    }
    NSError *error = [NSError errorWithDomain:ApolloAICloudBridgeErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: message ?: @"unknown error"}];
    if (code != kCloudErrorCancelled) {
        ApolloLog(@"[AICloud] request %@ failed (HTTP %ld, code=%ld): %@",
                  state.identifier, (long)state.httpStatus, (long)code, message);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ onComplete(nil, error); });
}

// _stateQueue only. Re-issues the request after `delay`, with the given
// parameter overrides. Returns NO when the request can no longer be rebuilt
// (base URL edited to something unparseable mid-flight).
- (BOOL)retryState:(ApolloAICloudRequest *)state
             after:(NSTimeInterval)delay
         overrides:(NSDictionary *)overrides {
    NSDictionary *previousOverrides = state.overrides;
    state.overrides = overrides;
    NSURLRequest *request = CloudURLRequestForState(state);
    if (!request) {
        state.overrides = previousOverrides;
        return NO;
    }
    // Detach from the finished task; the identifier keeps pointing at us so a
    // cancelRequest: during the wait still cancels (the task is already done,
    // so cancelRequest: marks finished directly).
    [_requestsByTask removeObjectForKey:@(state.task.taskIdentifier)];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _stateQueue, ^{
        if (state.finished) return;
        if (self->_requestsByIdentifier[state.identifier] != state) return; // superseded meanwhile
        [self startTaskForState:state request:request];
    });
    return YES;
}

#pragma mark Error mapping

// Extracts a human-readable message and the offending parameter name from an
// OpenAI-style error body: {"error": {"message": ..., "param": ...}} (string
// and nested-dict variants).
static NSString *CloudErrorMessageFromBody(NSData *body, NSString **outParam) {
    if (body.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        return raw.length > 0 && raw.length <= 300 ? raw : nil;
    }
    id error = ((NSDictionary *)json)[@"error"];
    if ([error isKindOfClass:[NSString class]]) return error;
    if ([error isKindOfClass:[NSDictionary class]]) {
        id param = ((NSDictionary *)error)[@"param"];
        if (outParam && [param isKindOfClass:[NSString class]]) *outParam = param;
        id message = ((NSDictionary *)error)[@"message"];
        if ([message isKindOfClass:[NSString class]]) return message;
    }
    return nil;
}

static BOOL CloudMessageSuggestsContextOverflow(NSString *message) {
    if (message.length == 0) return NO;
    for (NSString *needle in @[@"context", @"token", @"length", @"too long", @"maximum"]) {
        if ([message localizedCaseInsensitiveContainsString:needle]) return YES;
    }
    return NO;
}

- (void)handleHTTPFailureForState:(ApolloAICloudRequest *)state {
    NSInteger status = state.httpStatus;
    NSString *param = nil;
    NSString *message = CloudErrorMessageFromBody(state.rawBody, &param)
        ?: [NSString stringWithFormat:@"HTTP %ld", (long)status];
    BOOL contextOverflow = CloudMessageSuggestsContextOverflow(message);

    // Transient: one re-issue of the SAME request, honoring Retry-After up to 5s.
    if ((status == 429 || status == 500 || status == 502 || status == 503) && !state.retriedTransient) {
        state.retriedTransient = YES;
        NSTimeInterval delay = 1.0;
        double retryAfter = state.retryAfterHeader.doubleValue;
        if (retryAfter > 0) delay = MIN(retryAfter, 5.0);
        ApolloLog(@"[AICloud] request %@ got HTTP %ld, retrying once in %.1fs",
                  state.identifier, (long)status, delay);
        if ([self retryState:state after:delay overrides:state.overrides]) return;
    }

    // A 400 that names a parameter is a shape rejection, not a real failure:
    // re-issue once with only that parameter adjusted. This is what lets
    // OpenAI's reasoning models and arbitrary self-hosted servers work without
    // the user having to tune anything. A context-window 400 is a genuine
    // failure and must NOT be retried.
    if (status == 400 && !state.retriedParameters && !contextOverflow) {
        state.retriedParameters = YES;
        NSDictionary *overrides = CloudRetryOverridesForError(param, message);
        ApolloLog(@"[AICloud] request %@ rejected (HTTP 400); retrying with adjusted parameters (%@)",
                  state.identifier, [overrides.allKeys componentsJoinedByString:@","]);
        if ([self retryState:state after:0 overrides:overrides]) return;
    }

    NSInteger code;
    if (status == 401 || status == 402 || status == 403) {
        code = kCloudErrorAuth;
    } else if (status == 429) {
        code = kCloudErrorRateLimited;
    } else if (status == 400 && contextOverflow) {
        code = kCloudErrorContextWindow;
    } else {
        code = kCloudErrorService;
    }
    [self finishState:state final:nil errorCode:code message:message];
}

#pragma mark Reasoning-in-content stripping

// Reasoning models can leak chain-of-thought into message content instead of a
// separate reasoning field (free-tier OpenRouter hosts, local servers behind
// the custom provider). Two shapes exist in the wild: a tagged block
// (<think>…</think> — DeepSeek R1 family, Qwen, Nemotron), and reasoning that
// ends with a bare closing tag because the opening tag is baked into the
// model's chat template so it never appears in output. Content is accumulated
// raw; this derives what the user should actually see. Streaming-safe: an
// as-yet-unclosed tagged block (or a chunk boundary landing inside the tag
// literal, "<thi") is hidden until more of the stream arrives. The one
// unfixable-client-side shape — untagged reasoning with the closing tag still
// to come — can only show transiently in partials; the final text snaps to the
// post-tag answer, and the reasoning:{exclude:true} request parameter keeps
// OpenRouter from sending any of these shapes in the first place.
static NSString *CloudVisibleTextFromRaw(NSString *raw) {
    if (raw.length == 0) return raw;
    NSString *visible = raw;
    // Everything before the LAST closing tag is reasoning (this also disposes
    // of any properly-opened block preceding it).
    for (NSString *close in @[@"</think>", @"</thinking>"]) {
        NSRange r = [visible rangeOfString:close
                                   options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (r.location != NSNotFound) visible = [visible substringFromIndex:NSMaxRange(r)];
    }
    // A block whose closing tag hasn't arrived (yet): hide from the opener on.
    for (NSString *open in @[@"<think>", @"<thinking>"]) {
        NSRange r = [visible rangeOfString:open options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) visible = [visible substringToIndex:r.location];
    }
    // A chunk boundary can land inside the tag literal itself: hide a trailing
    // "<", "<th", … that is a strict prefix of an opening tag.
    NSRange lastAngle = [visible rangeOfString:@"<" options:NSBackwardsSearch];
    if (lastAngle.location != NSNotFound) {
        NSString *tail = [[visible substringFromIndex:lastAngle.location] lowercaseString];
        if (tail.length < @"<thinking>".length &&
            ([@"<think>" hasPrefix:tail] || [@"<thinking>" hasPrefix:tail])) {
            visible = [visible substringToIndex:lastAngle.location];
        }
    }
    return [visible stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark SSE parsing (_stateQueue via the session delegate queue)

// _stateQueue only. The stream ended without a transport/HTTP error: deliver
// the visible (reasoning-stripped) text, or a specific failure when nothing
// visible came.
- (void)finishStreamForState:(ApolloAICloudRequest *)state {
    if (state.droppedOversizedLine) {
        // Content after the dropped line is missing; surfacing a truncated
        // summary as success would be silent data loss — fail so the router
        // falls back to on-device.
        [self finishState:state final:nil errorCode:kCloudErrorService
                  message:@"the provider sent an oversized response"];
        return;
    }

    NSString *visible = CloudVisibleTextFromRaw(state.accumulated);
    if (visible.length > 0) {
        ApolloLog(@"[AICloud] request %@ DONE (%lu chars%@)", state.identifier,
                  (unsigned long)visible.length, state.sawDone ? @"" : @", stream ended without [DONE]");
        [self finishState:state final:visible errorCode:0 message:nil];
        return;
    }
    if (state.accumulated.length > 0 || [state.finishReason isEqualToString:@"length"]) {
        // Either the content was all chain-of-thought, or the model hit the
        // token cap while still thinking (Gemini reports finish_reason
        // "length" with empty content in that case).
        [self finishState:state final:nil errorCode:kCloudErrorReasoningOnly
                  message:@"model spent the whole response reasoning"];
        return;
    }
    // Empty stream: some providers ignore `stream:true` and answer with one
    // plain JSON completion object instead.
    id json = state.rawBody.length > 0
        ? [NSJSONSerialization JSONObjectWithData:state.rawBody options:0 error:NULL] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSArray *choices = ((NSDictionary *)json)[@"choices"];
        id message = [choices isKindOfClass:[NSArray class]] && choices.count > 0 &&
                     [choices.firstObject isKindOfClass:[NSDictionary class]]
            ? ((NSDictionary *)choices.firstObject)[@"message"] : nil;
        id content = [message isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)message)[@"content"] : nil;
        if ([content isKindOfClass:[NSString class]] && [(NSString *)content length] > 0) {
            NSString *nonStreamed = CloudVisibleTextFromRaw(content);
            if (nonStreamed.length > 0) {
                ApolloLog(@"[AICloud] request %@ DONE (non-streamed, %lu chars)",
                          state.identifier, (unsigned long)nonStreamed.length);
                [self finishState:state final:nonStreamed errorCode:0 message:nil];
                return;
            }
        }
    }
    [self finishState:state final:nil errorCode:kCloudErrorService
              message:@"empty response from model"];
}

- (void)processSSELine:(NSString *)line forState:(ApolloAICloudRequest *)state {
    // Blank keep-alives, `: comment` heartbeats (OpenRouter), and `event:`/`id:`
    // framing lines are all ignorable.
    if (line.length == 0 || [line hasPrefix:@":"]) return;
    if (![line hasPrefix:@"data:"]) return;
    NSString *payload = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
    if ([payload isEqualToString:@"[DONE]"]) {
        state.sawDone = YES;
        [self finishStreamForState:state];
        return;
    }
    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) return; // tolerate malformed keep-alives
    NSDictionary *chunk = (NSDictionary *)json;

    // OpenRouter can surface an error object mid-stream. Even with partial
    // content already accumulated this means the output is incomplete — fail
    // rather than surface (and cache) a truncated summary.
    id chunkError = chunk[@"error"];
    if ([chunkError isKindOfClass:[NSDictionary class]] || [chunkError isKindOfClass:[NSString class]]) {
        NSString *message = [chunkError isKindOfClass:[NSString class]]
            ? chunkError : (((NSDictionary *)chunkError)[@"message"] ?: @"provider error");
        NSInteger providerCode = [chunkError isKindOfClass:[NSDictionary class]]
            ? [((NSDictionary *)chunkError)[@"code"] integerValue] : 0;
        NSInteger code = kCloudErrorService;
        if (providerCode == 401 || providerCode == 402 || providerCode == 403) code = kCloudErrorAuth;
        else if (providerCode == 429) code = kCloudErrorRateLimited;
        state.streamedErrorObject = YES;
        [self finishState:state final:nil errorCode:code message:[message description]];
        return;
    }

    NSArray *choices = chunk[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) return; // usage/keep-alive chunk
    NSDictionary *choice = [choices[0] isKindOfClass:[NSDictionary class]] ? choices[0] : nil;
    id finishReason = choice[@"finish_reason"];
    if ([finishReason isKindOfClass:[NSString class]]) state.finishReason = finishReason;
    NSDictionary *delta = choice[@"delta"];
    id content = [delta isKindOfClass:[NSDictionary class]] ? delta[@"content"] : nil;
    // Note: delta.reasoning / delta.reasoning_details / delta.reasoning_content
    // are deliberately ignored — chain-of-thought is never user-visible.
    if (![content isKindOfClass:[NSString class]] || [(NSString *)content length] == 0) return; // role-only chunk
    [state.accumulated appendString:content];

    if (state.onPartial) {
        // FM contract: partials are cumulative. Deliver the reasoning-stripped
        // view, and only when it changed — while a <think> block streams, the
        // visible text sits unchanged (often empty) and there is nothing to say.
        NSString *visible = CloudVisibleTextFromRaw(state.accumulated);
        if (visible.length > 0 && ![visible isEqualToString:state.lastPartialVisible]) {
            state.lastPartialVisible = visible;
            void (^onPartial)(NSString *) = state.onPartial;
            dispatch_async(dispatch_get_main_queue(), ^{ onPartial(visible); });
        }
    }
}

// _stateQueue only. Consumes every complete line currently buffered. SSE lines
// may end in LF, CR, or CRLF (WHATWG spec), so both delimiters are honored.
- (void)processBufferedLinesForState:(ApolloAICloudRequest *)state {
    while (!state.finished) {
        const uint8_t *bytes = state.lineBuffer.bytes;
        NSUInteger length = state.lineBuffer.length;
        NSUInteger end = 0;
        while (end < length && bytes[end] != '\n' && bytes[end] != '\r') end++;
        if (end == length) return;   // no complete line buffered yet
        // A CR as the very last buffered byte is ambiguous (bare CR vs the first
        // half of a CRLF split across chunks) — wait for the next byte. This
        // can't stall forever: the completion path flushes with a trailing LF.
        if (bytes[end] == '\r' && end + 1 == length) return;
        NSUInteger consumed = end + 1;
        if (bytes[end] == '\r' && bytes[end + 1] == '\n') consumed++;

        NSData *lineData = [state.lineBuffer subdataWithRange:NSMakeRange(0, end)];
        [state.lineBuffer replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];

        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        if (line) [self processSSELine:line forState:state];
    }
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    ApolloAICloudRequest *state = _requestsByTask[@(dataTask.taskIdentifier)];
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        state.httpStatus = http.statusCode;
        state.retryAfterHeader = http.allHeaderFields[@"Retry-After"];
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    ApolloAICloudRequest *state = _requestsByTask[@(dataTask.taskIdentifier)];
    if (!state || state.finished) return;

    // Always keep a capped copy of the raw body: it backs both the error-message
    // extraction and the non-streamed JSON fallback. Clamp the append to the
    // remaining budget so one oversized chunk can't carry it past the cap.
    if (state.rawBody.length < kCloudMaxBufferedBody) {
        NSUInteger remaining = kCloudMaxBufferedBody - state.rawBody.length;
        [state.rawBody appendData:data.length <= remaining
            ? data : [data subdataWithRange:NSMakeRange(0, remaining)]];
    }
    if (state.httpStatus < 200 || state.httpStatus >= 300) return; // buffered whole for error extraction

    [state.lineBuffer appendData:data];
    [self processBufferedLinesForState:state];
    // Whatever remains has no line terminator yet. A single line past the cap is
    // pathological (real deltas are a few KB) — drop it rather than grow until
    // OOM. The line's later chunks then read as terminated fragments without a
    // `data:` prefix and are skipped harmlessly. The flag fails the request at
    // completion: content past the drop may be missing, and a silently
    // truncated summary is worse than falling back.
    if (state.lineBuffer.length > kCloudMaxBufferedBody) {
        ApolloLog(@"[AICloud] request %@ dropped an oversized SSE line (%lu bytes buffered)",
                  state.identifier, (unsigned long)state.lineBuffer.length);
        [state.lineBuffer setLength:0];
        state.droppedOversizedLine = YES;
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    ApolloAICloudRequest *state = _requestsByTask[@(task.taskIdentifier)];
    if (!state || state.finished) return;

    if (error) {
        if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) {
            [self finishState:state final:nil errorCode:kCloudErrorCancelled message:@"cancelled"];
        } else {
            // Timeouts, DNS, offline, TLS, ATS-blocked plain-http custom URLs…
            [self finishState:state final:nil errorCode:kCloudErrorService
                      message:error.localizedDescription ?: @"network error"];
        }
        return;
    }
    if (state.httpStatus < 200 || state.httpStatus >= 300) {
        [self handleHTTPFailureForState:state];
        return;
    }
    // A stream that closes without a trailing terminator leaves its final line —
    // often the last delta — unconsumed. Flush it as a complete line before
    // judging the result. (Same serial queue as didReceiveData:, so this can't
    // race an in-flight append.)
    if (state.lineBuffer.length > 0) {
        [state.lineBuffer appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [self processBufferedLinesForState:state];
    }
    if (state.finished) return;   // a flushed [DONE] already completed us
    // Clean close without an explicit [DONE]: same handling as [DONE].
    [self finishStreamForState:state];
}

@end
