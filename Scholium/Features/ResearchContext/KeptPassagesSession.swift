import Combine
import Foundation
import ScholiumContracts

/// A deliberately retained, immutable source revision; never a claim about current source.
struct KeptPassage: Identifiable, Equatable, Sendable {
    let title: String
    let reference: VaultNoteReference
    let fingerprint: DocumentFingerprint
    let range: SearchSourceRange
    /// The original action locator, distinct from a Links occurrence's surrounding context.
    let sourceRange: SearchSourceRange
    let text: String
    let displayText: String
    let excerpt: String
    let excerptMatches: [Range<Int>]
    let linkOccurrence: LinkOccurrence?

    var id: String { Self.identity(reference: reference, fingerprint: fingerprint, locator: sourceRange) }
    var excerptFocus: [Range<Int>] {
        linkOccurrence.map { ResearchLinkPassage(occurrence: $0).authoredFocus } ?? excerptMatches
    }

    init(card: RelatedMaterialCard) {
        title = card.candidate.title
        reference = card.reference
        fingerprint = card.candidate.fingerprint
        range = card.passage.range
        sourceRange = card.passage.range
        text = card.passage.source
        displayText = card.passage.displayText
        excerpt = card.passage.excerpt
        excerptMatches = card.passage.excerptMatches
        linkOccurrence = nil
    }

    init(item: InspectorLinkItem, document: NoteDocument) throws {
        let occurrence = item.edge.occurrence
        guard let source = item.source,
            source.reference.vaultID == item.edge.source.vaultID,
            source.reference.relativePath == item.edge.source.relativePath,
            document.relativePath == item.edge.source.relativePath,
            document.fingerprint == source.fingerprint,
            MarkdownSemanticDocument(parsing: document).links.contains(where: { parsed in
                var comparable = parsed
                comparable.resolution = occurrence.resolution
                return comparable == occurrence && parsed.localContext.utf8.elementsEqual(occurrence.localContext.utf8)
            }), occurrence.span.utf16LowerBound >= 0,
            occurrence.span.utf16UpperBound > occurrence.span.utf16LowerBound,
            occurrence.span.utf16UpperBound <= document.rawContent.utf16.count
        else { throw KeptPassageError.changedCapture }
        let sourceText = document.rawContent
        let native = sourceText as NSString
        let lineRange = native.lineRange(for: occurrence.span.nsRange)
        guard var context = Range(lineRange, in: sourceText) else { throw KeptPassageError.changedCapture }
        while context.lowerBound < context.upperBound, sourceText[context.lowerBound].isNewline {
            context = sourceText.index(after: context.lowerBound)..<context.upperBound
        }
        while context.lowerBound < context.upperBound, sourceText[sourceText.index(before: context.upperBound)].isNewline {
            context = context.lowerBound..<sourceText.index(before: context.upperBound)
        }
        guard let captured = DocumentPassageSnapshot.capture(source: sourceText, range: NSRange(context, in: sourceText)),
            captured.excerpt.utf8.elementsEqual(occurrence.localContext.utf8),
            let anchor = DocumentPassageSnapshot.capture(source: sourceText, range: occurrence.linkSpan.nsRange)
        else { throw KeptPassageError.changedCapture }
        let readable = ResearchLinkPassage(occurrence: occurrence)
        title = source.title
        reference = source.reference
        fingerprint = document.fingerprint
        range = captured.sourceRange
        sourceRange = anchor.sourceRange
        text = captured.excerpt
        displayText = ResearchExcerptPresentation.readableText(captured.excerpt, includingAnnotations: true)
        excerpt = readable.text
        excerptMatches = readable.highlights
        linkOccurrence = occurrence
    }

    static func identity(for item: InspectorLinkItem) -> String? {
        guard let source = item.source else { return nil }
        let span = item.edge.occurrence.linkSpan
        return identity(reference: source.reference, fingerprint: source.fingerprint, lower: span.utf16LowerBound, upper: span.utf16UpperBound)
    }

    private static func identity(reference: VaultNoteReference, fingerprint: DocumentFingerprint, locator: SearchSourceRange) -> String {
        identity(reference: reference, fingerprint: fingerprint, lower: locator.utf16LowerBound, upper: locator.utf16UpperBound)
    }

