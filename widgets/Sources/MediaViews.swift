import SwiftUI
import WidgetKit

/// First render of a .posts entry (for reading the background image).
private func firstRender(_ entry: WidgetEntry) -> RenderPost? {
    if case .posts(let r) = entry.state { return r.first }
    return nil
}

/// Full-bleed image background (iOS 17 containerBackground pattern) or a
/// gradient fallback. A short note is shown when an image was expected but
/// couldn't be loaded, to aid diagnosis.
@ViewBuilder private func mediaBackground(_ entry: WidgetEntry, fallback: some View) -> some View {
    if let data = firstRender(entry)?.imageData, let img = imageFromData(data) {
        img.resizable().scaledToFill()
    } else {
        fallback
    }
}

/// Single Post: top post of a subreddit, full-bleed image with a title scrim.
struct SinglePostWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        WidgetShell(entry: entry) {
            mediaBackground(entry, fallback: BlueGradient())
        } content: { renders in
            let post = renders[0].post
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(icon: "doc.text.image", label: "r/\(post.subreddit)")
                Spacer(minLength: 0)
                Text(post.title)
                    .font(.system(size: family == .systemSmall ? 13 : 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(family == .systemSmall ? 3 : 4)
                if family != .systemSmall { PostStats(post: post) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.top, 30)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .padding(-20)
                    .allowsHitTesting(false)
            }
            .opensInApollo(post)
        }
    }
}

/// Photo: full-bleed top image of a subreddit, minimal chrome.
struct PhotoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        WidgetShell(entry: entry) {
            mediaBackground(entry, fallback: BlueGradient())
        } content: { renders in
            let post = renders[0].post
            VStack {
                Spacer()
                if family != .systemSmall {
                    HStack {
                        Text(post.title).lineLimit(2).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                               startPoint: .top, endPoint: .bottom).padding(-8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opensInApollo(post)
        }
    }
}

/// Feed: a scrolling-style list of a subreddit's top posts. Each row links to
/// its post in Apollo.
struct FeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    private var rowCount: Int {
        switch family {
        case .systemLarge: return 6
        case .systemMedium: return 3
        default: return 2
        }
    }

    var body: some View {
        WidgetShell(entry: entry) {
            Color(red: 0.10, green: 0.11, blue: 0.13)
        } content: { renders in
            let sub = renders.first?.post.subreddit ?? ""
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "list.bullet.below.rectangle", label: "r/\(sub)")
                ForEach(Array(renders.prefix(rowCount)), id: \.post.id) { render in
                    rowLink(render)
                    if render.post.id != renders.prefix(rowCount).last?.post.id {
                        Divider().overlay(.white.opacity(0.12))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func rowLink(_ render: RenderPost) -> some View {
        if let url = render.post.apolloURL {
            Link(destination: url) { row(render) }
        } else {
            row(render)
        }
    }

    private func row(_ render: RenderPost) -> some View {
        HStack(spacing: 8) {
            if let img = imageFromData(render.imageData) {
                img.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(render.post.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if family != .systemSmall { PostStats(post: render.post) }
            }
            Spacer(minLength: 0)
        }
    }
}
