import WidgetKit
import Foundation

/// A post plus its (optional, pre-downloaded) image bytes, ready to render.
struct RenderPost: Hashable {
    let post: RedditPost
    let imageData: Data?
}

/// Shared timeline entry for every Reborn widget.
/// `.posts` holds one element for single-post widgets, several for Feed.
struct WidgetEntry: TimelineEntry {
    enum State: Hashable {
        case posts([RenderPost])
        case needsSetup
        case error(String)
        case loading
    }
    let date: Date
    let state: State

    static let loading = WidgetEntry(date: Date(), state: .loading)
}

/// Per-widget on-disk cache of the last successful text posts (no images) so a
/// widget keeps showing real content when offline or rate-limited.
enum PostCache {
    private static let defaults = UserDefaults.standard
    private static func key(_ k: String) -> String { "rw.cache.\(k)" }

    static func save(_ posts: [RedditPost], key k: String) {
        if let data = try? JSONEncoder().encode(posts) { defaults.set(data, forKey: key(k)) }
    }
    static func load(_ k: String) -> [RedditPost] {
        guard let data = defaults.data(forKey: key(k)),
              let posts = try? JSONDecoder().decode([RedditPost].self, from: data) else { return [] }
        return posts
    }
}

// MARK: - Timeline helpers

private let rotateInterval: TimeInterval = 15 * 60   // visible post changes this often
private let postsPerTimeline = 8                     // → ~2h timeline, then refetch fresh data

/// One entry per post, each shown for `rotateInterval`, then refresh.
func rotatingTimeline(_ renders: [RenderPost], refreshIn: TimeInterval? = nil) -> Timeline<WidgetEntry> {
    let now = Date()
    let chosen = Array(renders.prefix(postsPerTimeline))
    guard !chosen.isEmpty else { return singleEntry(.error("Nothing to show."), refreshIn: 1800) }
    var entries: [WidgetEntry] = []
    for (i, r) in chosen.enumerated() {
        entries.append(WidgetEntry(date: now.addingTimeInterval(Double(i) * rotateInterval),
                                   state: .posts([r])))
    }
    let refresh = now.addingTimeInterval(refreshIn ?? Double(chosen.count) * rotateInterval)
    return Timeline(entries: entries, policy: .after(refresh))
}

/// A single entry holding many posts (Feed), refreshed periodically.
func listTimeline(_ renders: [RenderPost], refreshIn: TimeInterval = 30 * 60) -> Timeline<WidgetEntry> {
    let entry = WidgetEntry(date: Date(), state: .posts(renders))
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(refreshIn)))
}

func singleEntry(_ state: WidgetEntry.State, refreshIn: TimeInterval) -> Timeline<WidgetEntry> {
    Timeline(entries: [WidgetEntry(date: Date(), state: state)],
             policy: .after(Date().addingTimeInterval(refreshIn)))
}

func errorMessage(_ error: Error) -> String {
    if let e = error as? RedditAppOnlyClient.ClientError {
        switch e {
        case .http(401), .http(403): return "Reddit rejected the credentials. Re-copy the setup code."
        case .http(404): return "Subreddit not found."
        case .http(429): return "Rate limited by Reddit. Will retry shortly."
        case .http(let code): return "Reddit error \(code)."
        case .badResponse, .noToken: return "Couldn't reach Reddit."
        }
    }
    return "Couldn't load posts."
}

/// Shared driver: parse creds → fetch (with cache fallback) → hand posts to a
/// per-widget `assemble` closure that does image downloads + timeline building.
func runPostTimeline(
    code: String?,
    cacheKey: String,
    fetch: @escaping (RedditAppOnlyClient) async throws -> [RedditPost],
    assemble: @escaping ([RedditPost]) async -> Timeline<WidgetEntry>,
    completion: @escaping (Timeline<WidgetEntry>) -> Void
) {
    guard let creds = SetupCode.resolve(code) else {
        rwLog.error("runPostTimeline: setup code missing/invalid")
        completion(singleEntry(.needsSetup, refreshIn: 60 * 60))
        return
    }
    Task {
        let client = RedditAppOnlyClient(clientID: creds.clientID, userAgent: creds.resolvedUserAgent)
        do {
            var posts = try await fetch(client)
            rwLog.log("runPostTimeline[\(cacheKey, privacy: .public)]: fetched \(posts.count)")
            if posts.isEmpty { posts = PostCache.load(cacheKey) }
            guard !posts.isEmpty else {
                completion(singleEntry(.error("Nothing to show."), refreshIn: 30 * 60))
                return
            }
            PostCache.save(posts, key: cacheKey)
            completion(await assemble(posts))
        } catch {
            rwLog.error("runPostTimeline[\(cacheKey, privacy: .public)]: \(String(describing: error), privacy: .public)")
            let cached = PostCache.load(cacheKey)
            if !cached.isEmpty { completion(await assemble(cached)) }
            else { completion(singleEntry(.error(errorMessage(error)), refreshIn: 15 * 60)) }
        }
    }
}

// MARK: - assemble helpers (image downloads)

/// Text-only rotating posts (Showerthoughts, Jokes).
func assembleText(_ posts: [RedditPost]) -> Timeline<WidgetEntry> {
    rotatingTimeline(posts.map { RenderPost(post: $0, imageData: nil) })
}

/// Rotating posts each with a downloaded preview image (Single Post, Photo).
/// Capped + concurrent so we stay within WidgetKit's timeline budget.
func assembleWithImages(_ posts: [RedditPost], maxPixel: Int, limit: Int = 6) async -> Timeline<WidgetEntry> {
    let chosen = Array(posts.prefix(limit))
    let renders = await downloadImages(chosen, keyPath: { $0.imageURL ?? $0.thumbnailURL }, maxPixel: maxPixel)
    return rotatingTimeline(renders)
}

/// Download images for `posts` concurrently, preserving order.
func downloadImages(_ posts: [RedditPost],
                    keyPath: @escaping (RedditPost) -> String?,
                    maxPixel: Int) async -> [RenderPost] {
    await withTaskGroup(of: (Int, Data?).self) { group in
        for (i, p) in posts.enumerated() {
            group.addTask { (i, await ImageLoader.fetchDownsampled(keyPath(p), maxPixel: maxPixel)) }
        }
        var byIndex: [Int: Data?] = [:]
        for await (i, data) in group { byIndex[i] = data }
        return posts.enumerated().map { RenderPost(post: $1, imageData: byIndex[$0] ?? nil) }
    }
}
