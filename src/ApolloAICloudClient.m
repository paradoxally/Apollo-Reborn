//
//  ApolloAICloudClient.m
//  Apollo-Reborn
//
//  See ApolloAICloudClient.h. Implementation notes:
//
//  - One shared NSURLSession with this singleton as its data delegate (the
//    session retains its delegate; benign here because the client is a
//    process-lifetime singleton). Delegate callbacks arrive on a serial
//    NSOperationQueue; all shared state is additionally guarded by a lock
//    because cancelRequest: can run on the main thread concurrently.
//  - SSE parsing: the response is a stream of `data: {json}` lines terminated
//    by `data: [DONE]`. Cumulative assistant text accumulates per request and
//    is delivered to onPartial on the main thread.
//  - Parameter shaping: reasoning models (gpt-5*, o<digit>*) get their
//    family's lowest reasoning_effort ("none" for dotted gpt-5.x, "minimal"
//    for the original gpt-5 family, "low" for o-series) + max_completion_tokens
//    and no temperature (they reject it, and thinking latency/cost is pure
//    waste for a 3-sentence summary); everything else gets temperature=0 +
//    max_tokens. If a provider
//    rejects the shape with an HTTP 400, the request is transparently
//    re-issued ONCE, fixing only the parameter the error names (token-cap key
//    swap, reasoning_effort remap/drop, temperature drop); an unidentifiable
//    400 falls back to the fully stripped legacy shape.
//  - Privacy: never log the API key, the request body, or any streamed text —
//    diagnostics are identifier/status/byte-count only, matching the
//    "never log generated text" discipline in ApolloAISummary.xm.
//

#import "ApolloAICloudClient.h"
#import "ApolloCommon.h"
#import "ApolloState.h"

NSString *const ApolloAICloudErrorDomain = @"ApolloAICloud";

BOOL ApolloAICloudConfigured(void) {
    return sCloudAIAPIKey.length > 0 && sCloudAIBaseURL.length > 0;
}

#pragma mark - Per-request stream context

@interface ApolloAICloudStream : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSMutableData *lineBuffer;    // unconsumed SSE bytes
@property (nonatomic, strong) NSMutableData *rawBody;       // capped copy of the whole body (error / non-streamed fallback)
@property (nonatomic, strong) NSMutableString *content;     // accumulated assistant text
@property (nonatomic) NSInteger httpStatus;
@property (nonatomic) BOOL sawDone;                         // saw `data: [DONE]`
@property (nonatomic) BOOL streamedErrorObject;             // saw a top-level {"error": ...} SSE payload
@property (nonatomic) BOOL droppedOversizedLine;            // an SSE line blew past the buffer cap and was discarded
@property (nonatomic) BOOL didStripRetry;                   // the one-shot 400 parameter-strip retry was used
@property (nonatomic) BOOL cancelled;                       // cancelRequest: hit this stream (set under the lock)
@property (nonatomic, copy) void (^onPartial)(NSString *);
@property (nonatomic, copy) void (^onComplete)(NSString *, NSError *);
// Retained request material so the strip-retry can rebuild the request.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *instructions;
@property (nonatomic) NSInteger maximumResponseTokens;
@end

@implementation ApolloAICloudStream
- (instancetype)init {
    if ((self = [super init])) {
        _lineBuffer = [NSMutableData data];
        _rawBody = [NSMutableData data];
        _content = [NSMutableString string];
    }
    return self;
}
@end

#pragma mark - Client

// Providers can return large error pages; keep enough for diagnostics and the
// non-streamed JSON fallback without buffering a runaway body.
static const NSUInteger kApolloAICloudMaxBufferedBody = 512 * 1024;

@interface ApolloAICloudClient () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSLock *lock;
// taskIdentifier -> stream context; requestID -> task (for cancellation).
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ApolloAICloudStream *> *streamsByTask;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *tasksByRequestID;
@end

@implementation ApolloAICloudClient

