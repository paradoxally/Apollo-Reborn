import Foundation

/// One Reddit post, trimmed to what the widgets render. Shared by every widget.
struct RedditPost: Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var subreddit: String
    var score: Int
    var numComments: Int
    var permalink: String          // "/r/sub/comments/id/slug/"
    var selftext: String           // body text (Jokes punchline, etc.)
    var thumbnailURL: String?      // small thumbnail for feed rows
    var imageURL: String?          // larger preview for Photo / Single Post
    var isImagePost: Bool

    /// Deep link that opens this post natively in Apollo. Apollo rewrites a
    /// reddit.com URL to the apollo:// scheme; we emit that scheme directly so
    /// tapping routes straight into the app (see ApolloCommon.m
    /// ApolloURLByConvertingResolvedURLToApolloScheme).
    var apolloURL: URL? {
        let path = permalink.hasPrefix("/") ? permalink : "/" + permalink
        return URL(string: "apollo://reddit.com\(path)")
    }

    static func subredditURL(_ sub: String) -> URL? {
        let clean = RedditPost.normalizeSubreddit(sub)
        return URL(string: "apollo://reddit.com/r/\(clean)")
    }

    /// Strip "r/", "/r/", leading/trailing slashes and whitespace from a
    /// user-typed subreddit so "r/EarthPorn", "/r/earthporn/", "earthporn" all
    /// normalize the same.
    static func normalizeSubreddit(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/r/", "r/", "/"] where s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }
}

/// Listing sort, mapped to the Reddit API path + time window.
enum WidgetSort {
    case hot, new, top, topWeek, rising

    var path: String {
        switch self {
        case .hot: return "hot"
        case .new: return "new"
        case .top, .topWeek: return "top"
        case .rising: return "rising"
        }
    }
    /// `t` window (only meaningful for the `top` sorts).
    var timeWindow: String? {
        switch self {
        case .top: return "day"
        case .topWeek: return "week"
        default: return nil
        }
    }
}
