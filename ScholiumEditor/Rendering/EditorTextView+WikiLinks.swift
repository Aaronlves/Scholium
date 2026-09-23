// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

// Authored destinations are handed to the application capability owner.
// The renderer never resolves paths, opens documents, or launches applications.
extension EditorTextView {
    func wikiTarget(at event: NSEvent) -> String? {
        guard let storage = textStorage, let i = clickCharIndex(at: event) else { return nil }
        return storage.attribute(.editorWikiTarget, at: i, effectiveRange: nil) as? String
    }
    public func followWikiLink(_ target: String) { onLinkActivation?(target) }
    public func followLinkDestination(_ destination: String) { onLinkActivation?(destination) }

    // MARK: Heading navigation

    /// Scrolls to the first heading block whose text matches `heading`
    /// (case-insensitive), or — when `heading` is a `^blockid` fragment — to the
    /// block defining that id. Beeps if there is no match. This is the single
    /// chokepoint every internal-link caller funnels through (`[[#heading]]`,
    /// `[[note#heading]]`, `[[#^id]]`, `[[note#^id]]`, and cross-file opens via
    /// `navigateToHeading`), so block-id dispatch and the Edit/Read surface
    /// switch both live here.
    public func scrollToHeading(_ heading: String) {
        if heading.hasPrefix("^") {
            scrollToBlockID(String(heading.dropFirst()))
            return
        }
        let want = heading.lowercased()
        for block in blocks {
            guard case .heading = block.kind,
                Self.headingText(block.content).lowercased() == want
            else { continue }
            scrollToBlock(block.range)
            return
        }
        NSSound.beep()
    }

    /// Scrolls to the block that defines the Obsidian `^id` block reference
    /// (a trailing `^id` at the end of a block). Beeps if none does.
    public func scrollToBlockID(_ id: String) {
        for block in blocks {
            var refs: [SyntaxHighlighter.Span] = []
            SyntaxHighlighter.parseBlockRef(block.content, into: &refs)
            let matches = refs.contains {
                if case .blockRef(let bid) = $0.kind { return bid == id }
                return false
            }
            if matches {
                scrollToBlock(block.range)
                return
            }
        }
        NSSound.beep()
    }

    /// Brings `range`'s block into view. In Edit/Source the editor selects the
    /// block (a visible highlight) and scrolls to it. An optional separate reader
    /// may receive a source-line anchor; native reading uses the same text view.
    private func scrollToBlock(_ range: NSRange) {
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    /// The text of a heading line, stripped of its leading `#`s and whitespace.
    static func headingText(_ line: String) -> String {
        var s = Substring(line)
        while s.first == "#" { s = s.dropFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Splits `path#heading` (or `#heading`, or `path`) into a path and the
    /// deepest heading component (so `Note#H1#H2` targets `H2`). A nil heading
    /// means none was named.
    static func splitHeading(_ s: String) -> (path: String, heading: String?) {
        let ns = s as NSString
        let hash = ns.range(of: "#")
        guard hash.location != NSNotFound else {
            return (s.trimmingCharacters(in: .whitespaces), nil)
        }
        let path = ns.substring(to: hash.location).trimmingCharacters(in: .whitespaces)
        let rest = ns.substring(from: hash.upperBound)
        let heading = rest.split(separator: "#").last
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        return (path, heading)
    }

}
