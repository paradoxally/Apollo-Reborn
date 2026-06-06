import WidgetKit
import Foundation

// MARK: Subreddit config helpers

private func resolvedSubreddit(_ raw: String?, default def: String) -> String {
    let s = RedditPost.normalizeSubreddit(raw ?? "")
    return s.isEmpty ? def : s
}

// MARK: Jokes (fixed r/Jokes, text)

struct JokesProvider: IntentTimelineProvider {
    typealias Entry = WidgetEntry
    typealias Intent = JokesConfigurationIntent

    func placeholder(in context: Context) -> WidgetEntry { .loading }

    func getSnapshot(for configuration: Intent, in context: Context,
                     completion: @escaping (WidgetEntry) -> Void) {
        if let first = PostCache.load("jokes").first {
            completion(WidgetEntry(date: Date(), state: .posts([RenderPost(post: first, imageData: nil)])))
        } else { completion(.loading) }
    }

    func getTimeline(for configuration: Intent, in context: Context,
                     completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        runPostTimeline(
            code: configuration.setupCode, cacheKey: "jokes",
            fetch: { try await $0.topPosts(subreddit: "Jokes", sort: .top, limit: 25) },
            assemble: { assembleText($0.filter { !$0.selftext.isEmpty }, key: "jokes") },
            completion: completion)
    }
}

// MARK: Single Post (configurable subreddit, image)

struct SinglePostProvider: IntentTimelineProvider {
    typealias Entry = WidgetEntry
    typealias Intent = SubredditConfigurationIntent

    func placeholder(in context: Context) -> WidgetEntry { .loading }

    func getSnapshot(for configuration: Intent, in context: Context,
                     completion: @escaping (WidgetEntry) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "popular")
        if let first = PostCache.load("single.\(sub)").first {
            completion(WidgetEntry(date: Date(), state: .posts([RenderPost(post: first, imageData: nil)])))
        } else { completion(.loading) }
    }

    func getTimeline(for configuration: Intent, in context: Context,
                     completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "popular")
        runPostTimeline(
            code: configuration.setupCode, cacheKey: "single.\(sub)",
            fetch: { try await $0.topPosts(subreddit: sub, sort: .hot, limit: 25) },
            assemble: { await assembleWithImages($0, key: "single.\(sub)", maxPixel: 600) },
            completion: completion)
    }
}

// MARK: Feed (configurable subreddit, list)

struct FeedProvider: IntentTimelineProvider {
    typealias Entry = WidgetEntry
    typealias Intent = SubredditConfigurationIntent

    func placeholder(in context: Context) -> WidgetEntry { .loading }

    func getSnapshot(for configuration: Intent, in context: Context,
                     completion: @escaping (WidgetEntry) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "popular")
        let cached = PostCache.load("feed.\(sub)")
        if !cached.isEmpty {
            completion(WidgetEntry(date: Date(), state: .posts(cached.map { RenderPost(post: $0, imageData: nil) })))
        } else { completion(.loading) }
    }

    func getTimeline(for configuration: Intent, in context: Context,
                     completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "popular")
        runPostTimeline(
            code: configuration.setupCode, cacheKey: "feed.\(sub)",
            fetch: { try await $0.topPosts(subreddit: sub, sort: .hot, limit: 8) },
            assemble: { posts in
                // Download small thumbnails (concurrently) for the rows the large family shows.
                let renders = await downloadImages(Array(posts.prefix(6)),
                                                   keyPath: { $0.thumbnailURL }, maxPixel: 160)
                return listTimeline(renders)
            },
            completion: completion)
    }
}

// MARK: Photo (configurable subreddit, image-only)

struct PhotoProvider: IntentTimelineProvider {
    typealias Entry = WidgetEntry
    typealias Intent = SubredditConfigurationIntent

    func placeholder(in context: Context) -> WidgetEntry { .loading }

    func getSnapshot(for configuration: Intent, in context: Context,
                     completion: @escaping (WidgetEntry) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "EarthPorn")
        if let first = PostCache.load("photo.\(sub)").first {
            completion(WidgetEntry(date: Date(), state: .posts([RenderPost(post: first, imageData: nil)])))
        } else { completion(.loading) }
    }

    func getTimeline(for configuration: Intent, in context: Context,
                     completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let sub = resolvedSubreddit(configuration.subreddit, default: "EarthPorn")
        runPostTimeline(
            code: configuration.setupCode, cacheKey: "photo.\(sub)",
            fetch: { try await $0.topPosts(subreddit: sub, sort: .top, limit: 25).filter { $0.isImagePost } },
            assemble: { await assembleWithImages($0, key: "photo.\(sub)", maxPixel: 800) },
            completion: completion)
    }
}