+ (instancetype)shared {
    static ApolloAICloudClient *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[ApolloAICloudClient alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = [[NSLock alloc] init];
        _streamsByTask = [NSMutableDictionary dictionary];
        _tasksByRequestID = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        // Idle timeout between chunks. The overall bound is ApolloAISummary's
        // generation watchdog, which cancels us (-> code 6) — so this must sit
        // ABOVE the largest watchdog value (120s cloud/sim), otherwise a
        // long-thinking model that streams nothing while reasoning gets cut
        // off by the transport before the watchdog can rule.
        config.timeoutIntervalForRequest = 150.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        queue.name = @"com.apollo-reborn.aicloud.delegate";
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
    }
    return self;
}

#pragma mark Request building

// "openai/gpt-5-mini" (OpenRouter style) -> "gpt-5-mini" for family detection.
static NSString *ApolloAICloudBareModelName(NSString *model) {
    NSRange slash = [model rangeOfString:@"/" options:NSBackwardsSearch];
    return slash.location == NSNotFound ? model : [model substringFromIndex:NSMaxRange(slash)];
}

// Reasoning-model families spend "thinking" tokens before the first streamed
// byte and reject sampling params: gpt-5*, and o<digit>* (o1/o3/o4-mini...).
static BOOL ApolloAICloudIsReasoningModel(NSString *model) {
    NSString *bare = ApolloAICloudBareModelName(model).lowercaseString;
    if ([bare hasPrefix:@"gpt-5"]) return YES;
    // Explicit '0'..'9' bounds: characterAtIndex returns a unichar, and
    // passing values outside unsigned char to isdigit() is undefined behavior.
    unichar second = bare.length >= 2 ? [bare characterAtIndex:1] : 0;
    if (bare.length >= 2 && [bare characterAtIndex:0] == 'o' &&
        second >= '0' && second <= '9') return YES;
    return NO;
}