    private static func identity(reference: VaultNoteReference, fingerprint: DocumentFingerprint, lower: Int, upper: Int) -> String {
        let note = reference.stableNoteID.flatMap(UUID.init(uuidString:)).map { "id:" + $0.uuidString } ?? "path:" + reference.relativePath
        return "\(reference.vaultID):\(note):\(fingerprint.sha256):\(lower):\(upper)"
    }
}

enum KeptPassageError: LocalizedError {
    case changedCapture, changedSource, missingSource, unverifiedSource, unavailable

    var errorDescription: String? {
        switch self {
        case .changedCapture: String(localized: "The source has changed. Refresh the results before keeping this passage.", bundle: .module)
        case .changedSource: String(localized: "The source has changed. The kept snapshot remains unchanged.", bundle: .module)
        case .missingSource: String(localized: "The source could not be opened. The kept snapshot remains available.", bundle: .module)
        case .unverifiedSource: String(localized: "The source location could not be verified. The kept snapshot remains unchanged.", bundle: .module)
        case .unavailable: String(localized: "This source is not available in the current Triptych.", bundle: .module)
        }
    }
}

/// Per-window memory only. Discovery refreshes and Document selection never own this collection.
@MainActor final class KeptPassagesSession: ObservableObject {
    @Published private(set) var entries: [KeptPassage] = []
    @Published private(set) var errorMessage: String?
    @Published var isExpanded = true
    @Published private var expandedContextIDs: Set<String> = []
    private(set) var generation = UUID()
    private var pending: [String: UUID] = [:]
    private var lifetimes: [String: UUID] = [:]

    struct Capture: Equatable {
        let id: String
        let generation: UUID
        let ticket: UUID
    }

    func entry(for card: RelatedMaterialCard) -> KeptPassage? { entries.first { $0.id == KeptPassage(card: card).id } }
    func entry(for item: InspectorLinkItem) -> KeptPassage? { entries.first { $0.id == KeptPassage.identity(for: item) } }
    func contains(_ card: RelatedMaterialCard) -> Bool { entry(for: card) != nil }
    func contains(_ item: InspectorLinkItem) -> Bool { entry(for: item) != nil }

    func retain(_ entry: KeptPassage) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        lifetimes[entry.id] = UUID()
        entries.append(entry)
        isExpanded = true
        errorMessage = nil
    }

    func isContextExpanded(_ id: String) -> Bool { expandedContextIDs.contains(id) }

    func setContextExpanded(_ expanded: Bool, for id: String) {
        guard lifetimes[id] != nil else { return }
        if expanded { expandedContextIDs.insert(id) } else { expandedContextIDs.remove(id) }
    }

    func directoryContext(for entry: KeptPassage) -> String? {
        guard entries.contains(where: {
            $0.title == entry.title
                && ($0.reference.vaultID != entry.reference.vaultID || $0.reference.relativePath != entry.reference.relativePath)
        }) else { return nil }
        let directory = (entry.reference.relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty ? entry.reference.vaultName : entry.reference.vaultName + " / " + directory
    }

    func entryLifetime(for entry: KeptPassage) -> UUID? {
        entries.contains(entry) ? lifetimes[entry.id] : nil
    }

    func remove(_ id: String) {
        pending[id] = nil
        lifetimes[id] = nil
        expandedContextIDs.remove(id)
        entries.removeAll { $0.id == id }
    }

    func beginCapture(id: String) -> Capture? {
        guard pending[id] == nil, !entries.contains(where: { $0.id == id }) else { return nil }
        let ticket = UUID()
        pending[id] = ticket
        return Capture(id: id, generation: generation, ticket: ticket)
    }

    func isCurrent(_ capture: Capture) -> Bool {
        capture.generation == generation && pending[capture.id] == capture.ticket
    }

    func finish(_ capture: Capture, entry: KeptPassage? = nil, error: Error? = nil) {
        guard isCurrent(capture) else { return }
        pending[capture.id] = nil
        if let entry, entry.id == capture.id { retain(entry) }
        if let error { report(error) }
    }

    func report(_ error: Error) { errorMessage = error.localizedDescription }
    func dismissError() { errorMessage = nil }

    func reset() {
        generation = UUID()
        pending = [:]
        lifetimes = [:]
        entries = []
        isExpanded = true
        expandedContextIDs = []
        errorMessage = nil
    }
}
