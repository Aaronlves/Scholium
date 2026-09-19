import Foundation
import SwiftUI

enum ScholiumMotion {
    static let libraryWorkspaceDuration: TimeInterval = 0.14

    /// Native preview window motion; reduced motion uses only a short fade.
    static func contentPreviewDuration(closing: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.12 : closing ? 0.20 : 0.26
    }

    static func documentReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.36)
    }

    static func documentRevealTransition(
        showingDocument: Bool,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return showingDocument
            ? .opacity.combined(with: .scale(scale: 0.995))
            : .opacity
    }

    static func disclosure(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func chatMessageArrival(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static func outlineInteraction(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.38)
    }

    static func symbolReplacement(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func symbolReplacementContentTransition(
        reduceMotion: Bool
    ) -> ContentTransition {
        reduceMotion ? .identity : .symbolEffect(.replace)
    }

}