// YES only for a literal dotted-quad IPv4 address: exactly four all-numeric
// octets, each 0-255, no leading zeros (inet-style resolvers treat "010" as
// octal, so "010.1.2.3" could connect somewhere other than 10.1.2.3).
// Hostnames like "10.evil.com" or "127.0.0.1.evil.com" must NOT parse — they
// resolve wherever their owner points them.
static BOOL ApolloAICloudParseIPv4(NSString *host, NSInteger octets[4]) {
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

// Loopback / RFC1918-LAN / mDNS hosts — the places a local-development model
// server (mock, LM Studio, Ollama proxy) legitimately lives. Private IP ranges
// are only honored for literal IPv4 addresses; name lookups (other than mDNS
// .local, which never resolves through public DNS) can point anywhere.
static BOOL ApolloAICloudHostIsLocal(NSString *host) {
    NSString *h = host.lowercaseString;
    if ([h isEqualToString:@"localhost"] || [h isEqualToString:@"::1"] || [h hasSuffix:@".local"]) return YES;
    NSInteger o[4];
    if (!ApolloAICloudParseIPv4(h, o)) return NO;
    if (o[0] == 127 || o[0] == 10) return YES;                 // loopback, 10/8
    if (o[0] == 192 && o[1] == 168) return YES;                // 192.168/16
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return YES;   // 172.16/12
    return NO;
}

// Returns nil for a base URL that can't produce a usable request (user-entered
// setting — e.g. contains spaces, or lacks a scheme/host). Callers must treat
// nil as a hard config error rather than build a request from it: a malformed
// URL either crashes requestWithURL: or dies later as a generic transport
// error, hiding that the problem is the setting, not connectivity.
// http is only allowed for local hosts: the request carries the API key and
// post/comment text, which must not cross the open internet in cleartext.
static NSURL *ApolloAICloudChatCompletionsURL(void) {
    NSString *base = sCloudAIBaseURL ?: @"";
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/chat/completions"]];
    NSString *scheme = url.scheme.lowercaseString;
    BOOL schemeOK = [scheme isEqualToString:@"https"] ||
                    ([scheme isEqualToString:@"http"] && ApolloAICloudHostIsLocal(url.host));
    return (schemeOK && url.host.length > 0) ? url : nil;
}

BOOL ApolloAICloudBaseURLIsValid(void) {
    return ApolloAICloudChatCompletionsURL() != nil;
}

// Retry-override keys (values adjusting the primary shape after a 400 that
// names the offending parameter — see ApolloAICloudRetryOverridesForError):
//   kApolloAICloudOverrideSwapTokenKey    -> @YES to use the token-cap key the
//                                            primary shape did NOT send
//   kApolloAICloudOverrideReasoningEffort -> NSString replacement, or NSNull to drop
//   kApolloAICloudOverrideDropTemperature -> @YES to drop temperature
//   kApolloAICloudOverrideFullStrip       -> @YES for the legacy drop-everything shape
static NSString *const kApolloAICloudOverrideSwapTokenKey = @"swapTokenKey";
static NSString *const kApolloAICloudOverrideReasoningEffort = @"reasoningEffort";
static NSString *const kApolloAICloudOverrideDropTemperature = @"dropTemperature";
static NSString *const kApolloAICloudOverrideFullStrip = @"fullStrip";

// Lowest reasoning effort each family accepts — thinking latency/cost is pure
// waste for a 3-sentence summary. Dotted gpt-5.x models (gpt-5.1+) renamed
// "minimal" to "none"; the original gpt-5 family only knows "minimal"; the
// o-series (o1/o3/o4-mini) never had either, so "low" is its floor. Predicting
// this correctly avoids a wasted 400+retry roundtrip on every request for the
// default model; the one-shot retry stays as the net for models this table
// mispredicts.
static NSString *ApolloAICloudDefaultReasoningEffort(NSString *model) {
    NSString *bare = ApolloAICloudBareModelName(model).lowercaseString;
    if ([bare hasPrefix:@"gpt-5."]) return @"none";
    if ([bare hasPrefix:@"gpt-5"]) return @"minimal";
    return @"low";
}

// Builds the request body. overrides=nil is the primary shape (reasoning models:
// max_completion_tokens + the family's lowest reasoning_effort; others:
// max_tokens + temperature=0). With overrides, the primary shape is adjusted
// per the keys above — fixing ONLY what the provider complained about keeps the
// rest of the tuning intact (a blind full-strip swapped the token key too,
// which itself 400s on newer models that reject max_tokens outright).
static NSData *ApolloAICloudRequestBody(NSString *text, NSString *instructions,
                                        NSInteger maxTokens, NSDictionary *overrides) {
    NSString *model = sCloudAIModel ?: @"gpt-5.4-mini";
    BOOL reasoning = ApolloAICloudIsReasoningModel(model);
    BOOL fullStrip = [overrides[kApolloAICloudOverrideFullStrip] boolValue];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"model": model,
        @"stream": @YES,
        @"messages": @[
            @{@"role": @"system", @"content": instructions ?: @""},
            @{@"role": @"user", @"content": text ?: @""},
        ],
    }];

    NSString *tokenKey = reasoning ? @"max_completion_tokens" : @"max_tokens";
    if ([overrides[kApolloAICloudOverrideSwapTokenKey] boolValue]) {
        tokenKey = reasoning ? @"max_tokens" : @"max_completion_tokens";
    }
    // The full-strip fallback sends NO optional params at all — including the
    // token cap, whose key might itself be what the provider objected to.
    if (!fullStrip && maxTokens > 0) body[tokenKey] = @(maxTokens);

    if (!fullStrip) {
        if (reasoning) {
            id effort = overrides[kApolloAICloudOverrideReasoningEffort]
                ?: ApolloAICloudDefaultReasoningEffort(model);
            if (![effort isKindOfClass:[NSNull class]]) body[@"reasoning_effort"] = effort;
        } else if (![overrides[kApolloAICloudOverrideDropTemperature] boolValue]) {
            body[@"temperature"] = @0;
        }
    }
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
}

