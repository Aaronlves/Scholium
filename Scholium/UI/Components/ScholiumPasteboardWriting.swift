import AppKit

/// The smallest native boundary for replacing the plain-text pasteboard.
/// Workflows retain success, failure, recovery, and feedback presentation.
@MainActor
protocol PasteboardWriting {
    @discardableResult
    func writeText(_ text: String) -> Bool
}

@MainActor
struct ScholiumPasteboardWriter: PasteboardWriting {
    static let general = ScholiumPasteboardWriter(pasteboard: .general)

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
