import AppKit
import ScholiumContracts

enum DocumentPassageSnapshot {
    /// A complete visible paragraph includes its hidden source identity; a
    /// partial prose selection keeps its exact captured boundaries.
    static func includingParagraphIdentity(
        _ captured: MarkdownSourceSelectionSnapshot, paragraphSpan: SourceSpan
    ) -> MarkdownSourceSelectionSnapshot {
        let source = captured.source
        let note = NoteDocument(relativePath: "Passage.md", rawContent: source)
        let anchor = ParagraphAnchorPlanner.anchors(in: note).first { $0.paragraphSpan == paragraphSpan }
        let contentEnd = anchor?.markerSpan.utf16LowerBound ?? paragraphSpan.utf16UpperBound
        let contentRange = NSRange(location: paragraphSpan.utf16LowerBound, length: contentEnd - paragraphSpan.utf16LowerBound)
        guard let range = Range(contentRange, in: source) else { return captured }
        let content = String(source[range])
        let visible = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = paragraphSpan.utf16LowerBound + content.prefix { $0.isWhitespace }.utf16.count
        if captured.sourceRange.utf16LowerBound >= paragraphSpan.utf16LowerBound,
            captured.sourceRange.utf16LowerBound <= lower,
            captured.sourceRange.utf16UpperBound >= lower + visible.utf16.count,
            captured.sourceRange.utf16UpperBound <= contentEnd
        {
            return DocumentPassageSnapshot.capture(source: source, range: paragraphSpan.nsRange) ?? captured
        }
        return captured
    }

    static func capture(source: String, range: NSRange) -> MarkdownSourceSelectionSnapshot? {
        guard range.location >= 0, range.length > 0,
            range.location <= source.utf16.count, range.length <= source.utf16.count - range.location,
            let selected = Range(range, in: source)
        else { return nil }
        let native = source as NSString
        let upper = range.location + range.length
        return .init(
            source: source, excerpt: String(source[selected]),
            sourceRange: .init(
                utf16LowerBound: range.location, utf16UpperBound: upper,
                line: 1 + source[..<selected.lowerBound].utf8.filter { $0 == 10 }.count,
                column: range.location - native.lineRange(for: NSRange(location: range.location, length: 0)).location + 1,
                endLine: 1 + source[..<selected.upperBound].utf8.filter { $0 == 10 }.count,
                endColumn: upper - native.lineRange(for: NSRange(location: upper, length: 0)).location + 1))
    }
}

enum DocumentPassageAction: String, CaseIterable, Sendable {
    case copyLink, relatedMaterial, addToChat, extract, move, copy

    var title: String {
        switch self {
        case .copyLink: ScholiumL10n.string("Copy Paragraph Link")
        case .relatedMaterial: ScholiumL10n.string("Find Related Material")
        case .addToChat: ScholiumL10n.string("Add to Chat")
        case .extract: ScholiumL10n.string("Extract to New Note…")
        case .move: ScholiumL10n.string("Move Passage to Note…")
        case .copy: ScholiumL10n.string("Copy Passage to Note…")
        }
    }

}

/// A native menu item retains one revision/selection-checked invocation.
@MainActor
final class PassageMenuItem: NSMenuItem {
    private let invoke: () -> Void

    init(title: String, enabled: Bool, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { invoke() }
}