- (NSURLSessionDataTask *)taskForStream:(ApolloAICloudStream *)stream overrides:(NSDictionary *)overrides {
    NSURL *url = ApolloAICloudChatCompletionsURL();
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[@"Bearer " stringByAppendingString:sCloudAIAPIKey ?: @""] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = ApolloAICloudRequestBody(stream.text, stream.instructions,
                                                stream.maximumResponseTokens, overrides);
    return [self.session dataTaskWithRequest:request];
}

// Maps a parsed 400 ("param" + message, both optional) to targeted overrides
// for the one-shot retry. Returns the full-strip fallback when the offending
// parameter can't be identified.
static NSDictionary *ApolloAICloudRetryOverridesForError(NSString *param, NSString *message) {
    NSString *lowerMessage = message.lowercaseString ?: @"";
    NSString *subject = param.length > 0 ? param.lowercaseString : lowerMessage;

    // The primary shape only ever sends ONE of the two token-cap keys, so an
    // error naming either one can only mean "the key you sent is wrong" — swap
    // to the other. No need to work out which key the message is complaining
    // about vs suggesting ("'max_tokens' is not supported... Use
    // 'max_completion_tokens' instead" names both).
    if ([subject containsString:@"max_tokens"] || [subject containsString:@"max_completion_tokens"]) {
        return @{kApolloAICloudOverrideSwapTokenKey: @YES};
    }
    if ([subject containsString:@"reasoning_effort"] || [lowerMessage containsString:@"reasoning_effort"]) {
        // Newer models renamed the lowest effort "minimal" -> "none"; use it
        // when the error's supported-values list offers it, else drop the knob.
        if ([lowerMessage containsString:@"'none'"]) {
            return @{kApolloAICloudOverrideReasoningEffort: @"none"};
        }
        return @{kApolloAICloudOverrideReasoningEffort: [NSNull null]};
    }
    if ([subject containsString:@"temperature"]) {
        return @{kApolloAICloudOverrideDropTemperature: @YES};
    }
    return @{kApolloAICloudOverrideFullStrip: @YES};
}

#pragma mark Public API

- (void)summarize:(NSString *)text
       identifier:(NSString *)identifier
     instructions:(NSString *)instructions
maximumResponseTokens:(NSInteger)maximumResponseTokens
        onPartial:(void (^)(NSString *))onPartial
       onComplete:(void (^)(NSString *, NSError *))onComplete {
    if (!ApolloAICloudConfigured() || text.length == 0) {
        NSError *error = [NSError errorWithDomain:ApolloAICloudErrorDomain
                                             code:ApolloAICloudErrorProvider
                                         userInfo:@{NSLocalizedDescriptionKey: @"Cloud model not configured"}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (onComplete) onComplete(nil, error); });
        return;
    }

    ApolloAICloudStream *stream = [[ApolloAICloudStream alloc] init];
    stream.identifier = identifier ?: @"";
    stream.onPartial = onPartial;
    stream.onComplete = onComplete;
    stream.text = text;
    stream.instructions = instructions;
    stream.maximumResponseTokens = maximumResponseTokens;

    NSURLSessionDataTask *task = [self taskForStream:stream overrides:nil];
    if (!task) {
        // Unparseable user-entered base URL. This abort still SUPERSEDES any
        // in-flight request for the same identifier (cancel + clear, exactly
        // like the success path below) so a stale request can't keep streaming
        // into the card while the caller runs its error/fallback flow.
        [self.lock lock];
        NSURLSessionDataTask *previous = self.tasksByRequestID[stream.identifier];
        [self.tasksByRequestID removeObjectForKey:stream.identifier];
        [self.lock unlock];
        [previous cancel];

        // Surface as the "check the base URL" error (code 12) so the router
        // can fall back to on-device.
        ApolloLog(@"[AISummary][cloud] request %@ aborted: base URL is not a valid URL", stream.identifier);
        NSError *error = [NSError errorWithDomain:ApolloAICloudErrorDomain
                                             code:ApolloAICloudErrorNetwork
                                         userInfo:@{NSLocalizedDescriptionKey: @"The cloud AI base URL is invalid"}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (onComplete) onComplete(nil, error); });
        return;
    }

    [self.lock lock];
    // A newer request for the same identifier supersedes any in-flight one
    // (mirrors the bridge, which cancels the previous task per identifier).
    NSURLSessionDataTask *previous = self.tasksByRequestID[stream.identifier];
    self.tasksByRequestID[stream.identifier] = task;
    self.streamsByTask[@(task.taskIdentifier)] = stream;
    [self.lock unlock];
    [previous cancel];

    ApolloLog(@"[AISummary][cloud] request %@ started (%lu input chars)",
              stream.identifier, (unsigned long)text.length);
    [task resume];
}

