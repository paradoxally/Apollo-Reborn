import SwiftUI
import WidgetKit

/// Apple-Shortcuts-style subreddit tiles: a colored rounded card per subreddit
/// with its icon top-left and name bottom-left. Tapping opens the sub in Apollo.
struct ShortcutsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShortcutsEntry

    private var columns: Int { 2 }
    private var maxItems: Int {
        switch family {
        case .systemLarge: return 8   // 2 × 4
        case .systemMedium: return 6  // 2 × 3
        default: return 4             // 2 × 2 (small)
        }
    }

    var body: some View {
        Group {
            if entry.needsConfig {
                MessageView(icon: "square.grid.2x2",
                            title: "Add subreddits",
                            detail: "Edit this widget and type subreddits (comma or space separated), e.g. aww, apple, EarthPorn.")
            } else {
                grid
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.09, green: 0.10, blue: 0.12) }
    }

    private var grid: some View {
        let items = Array(entry.items.prefix(maxItems))
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< min($0 + columns, items.count)])
        }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.subreddit) { tile($0) }
                    // Pad a short final row so tiles keep their width.
                    if row.count < columns {
                        ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func tile(_ item: ShortcutItem) -> some View {
        let body = VStack(alignment: .leading, spacing: 0) {
            avatar(item)
            Spacer(minLength: 4)
            Text(item.subreddit)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileColor(item), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        if let url = RedditPost.subredditURL(item.subreddit) {
            Link(destination: url) { body }
        } else {
            body
        }
    }

    private func avatar(_ item: ShortcutItem) -> some View {
        let size: CGFloat = 30
        return Group {
            if let img = imageFromData(item.iconData) {
                img.resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(.white.opacity(0.25))
                    Text(String(item.subreddit.prefix(1)).uppercased())
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            }
        }
    }

    /// Brand color from the subreddit when available, else a stable palette pick.
    private func tileColor(_ item: ShortcutItem) -> Color {
        if let c = Color(hex: item.colorHex) { return c }
        let palette: [Color] = [
            Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.95, green: 0.62, blue: 0.20),
            Color(red: 0.30, green: 0.72, blue: 0.40), Color(red: 0.90, green: 0.35, blue: 0.35),
            Color(red: 0.55, green: 0.40, blue: 0.92), Color(red: 0.20, green: 0.68, blue: 0.70),
            Color(red: 0.92, green: 0.45, blue: 0.62), Color(red: 0.45, green: 0.50, blue: 0.95),
        ]
        return palette[abs(item.subreddit.lowercased().hashValue) % palette.count]
    }
}
