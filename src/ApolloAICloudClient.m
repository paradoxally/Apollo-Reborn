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
//  - Parameter shaping: reasoning models (gpt-5*, o<digit>*) get
//    reasoning_effort=minimal + max_completion_tokens and no temperature (they
//    reject it, and thinking latency/cost is pure waste for a 3-sentence
//    summary); everything else gets temperature=0 + max_tokens. If a provider
//    rejects the shape with an HTTP 400 naming a parameter, the request is
//    transparently re-issued ONCE with the optional params stripped and the
//    token-cap key swapped.
//  - Privacy: never log the API key, the request body, or any streamed text —
//    diagnostics are identifier/status/byte-count only, matching the
//    "never log generated text" discipline in ApolloAISummary.xm.
//

#import "ApolloAICloudClient.h"
#import "ApolloCommon.h"
#import "ApolloState.h"

#include <ctype.h>

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
        // Idle timeout between chunks; the overall bound is ApolloAISummary's
        // generation watchdog, which cancels us (-> code 6).
        config.timeoutIntervalForRequest = 60.0;
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
    if (bare.length >= 2 && [bare characterAtIndex:0] == 'o' &&
        isdigit([bare characterAtIndex:1])) return YES;
    return NO;
}

// Returns nil for a base URL that NSURL can't parse (user-entered setting —
// e.g. contains spaces). Callers must treat nil as a hard config error rather
// than build a request from it: requestWithURL:nil crashes/creates an invalid
// task before any of the error mapping in didCompleteWithError can run.
static NSURL *ApolloAICloudChatCompletionsURL(void) {
    NSString *base = sCloudAIBaseURL ?: @"";
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    return [NSURL URLWithString:[base stringByAppendingString:@"/chat/completions"]];
}

// stripped=YES is the retry shape: no temperature/reasoning_effort, and the
// token-cap key swapped relative to the primary shape.
static NSData *ApolloAICloudRequestBody(NSString *text, NSString *instructions,
                                        NSInteger maxTokens, BOOL stripped) {
    NSString *model = sCloudAIModel ?: @"gpt-5-mini";
    BOOL reasoning = ApolloAICloudIsReasoningModel(model);
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"model": model,
        @"stream": @YES,
        @"messages": @[
            @{@"role": @"system", @"content": instructions ?: @""},
            @{@"role": @"user", @"content": text ?: @""},
        ],
    }];
    // Primary: reasoning models take max_completion_tokens, others max_tokens.
    // Stripped retry: swap the key, drop every optional knob.
    BOOL useCompletionTokensKey = stripped ? !reasoning : reasoning;
    if (maxTokens > 0) {
        body[useCompletionTokensKey ? @"max_completion_tokens" : @"max_tokens"] = @(maxTokens);
    }
    if (!stripped) {
        if (reasoning) {
            body[@"reasoning_effort"] = @"minimal";
        } else {
            body[@"temperature"] = @0;
        }
    }
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
}

- (NSURLSessionDataTask *)taskForStream:(ApolloAICloudStream *)stream stripped:(BOOL)stripped {
    NSURL *url = ApolloAICloudChatCompletionsURL();
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[@"Bearer " stringByAppendingString:sCloudAIAPIKey ?: @""] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = ApolloAICloudRequestBody(stream.text, stream.instructions,
                                                stream.maximumResponseTokens, stripped);
    return [self.session dataTaskWithRequest:request];
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

    NSURLSessionDataTask *task = [self taskForStream:stream stripped:NO];
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

// Re-issues the request once with optional parameters stripped, transferring
// the context to the new task. Returns without firing onComplete.
- (void)stripRetryTask:(NSURLSessionTask *)task stream:(ApolloAICloudStream *)stream {
    ApolloLog(@"[AISummary][cloud] request %@ rejected (HTTP 400); retrying with stripped parameters",
              stream.identifier);
    stream.didStripRetry = YES;
    stream.lineBuffer = [NSMutableData data];
    stream.rawBody = [NSMutableData data];
    stream.content = [NSMutableString string];
    stream.httpStatus = 0;
    stream.sawDone = NO;
    stream.streamedErrorObject = NO;

    NSURLSessionDataTask *retryTask = [self taskForStream:stream stripped:YES];
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
        NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange lineEnd = [stream.lineBuffer rangeOfData:newline
                                                 options:0
                                                   range:NSMakeRange(0, stream.lineBuffer.length)];
        if (lineEnd.location == NSNotFound) return;

        NSData *lineData = [stream.lineBuffer subdataWithRange:NSMakeRange(0, lineEnd.location)];
        [stream.lineBuffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(lineEnd)) withBytes:NULL length:0];

        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r"]];
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
        id json = stream.rawBody.length > 0
            ? [NSJSONSerialization JSONObjectWithData:stream.rawBody options:0 error:NULL] : nil;
        if ([json isKindOfClass:[NSDictionary class]] &&
            [json[@"error"] isKindOfClass:[NSDictionary class]]) {
            NSString *msg = json[@"error"][@"message"];
            if ([msg isKindOfClass:[NSString class]]) providerMessage = msg;
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
                // on a reasoning model, unknown reasoning_effort). One retry
                // with the minimal body settles it either way.
                [self stripRetryTask:task stream:stream];
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
    if (stream.streamedErrorObject && stream.content.length == 0) {
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
