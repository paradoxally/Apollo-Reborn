import SwiftUI
import WidgetKit
import AppIntents

/// Showerthoughts: a single rotating thought on the blue gradient.
struct ShowerthoughtsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        WidgetShell(entry: entry) {
            BlueGradient()
        } content: { renders in
            let post = renders[0].post
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill").font(.caption2)
                    Text("Showerthoughts").font(.caption2).fontWeight(.bold)
                    Spacer()
                    // Tap for another thought (interactive AppIntent button).
                    Button(intent: NextShowerthoughtIntent()) {
                        Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.95))
                Spacer(minLength: 2)
                Text(post.title)
                    .font(titleFont).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(family == .systemLarge ? 8 : (family == .systemSmall ? 6 : 4))
                Spacer(minLength: 2)
                if family != .systemSmall {
                    Text("u/\(post.author)").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
            .opensInApollo(post)
        }
    }

    private var titleFont: Font {
        switch family {
        case .systemSmall: return .system(size: 15)
        case .systemLarge: return .system(size: 24)
        default: return .system(size: 18)
        }
    }
}

/// Jokes: r/Jokes — title is the setup, selftext is the punchline.
struct JokesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        WidgetShell(entry: entry) {
            LinearGradient(colors: [Color(red: 0.85, green: 0.35, blue: 0.10),
                                    Color(red: 0.97, green: 0.55, blue: 0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } content: { renders in
            let post = renders[0].post
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "face.smiling.fill", label: "r/Jokes")
                Spacer(minLength: 2)
                Text(post.title)
                    .font(setupFont).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(family == .systemSmall ? 3 : 4)
                if !post.selftext.isEmpty {
                    Text(post.selftext)
                        .font(punchlineFont)
                        .foregroundStyle(.white.opacity(0.95))
                        .minimumScaleFactor(0.7)
                        .lineLimit(family == .systemLarge ? 8 : (family == .systemSmall ? 3 : 4))
                }
                Spacer(minLength: 2)
            }
            .opensInApollo(post)
        }
    }

    private var setupFont: Font { family == .systemLarge ? .system(size: 20) : .system(size: 15) }
    private var punchlineFont: Font { family == .systemLarge ? .system(size: 22, weight: .bold) : .system(size: 16, weight: .bold) }
}
