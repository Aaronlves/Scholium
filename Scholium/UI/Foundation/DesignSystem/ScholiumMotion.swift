import Foundation
import SwiftUI

enum ScholiumMotion {
    static let sidebarPageDuration: TimeInterval = 0.16
    static let libraryWorkspaceDuration: TimeInterval = 0.14
    static let pdfContentRevealDuration: TimeInterval = 0.16

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

    static func documentNotice(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static func documentNoticeTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: -8))
    }

    static func outlineSettling(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
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
