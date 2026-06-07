import SwiftUI
import WidgetKit

/// Calendar widget: a single locked photo-of-the-day with the date overlaid in
/// one of several styles. Tapping opens the source post in Apollo.
struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        WidgetShell(entry: entry) {
            calendarBackground(entry, fallback: BlueGradient())
        } content: { renders in
            let post = renders[0].post
            ZStack {
                overlay(date: entry.date, style: entry.calendarStyle)
                if entry.calendarShowTitle { titleOverlay(post.title, style: entry.calendarStyle) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opensInApollo(post)
        }
    }

    // MARK: scale

    private var small: Bool { family == .systemSmall }
    private func s(_ base: CGFloat) -> CGFloat { small ? base * 0.72 : base }

    // MARK: date strings

    private func text(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(format)
        // setLocalizedDateFormatFromTemplate reorders to locale; for fixed
        // single-field templates that's fine.
        f.dateFormat = format
        return f.string(from: date)
    }
    private func weekday(_ d: Date, short: Bool) -> String { text(d, short ? "EEE" : "EEEE") }
    private func dayNum(_ d: Date) -> String { text(d, "d") }
    private func month(_ d: Date, short: Bool) -> String { text(d, short ? "MMM" : "MMMM") }
    private func year(_ d: Date) -> String { text(d, "yyyy") }

    // MARK: overlays

    @ViewBuilder private func overlay(date: Date, style: CalendarStyle) -> some View {
        switch style {
        case .minimal: minimalStyle(date)
        case .card:    cardStyle(date)
        case .poster:  posterStyle(date)
        case .pill:    pillStyle(date)
        case .stamp:   stampStyle(date)
        }
    }

    private var shadow: some ViewModifier { TextShadow() }

    /// Big day number with small weekday/month, anchored bottom-left.
    private func minimalStyle(_ d: Date) -> some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(weekday(d, short: false).uppercased())
                .font(.system(size: s(14), weight: .semibold)).tracking(2)
            Text(dayNum(d))
                .font(.system(size: s(74), weight: .heavy)).monospacedDigit()
            Text("\(month(d, short: false)) \(year(d))")
                .font(.system(size: s(15), weight: .medium))
        }
        .foregroundStyle(.white)
        .modifier(TextShadow())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(s(14))
        .background(alignment: .bottom) { bottomScrim }
    }

    /// Translucent calendar-tile (red header strip / day / month), bottom-left.
    private func cardStyle(_ d: Date) -> some View {
        VStack(spacing: 0) {
            Text(weekday(d, short: true).uppercased())
                .font(.system(size: s(13), weight: .heavy)).tracking(1)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, s(4))
                .background(Color(red: 0.92, green: 0.26, blue: 0.21))
            VStack(spacing: -2) {
                Text(dayNum(d))
                    .font(.system(size: s(40), weight: .bold)).monospacedDigit()
                    .foregroundStyle(.primary)
                Text(month(d, short: true).uppercased())
                    .font(.system(size: s(12), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, s(14)).padding(.vertical, s(7))
        }
        .frame(width: s(96))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: s(16), style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(s(13))
    }

    /// Centered large stacked typography across the image.
    private func posterStyle(_ d: Date) -> some View {
        VStack(spacing: small ? 0 : 2) {
            Text(weekday(d, short: false).uppercased())
                .font(.system(size: s(16), weight: .bold)).tracking(4)
            Text(dayNum(d))
                .font(.system(size: s(92), weight: .black)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("\(month(d, short: false).uppercased()) · \(year(d))")
                .font(.system(size: s(15), weight: .semibold)).tracking(2)
        }
        .foregroundStyle(.white)
        .modifier(TextShadow())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.black.opacity(0.28) }
    }

    /// Compact capsule, top-left.
    private func pillStyle(_ d: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: s(12), weight: .bold))
            Text("\(weekday(d, short: true)) · \(month(d, short: true)) \(dayNum(d))")
                .font(.system(size: s(14), weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, s(12)).padding(.vertical, s(7))
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(s(12))
    }

    /// Magazine-style ruled date, top-left, serif.
    private func stampStyle(_ d: Date) -> some View {
        VStack(alignment: .leading, spacing: s(3)) {
            Text(month(d, short: true).uppercased())
                .font(.system(size: s(15), weight: .bold, design: .serif)).tracking(3)
            Rectangle().fill(.white).frame(width: s(34), height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(dayNum(d))
                    .font(.system(size: s(44), weight: .black, design: .serif)).monospacedDigit()
                Text(weekday(d, short: true).lowercased())
                    .font(.system(size: s(14), weight: .regular, design: .serif))
            }
        }
        .foregroundStyle(.white)
        .modifier(TextShadow())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(s(15))
        .background(alignment: .top) { topScrim }
    }

    // MARK: title

    /// Optional post title, placed at the opposite edge from each style's date
    /// anchor so the two never collide.
    @ViewBuilder private func titleOverlay(_ title: String, style: CalendarStyle) -> some View {
        let bottomAnchored = (style == .minimal || style == .card)
        Text(title)
            .font(.system(size: s(12), weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(2).minimumScaleFactor(0.8)
            .modifier(TextShadow())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, s(14)).padding(.vertical, s(10))
            .background(alignment: bottomAnchored ? .top : .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: bottomAnchored ? .bottom : .top,
                               endPoint: bottomAnchored ? .top : .bottom)
                    .padding(-10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: bottomAnchored ? .top : .bottom)
    }

    // MARK: scrims

    private var bottomScrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            .padding(-24).allowsHitTesting(false)
    }
    private var topScrim: some View {
        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            .padding(-24).allowsHitTesting(false)
    }
}

/// Shared legibility shadow for text laid directly over a photo.
private struct TextShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

/// Full-bleed image background or gradient fallback (mirrors MediaViews, but the
/// Calendar widget always fills with the locked photo).
@ViewBuilder private func calendarBackground(_ entry: WidgetEntry, fallback: some View) -> some View {
    if case .posts(let r) = entry.state, let data = r.first?.imageData, let img = imageFromData(data) {
        img.resizable().scaledToFill()
    } else {
        fallback
    }
}
