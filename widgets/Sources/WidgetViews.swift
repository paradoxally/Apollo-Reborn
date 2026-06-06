import SwiftUI
import WidgetKit
import UIKit

/// Shared shell: routes the entry state to content vs. message, and paints the
/// container background. Non-content states are color-coded (orange=loading,
/// red=needsSetup, purple=error) so issues are obvious at a glance; content
/// uses each widget's own background.
struct WidgetShell<Content: View, Background: View>: View {
    let entry: WidgetEntry
    @ViewBuilder var background: () -> Background
    @ViewBuilder var content: ([RenderPost]) -> Content

    var body: some View {
        routed
            .containerBackground(for: .widget) { backgroundColor }
    }

    @ViewBuilder private var routed: some View {
        switch entry.state {
        case .posts(let renders) where !renders.isEmpty:
            content(renders)
        case .posts:
            MessageView(icon: "tray", title: "Nothing here", detail: "No posts to show right now.")
        case .loading:
            MessageView(icon: "arrow.clockwise", title: "Loading…", detail: "Fetching posts.")
        case .needsSetup:
            MessageView(icon: "key.horizontal.fill", title: "Setup needed",
                        detail: "In Apollo: Settings → Apollo Reborn → Copy Widget Setup Code, then Edit any one widget and paste it once — all widgets share it.")
        case .error(let msg):
            MessageView(icon: "exclamationmark.triangle.fill", title: "Error", detail: msg)
        }
    }

    @ViewBuilder private var backgroundColor: some View {
        switch entry.state {
        case .posts(let r) where !r.isEmpty: background()
        case .loading: Color.orange
        case .needsSetup: Color.red
        case .error, .posts: Color.purple
        }
    }
}

struct MessageView: View {
    @Environment(\.widgetFamily) private var family
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title).fontWeight(.bold)
            }
            .font(.caption)
            .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .minimumScaleFactor(0.8)
                .lineLimit(family == .systemSmall ? 4 : 6)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Reusable bits

/// Small header: an SF Symbol + subreddit/label.
struct WidgetHeader: View {
    let icon: String
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2).fontWeight(.bold)
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.95))
    }
}

/// score · comments footer.
struct PostStats: View {
    let post: RedditPost
    var body: some View {
        HStack(spacing: 8) {
            Label("\(post.score.abbreviated)", systemImage: "arrow.up")
            Label("\(post.numComments.abbreviated)", systemImage: "bubble.right")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.85))
        .labelStyle(.titleAndIcon)
    }
}

extension Int {
    /// 1500 → "1.5k", 23000 → "23k".
    var abbreviated: String {
        if self >= 10_000 { return "\(self / 1000)k" }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1000) }
        return "\(self)"
    }
}

/// The blue gradient used for text widgets.
struct BlueGradient: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.0, green: 0.48, blue: 0.93),
                                Color(red: 0.20, green: 0.62, blue: 0.98)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// Apply a deep link that opens the post in Apollo, if available.
    @ViewBuilder func opensInApollo(_ post: RedditPost) -> some View {
        if let url = post.apolloURL { self.widgetURL(url) } else { self }
    }
}

func imageFromData(_ data: Data?) -> Image? {
    guard let data, let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
}