- (void)cancelRequest:(NSString *)identifier {
    if (identifier.length == 0) return;
    [self.lock lock];
    NSURLSessionDataTask *task = self.tasksByRequestID[identifier];
    // Also flag the stream itself: a cancel can land while the original task is
    // inside its 400 strip-retry handoff (already completed, retry not yet
    // resumed) — cancelling the completed task alone would be a no-op and the
    // retry would run anyway. stripRetryTask: checks this flag under the lock.
    ApolloAICloudStream *stream = task ? self.streamsByTask[@(task.taskIdentifier)] : nil;
    stream.cancelled = YES;
    [self.lock unlock];
    // The cancel surfaces in didCompleteWithError: as NSURLErrorCancelled and
    // is mapped to code 6 there; bookkeeping is cleaned up in one place.
    [task cancel];
}

#pragma mark Completion plumbing

// Removes the stream's bookkeeping and fires onComplete exactly once (main thread).
- (void)finishTask:(NSURLSessionTask *)task
            stream:(ApolloAICloudStream *)stream
             final:(NSString *)final
             error:(NSError *)error {
    [self.lock lock];
    [self.streamsByTask removeObjectForKey:@(task.taskIdentifier)];
    // Only clear the requestID mapping if it still points at THIS task — a
    // superseding request may already own the slot.
    if (self.tasksByRequestID[stream.identifier] == task) {
        [self.tasksByRequestID removeObjectForKey:stream.identifier];
    }
    [self.lock unlock];

    void (^onComplete)(NSString *, NSError *) = stream.onComplete;
    stream.onComplete = nil;
    stream.onPartial = nil;
    if (!onComplete) return;
    dispatch_async(dispatch_get_main_queue(), ^{ onComplete(final, error); });
}

- (void)finishTask:(NSURLSessionTask *)task
            stream:(ApolloAICloudStream *)stream
              code:(ApolloAICloudErrorCode)code
           message:(NSString *)message {
    ApolloLog(@"[AISummary][cloud] request %@ failed (HTTP %ld, code %ld)",
              stream.identifier, (long)stream.httpStatus, (long)code);
    NSError *error = [NSError errorWithDomain:ApolloAICloudErrorDomain code:code
                                     userInfo:@{NSLocalizedDescriptionKey: message ?: @"Cloud request failed"}];
    [self finishTask:task stream:stream final:nil error:error];
}

