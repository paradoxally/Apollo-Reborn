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
    /// Cache key of the widget that produced this entry, so interactive buttons
    /// know which widget's rotation to advance. Nil for non-content states.
    var rotationKey: String? = nil
    /// Post widget rendering config (ignored by the other widgets).
    var display: DisplayMode = .standard
    var showPreview: Bool = false

    static let loading = WidgetEntry(date: Date(), state: .loading)
}

/// Stamp the Post widget's render config onto every entry of a built timeline,
/// so the view can switch metadata density / preview text. Keeps the shared
/// timeline builders config-agnostic — only the Post provider opts in.
func stamped(_ timeline: Timeline<WidgetEntry>, display: DisplayMode, showPreview: Bool) -> Timeline<WidgetEntry> {
    let entries = timeline.entries.map { e -> WidgetEntry in
        var e = e
        e.display = display
        e.showPreview = showPreview
        return e
    }
    return Timeline(entries: entries, policy: timeline.policy)
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

// Freshness model (fixes "I keep seeing posts I've already seen"):
//
//   * The timeline is LONG and WALL-CLOCK-SEEDED, not a short 8-entry strip.
//     WidgetKit reloads on a stingy budget, so a 2h timeline meant the system
//     pinned the last entry for hours. We instead emit entries across an
//     ~8h window, and the post shown at any moment is a pure function of the
//     wall-clock slot — so glances at different times rotate even with no
//     reload, and consecutive reloads continue seamlessly instead of
//     restarting on the same post.
//   * We rotate through the ENTIRE fetched pool (up to ~25) for text widgets,
//     not just the first 8.
//   * `orderedPool` applies a per-day deterministic shuffle so the cycle order
//     varies day to day (combats "same 25 in the same order"), plus the manual
//     button offset.
private let slotInterval: TimeInterval = 25 * 60     // a glance within 25 min shows the same post
private let refreshWindow: TimeInterval = 8 * 3600   // span the timeline this far, then ask to refetch
private let maxEntries = 24                          // safety cap on timeline length
let imageBatchSize = 8                               // images downloaded per fetch (image widgets)

/// Long, wall-clock-seeded rotation. `renders` is already in final display
/// order; entry for slot S shows `renders[S % count]`, so the visible post
/// depends only on the time of day, not on when the timeline was generated.
func steppingTimeline(_ renders: [RenderPost], key: String? = nil) -> Timeline<WidgetEntry> {
    let now = Date()
    let count = renders.count
    guard count > 0 else { return singleEntry(.error("Nothing to show."), refreshIn: 1800) }

    let slotNow = Int(now.timeIntervalSince1970 / slotInterval)
    let entryCount = min(maxEntries, max(1, Int(refreshWindow / slotInterval)))
    var entries: [WidgetEntry] = []
    for i in 0..<entryCount {
        let slot = slotNow + i
        let idx = ((slot % count) + count) % count
        // First entry uses `now` (mid-slot) so it's never in the future; the
        // rest land on exact slot boundaries.
        let date = i == 0 ? now : Date(timeIntervalSince1970: Double(slot) * slotInterval)
        entries.append(WidgetEntry(date: date, state: .posts([renders[idx]]), rotationKey: key))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshWindow)))
}

/// Current wall-clock rotation slot (advances every `slotInterval`). Used to
/// pick an advancing image batch so each refetch shows fresh images.
func currentSlot() -> Int { Int(Date().timeIntervalSince1970 / slotInterval) }

/// Deterministic per-day shuffle of `posts` (so the rotation order varies day
/// to day) followed by the manual button offset. Stable within a day, so a
/// given time slot maps consistently until midnight.
func orderedPool(_ key: String, _ posts: [RedditPost]) -> [RedditPost] {
    guard posts.count > 1 else { return posts }
    let day = Int(Date().timeIntervalSince1970 / 86_400)
    var rng = SeededRNG(seed: UInt64(bitPattern: Int64(day)) &* 0x9E3779B97F4A7C15 ^ fnv1a(key))
    var arr = posts
    arr.shuffle(using: &rng)
    return Rotation.rotated(key, arr)
}

/// Small splitmix64 PRNG so `shuffle(using:)` is reproducible from a seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001B3 }
    return h
}

/// A single entry holding many posts (Feed), refreshed periodically.
func listTimeline(_ renders: [RenderPost], key: String? = nil, refreshIn: TimeInterval = 30 * 60) -> Timeline<WidgetEntry> {
    let entry = WidgetEntry(date: Date(), state: .posts(renders), rotationKey: key)
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

/// Text-only rotation (Showerthoughts, Jokes, text-mode Post). Rotates through
/// the FULL ordered pool so a glance hours later shows something new.
func assembleText(_ posts: [RedditPost], key: String) -> Timeline<WidgetEntry> {
    let ordered = orderedPool(key, posts)
    return steppingTimeline(ordered.map { RenderPost(post: $0, imageData: nil) }, key: key)
}

/// Rotating posts each with a downloaded preview image (Photo, image Post).
/// Only `imageBatchSize` images are downloaded per fetch (WidgetKit budget),
/// but the batch start advances with the wall-clock slot, so every refetch
/// pulls a fresh slice of the pool instead of the same first few.
func assembleWithImages(_ posts: [RedditPost], key: String, maxPixel: Int, limit: Int = imageBatchSize) async -> Timeline<WidgetEntry> {
    let ordered = orderedPool(key, posts)
    let count = ordered.count
    let base = currentSlot()
    let take = min(limit, count)
    let batch = (0..<take).map { ordered[(((base + $0) % count) + count) % count] }
    let renders = await downloadImages(batch, keyPath: { $0.imageURL ?? $0.thumbnailURL }, maxPixel: maxPixel)
    return steppingTimeline(renders, key: key)
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
