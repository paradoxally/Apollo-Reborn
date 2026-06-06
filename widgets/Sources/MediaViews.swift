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
        if isAccessoryFamily(family) {
            AccessoryPostView(entry: entry, label: "Post", icon: "doc.text.image")
        } else {
            homeBody
        }
    }

    private var homeBody: some View {
        WidgetShell(entry: entry) {
            mediaBackground(entry, fallback: BlueGradient())
        } content: { renders in
            let post = renders[0].post
            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 0)
                Text(post.title)
                    .font(.system(size: family == .systemSmall ? 14 : 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(family == .systemSmall ? 3 : 4)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                // Small has no room for the subreddit; larger sizes show it.
                StatsLine(post: post,
                          showSubreddit: family != .systemSmall,
                          showComments: family != .systemSmall)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.top, 30)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
                    .padding(-24)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { NextOverlayButton(rotationKey: entry.rotationKey) }
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
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text(post.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    .padding(-24)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { NextOverlayButton(rotationKey: entry.rotationKey) }
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
            Color(red: 0.11, green: 0.12, blue: 0.14)
        } content: { renders in
            let sub = renders.first?.post.subreddit ?? ""
            VStack(alignment: .leading, spacing: 7) {
                WidgetHeader(label: "r/\(sub)",
                             tint: Color(red: 0.40, green: 0.62, blue: 1.0),
                             trailing: AnyView(ReloadButton(kind: "FeedWidget")))
                let rows = Array(renders.prefix(rowCount))
                ForEach(Array(rows.enumerated()), id: \.element.post.id) { idx, render in
                    rowLink(render)
                    if idx != rows.count - 1 {
                        Divider().overlay(.white.opacity(0.10))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(render.post.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.85)
                StatsLine(post: render.post)
            }
            Spacer(minLength: 0)
            // Apollo puts the thumbnail on the trailing edge.
            if let img = imageFromData(render.imageData) {
                img.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