// Re-issues the request once with the given parameter overrides, transferring
// the context to the new task. Returns without firing onComplete.
- (void)stripRetryTask:(NSURLSessionTask *)task
                stream:(ApolloAICloudStream *)stream
             overrides:(NSDictionary *)overrides {
    ApolloLog(@"[AISummary][cloud] request %@ rejected (HTTP 400); retrying with adjusted parameters (%@)",
              stream.identifier, [overrides.allKeys componentsJoinedByString:@","]);
    stream.didStripRetry = YES;
    stream.lineBuffer = [NSMutableData data];
    stream.rawBody = [NSMutableData data];
    stream.content = [NSMutableString string];
    stream.httpStatus = 0;
    stream.sawDone = NO;
    stream.streamedErrorObject = NO;
    stream.droppedOversizedLine = NO;

    NSURLSessionDataTask *retryTask = [self taskForStream:stream overrides:overrides];
    if (!retryTask) {   // base URL edited to something unparseable mid-flight
        [self finishTask:task stream:stream code:ApolloAICloudErrorNetwork
                 message:@"The cloud AI base URL is invalid"];
        return;
    }
    // Retry only while this request still owns its identifier slot AND wasn't
    // cancelled. A cancel that landed after the original task completed (so its
    // [task cancel] was a no-op) or a superseding request both win this race —
    // the retry must not run behind them.
    BOOL proceed = NO;
    [self.lock lock];
    [self.streamsByTask removeObjectForKey:@(task.taskIdentifier)];
    if (!stream.cancelled &&
        (self.tasksByRequestID[stream.identifier] == task ||
         self.tasksByRequestID[stream.identifier] == nil)) {
        self.streamsByTask[@(retryTask.taskIdentifier)] = stream;
        self.tasksByRequestID[stream.identifier] = retryTask;
        proceed = YES;
    }
    [self.lock unlock];
    if (proceed) {
        [retryTask resume];
        return;
    }
    [retryTask cancel];
    [self finishTask:task stream:stream code:ApolloAICloudErrorCancelled message:@"Cancelled"];
}

#pragma mark SSE parsing

// Handles one `data: {...}` payload. Returns the delta text to append, if any.
static NSString *ApolloAICloudDeltaFromPayload(NSData *payload, BOOL *outIsErrorObject) {
    id json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    if ([json[@"error"] isKindOfClass:[NSDictionary class]]) {
        if (outIsErrorObject) *outIsErrorObject = YES;
        return nil;
    }
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) return nil;
    NSDictionary *delta = [choices.firstObject isKindOfClass:[NSDictionary class]]
        ? ((NSDictionary *)choices.firstObject)[@"delta"] : nil;
    if (![delta isKindOfClass:[NSDictionary class]]) return nil;
    // Role-only first chunk and OpenRouter `delta.reasoning` chunks have no
    // content; both are intentionally ignored.
    NSString *content = delta[@"content"];
    return [content isKindOfClass:[NSString class]] && content.length > 0 ? content : nil;
}

