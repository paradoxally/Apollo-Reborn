import AppIntents
import WidgetKit
import Foundation

/// Interactive "show me another" button intent for Showerthoughts.
///
/// EXPERIMENT: interactive widget buttons require the AppIntents runtime — the
/// same subsystem whose metadata did NOT survive Feather's re-sign for widget
/// *configuration* (which is why config uses SiriKit). Rendering is unaffected
/// either way (config is still SiriKit); this only tests whether AppIntents
/// *perform()* fires under sideloading. If it doesn't, the button is a no-op
/// and we fall back to a tap-to-open affordance.
struct NextShowerthoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Showerthought"
    static var description = IntentDescription("Show another showerthought.")

    func perform() async throws -> some IntentResult {
        ThoughtRotation.advance()
        // Returning reloads the timeline; the provider rotates to the next post.
        return .result()
    }
}

/// Persisted offset that the provider uses to pick which cached post shows
/// first. Bumped by the button; lives in the extension's own UserDefaults.
enum ThoughtRotation {
    private static let defaults = UserDefaults.standard
    private static let key = "rw.showerthoughtOffset"

    static var offset: Int { defaults.integer(forKey: key) }
    static func advance() { defaults.set(offset + 1, forKey: key) }

    /// Rotate `posts` so the current offset is first.
    static func rotated<T>(_ posts: [T]) -> [T] {
        guard posts.count > 1 else { return posts }
        let off = ((offset % posts.count) + posts.count) % posts.count
        return Array(posts[off...] + posts[..<off])
    }
}