- (void)processBufferedLinesForStream:(ApolloAICloudStream *)stream {
    while (YES) {
        // SSE lines may end in LF, CR, or CRLF (WHATWG spec) — scan for the
        // first of either delimiter byte.
        const uint8_t *bytes = stream.lineBuffer.bytes;
        NSUInteger length = stream.lineBuffer.length;
        NSUInteger end = 0;
        while (end < length && bytes[end] != '\n' && bytes[end] != '\r') end++;
        if (end == length) return;   // no complete line buffered yet
        // A CR as the very last buffered byte is ambiguous (bare CR vs first
        // half of a CRLF split across chunks) — wait for the next byte. This
        // can't stall forever: the completion path flushes with a trailing LF.
        if (bytes[end] == '\r' && end + 1 == length) return;
        NSUInteger consumed = end + 1;
        if (bytes[end] == '\r' && bytes[end + 1] == '\n') consumed++;

        NSData *lineData = [stream.lineBuffer subdataWithRange:NSMakeRange(0, end)];
        [stream.lineBuffer replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];

        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        // Blank keep-alives, `: comment` heartbeats (OpenRouter), and
        // `event:`/`id:` framing lines are all ignorable.
        if (line.length == 0 || [line hasPrefix:@":"]) continue;
        if (![line hasPrefix:@"data:"]) continue;

        NSString *payload = [[line substringFromIndex:5]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([payload isEqualToString:@"[DONE]"]) { stream.sawDone = YES; continue; }

        BOOL isErrorObject = NO;
        NSString *delta = ApolloAICloudDeltaFromPayload([payload dataUsingEncoding:NSUTF8StringEncoding],
                                                        &isErrorObject);
        if (isErrorObject) { stream.streamedErrorObject = YES; continue; }
        if (delta.length == 0) continue;

        [stream.content appendString:delta];
        if (stream.onPartial) {
            NSString *snapshot = [stream.content copy];
            void (^onPartial)(NSString *) = stream.onPartial;
            dispatch_async(dispatch_get_main_queue(), ^{ onPartial(snapshot); });
        }
    }
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self.lock lock];
    ApolloAICloudStream *stream = self.streamsByTask[@(dataTask.taskIdentifier)];
    [self.lock unlock];
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        stream.httpStatus = ((NSHTTPURLResponse *)response).statusCode;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [self.lock lock];
    ApolloAICloudStream *stream = self.streamsByTask[@(dataTask.taskIdentifier)];
    [self.lock unlock];
    if (!stream) return;

    // Clamp the append to the remaining budget — a single oversized chunk must
    // not carry the buffer past the cap.
    if (stream.rawBody.length < kApolloAICloudMaxBufferedBody) {
        NSUInteger remaining = kApolloAICloudMaxBufferedBody - stream.rawBody.length;
        [stream.rawBody appendData:data.length <= remaining
            ? data : [data subdataWithRange:NSMakeRange(0, remaining)]];
    }
    if (stream.httpStatus >= 200 && stream.httpStatus < 300) {
        [stream.lineBuffer appendData:data];
        [self processBufferedLinesForStream:stream];
        // Whatever remains has no newline yet. A single line past the cap is
        // pathological (real deltas are a few KB) — drop it rather than grow
        // until OOM. The line's later chunks then read as newline-terminated
        // fragments without a `data:` prefix and are skipped harmlessly. The
        // flag fails the request at completion: content past the drop may be
        // missing, and a silently truncated summary is worse than falling back.
        if (stream.lineBuffer.length > kApolloAICloudMaxBufferedBody) {
            ApolloLog(@"[AISummary][cloud] request %@ dropped an oversized SSE line (%lu bytes buffered)",
                      stream.identifier, (unsigned long)stream.lineBuffer.length);
            stream.lineBuffer = [NSMutableData data];
            stream.droppedOversizedLine = YES;
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    [self.lock lock];
    ApolloAICloudStream *stream = self.streamsByTask[@(task.taskIdentifier)];
    [self.lock unlock];
    if (!stream) return;   // superseded/cleaned up already

    // --- Transport-level outcomes ---
    if (error) {
        if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) {
            [self finishTask:task stream:stream code:ApolloAICloudErrorCancelled message:@"Cancelled"];
        } else {
            [self finishTask:task stream:stream code:ApolloAICloudErrorNetwork
                     message:@"Couldn't reach the cloud AI service"];
        }
        return;
    }

    // --- HTTP error statuses ---
    NSInteger status = stream.httpStatus;
    if (status < 200 || status >= 300) {
        NSString *providerMessage = nil;
        NSString *providerParam = nil;
        id json = stream.rawBody.length > 0
            ? [NSJSONSerialization JSONObjectWithData:stream.rawBody options:0 error:NULL] : nil;
        if ([json isKindOfClass:[NSDictionary class]] &&
            [json[@"error"] isKindOfClass:[NSDictionary class]]) {
            NSString *msg = json[@"error"][@"message"];
            if ([msg isKindOfClass:[NSString class]]) providerMessage = msg;
            NSString *param = json[@"error"][@"param"];
            if ([param isKindOfClass:[NSString class]]) providerParam = param;
        }

        if (status == 401 || status == 403) {
            [self finishTask:task stream:stream code:ApolloAICloudErrorAuth
                     message:@"The cloud AI service rejected the API key"];
        } else if (status == 429) {
            [self finishTask:task stream:stream code:ApolloAICloudErrorRateLimited
                     message:@"The cloud AI service is rate limiting requests"];
        } else if (status == 400) {
            NSString *lower = providerMessage.lowercaseString ?: @"";
            BOOL contextOverflow = [lower containsString:@"context"] || [lower containsString:@"too long"] ||
                                   [lower containsString:@"maximum length"];
            if (contextOverflow) {
                [self finishTask:task stream:stream code:ApolloAICloudErrorContextWindow
                         message:@"The request was too large for the cloud model"];
            } else if (!stream.didStripRetry) {
                // Most 400s on a well-formed request are parameter-shape
                // rejections (max_tokens vs max_completion_tokens, temperature
                // on a reasoning model, a reasoning_effort value this model
                // dropped). One targeted retry settles it either way.
                [self stripRetryTask:task stream:stream
                           overrides:ApolloAICloudRetryOverridesForError(providerParam, providerMessage)];
            } else {
                [self finishTask:task stream:stream code:ApolloAICloudErrorProvider
                         message:@"The cloud AI service rejected the request"];
            }
        } else {
            [self finishTask:task stream:stream code:ApolloAICloudErrorProvider
                     message:@"The cloud AI service returned an error"];
        }
        return;
    }

    // --- 2xx ---
    // A stream that closes without a trailing newline leaves its final line —
    // often the last delta — unconsumed in lineBuffer. Flush it as a complete
    // line before judging the result. (Same serial delegate queue as
    // didReceiveData:, so this can't race an in-flight append.)
    if (stream.lineBuffer.length > 0) {
        [stream.lineBuffer appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [self processBufferedLinesForStream:stream];
    }
    if (stream.droppedOversizedLine) {
        // Content after the dropped line is missing; surfacing a truncated
        // summary as success would be silent data loss — fail so the router
        // falls back to on-device.
        [self finishTask:task stream:stream code:ApolloAICloudErrorProvider
                 message:@"The cloud AI service sent an oversized response"];
        return;
    }
    if (stream.streamedErrorObject) {
        // Even with partial content accumulated: an in-stream {"error": ...}
        // event means the output is incomplete — fail rather than surface (and
        // cache) a truncated summary.
        [self finishTask:task stream:stream code:ApolloAICloudErrorProvider
                 message:@"The cloud AI service reported an error"];
        return;
    }
    if (stream.content.length > 0) {
        ApolloLog(@"[AISummary][cloud] request %@ DONE (%lu chars%@)",
                  stream.identifier, (unsigned long)stream.content.length,
                  stream.sawDone ? @"" : @", stream ended without [DONE]");
        [self finishTask:task stream:stream final:[stream.content copy] error:nil];
        return;
    }
    // Empty stream: some providers ignore `stream:true` and answer with one
    // plain JSON completion object.
    id json = stream.rawBody.length > 0
        ? [NSJSONSerialization JSONObjectWithData:stream.rawBody options:0 error:NULL] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSArray *choices = json[@"choices"];
        NSDictionary *message = [choices isKindOfClass:[NSArray class]] && choices.count > 0 &&
                                [choices.firstObject isKindOfClass:[NSDictionary class]]
            ? ((NSDictionary *)choices.firstObject)[@"message"] : nil;
        NSString *content = [message isKindOfClass:[NSDictionary class]] ? message[@"content"] : nil;
        if ([content isKindOfClass:[NSString class]] && content.length > 0) {
            ApolloLog(@"[AISummary][cloud] request %@ DONE (non-streamed, %lu chars)",
                      stream.identifier, (unsigned long)content.length);
            [self finishTask:task stream:stream final:content error:nil];
            return;
        }
    }
    [self finishTask:task stream:stream code:ApolloAICloudErrorProvider
             message:@"The cloud AI service returned an empty response"];
}

@end
