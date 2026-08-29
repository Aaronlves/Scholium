import ScholiumContracts
import SwiftUI

/// Read-only navigation state derived from the current Workspace snapshot.
/// Record-authored links use the same fail-closed resolver as Note links but
/// never enter the Link Graph or acquire philosophical relationship meaning.
struct ResearchRecordProseNavigation: Sendable {
    static let empty = Self(catalog: [], stableNoteIDs: [:])

    private static let scheme = "scholium-record-note"
    private let catalog: LinkResolutionCatalog
    private let stableNoteIDs: [VaultQualifiedNoteID: UUID]
    private let notesByStableID: [UUID: VaultQualifiedNoteID]

    init(snapshot: WorkspaceSnapshot) {
        let notes = snapshot.vaults.flatMap(\.documents)
        var stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:]
        for note in notes {
            if let stableNoteID = note.stableIdentity.resolvedID {
                stableNoteIDs[note.id] = stableNoteID
            }
        }
        self.init(
            catalog: notes.map { note in
                LinkCatalogNote(
                    vaultID: note.id.vaultID,
                    document: note.document,
                    profile: note.schemaProfile,
                    metadata: note.metadata,
                    semantic: note.cachedSemanticDocument
                )
            },
            stableNoteIDs: stableNoteIDs
        )
    }

    init(
        catalog: [LinkCatalogNote],
        stableNoteIDs: [VaultQualifiedNoteID: UUID]
    ) {
        self.catalog = LinkResolutionCatalog(catalog: catalog)
        let grouped = Dictionary(
            grouping: stableNoteIDs.map { ($0.key, $0.value) },
            by: { $0.1 }
        )
        let unique = grouped.compactMapValues { entries in
            entries.count == 1 ? entries[0].0 : nil
        }
        notesByStableID = unique
        self.stableNoteIDs = Dictionary(
            uniqueKeysWithValues: unique.map { ($0.value, $0.key) }
        )
    }

    func destination(
        target: String,
        fragment: String?,
        from source: VaultQualifiedNoteID
    ) -> ResearchRecordProseDestination? {
        guard case .resolved(let resolved) = catalog.resolveNavigation(
            target: target,
            fragment: fragment,
            from: source,
            scope: .workspace
        ), let stableNoteID = stableNoteIDs[resolved.note] else {
            return nil
        }
        return ResearchRecordProseDestination(
            stableNoteID: stableNoteID,
            note: resolved.note,
            sourceLine: resolved.span?.start.line
        )
    }

    func currentLocation(
        for participant: PortableResearchNoteRevision?
    ) -> VaultQualifiedNoteID? {
        guard let participant else { return nil }
        return notesByStableID[participant.noteID]
    }

    func url(for destination: ResearchRecordProseDestination) -> URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = destination.stableNoteID.uuidString.lowercased()
        if let line = destination.sourceLine {
            components.queryItems = [URLQueryItem(name: "line", value: String(line))]
        }
        return components.url
    }

    func destination(for url: URL) -> ResearchRecordProseDestination? {
        guard url.scheme == Self.scheme,
            let host = url.host,
            let stableNoteID = UUID(uuidString: host),
            let note = notesByStableID[stableNoteID]
        else { return nil }
        let line = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "line" }?
            .value
            .flatMap(Int.init)
        return ResearchRecordProseDestination(
            stableNoteID: stableNoteID,
            note: note,
            sourceLine: line
        )
    }
}

struct ResearchRecordProseDestination: Hashable, Sendable {
    let stableNoteID: UUID
    let note: VaultQualifiedNoteID
    let sourceLine: Int?
}

struct ResearchRecordProsePresentationBlock: Identifiable {
    let id: Int
    let kind: ResearchRecordProseBlockKind
    let quoteDepth: Int
    let text: AttributedString
}

struct ResearchRecordProsePresentation {
    let blocks: [ResearchRecordProsePresentationBlock]

    init(
        source: String,
        sourceNote: VaultQualifiedNoteID?,
        navigation: ResearchRecordProseNavigation
    ) {
        blocks = ResearchRecordProseProjection(source: source).blocks.enumerated().map {
            offset, block in
            ResearchRecordProsePresentationBlock(
                id: offset,
                kind: block.kind,
                quoteDepth: block.quoteDepth,
                text: Self.attributedText(
                    block.inlines,
                    sourceNote: sourceNote,
                    navigation: navigation
                )
            )
        }
    }

    private static func attributedText(
        _ inlines: [ResearchRecordProseInline],
        sourceNote: VaultQualifiedNoteID?,
        navigation: ResearchRecordProseNavigation
    ) -> AttributedString {
        var result = AttributedString()
        var index = inlines.startIndex
        while index < inlines.endIndex {
            let inline = inlines[index]
            guard case let .internalReference(
                target,
                fragment,
                fallbackText,
                syntax
            )? = inline.link else {
                result.append(styled(inline, linkURL: externalURL(inline.link)))
                index = inlines.index(after: index)
                continue
            }

            let nextDifferentLink = inlines[index...].firstIndex { $0.link != inline.link }
                ?? inlines.endIndex
            let destination = sourceNote.flatMap {
                navigation.destination(target: target, fragment: fragment, from: $0)
            }
            if let destination, let url = navigation.url(for: destination) {
                for linkedInline in inlines[index..<nextDifferentLink] {
                    result.append(styled(linkedInline, linkURL: url, syntax: syntax))
                }
            } else {
                result.append(literal(fallbackText))
            }
            index = nextDifferentLink
        }
        return result
    }

    private static func externalURL(_ link: ResearchRecordProseLink?) -> URL? {
        guard case .external(let url) = link else { return nil }
        return url
    }

    private static func styled(
        _ inline: ResearchRecordProseInline,
        linkURL: URL?,
        syntax: ResearchRecordProseInternalLinkSyntax? = nil
    ) -> AttributedString {
        var value = AttributedString(inline.text)
        if inline.traits.contains(.code) {
            value.font = ScholiumTypography.exactInline(
                bold: inline.traits.contains(.strong),
                italic: inline.traits.contains(.emphasis)
            )
        } else {
            value.font = ScholiumTypography.scholarlyInline(
                bold: inline.traits.contains(.strong),
                italic: inline.traits.contains(.emphasis)
            )
        }
        value.foregroundColor = ScholiumColorRole.primaryText.color
        if let linkURL {
            value.link = linkURL
            value.foregroundColor = ScholiumColorRole.accent.color
            value.underlineStyle = Text.LineStyle(pattern: .solid)
            if syntax == .wikilink {
                value.backgroundColor = ScholiumColorRole.raisedSurfaceBackground.color
            }
        }
        return value
    }

    private static func literal(_ source: String) -> AttributedString {
        var value = AttributedString(source)
        value.font = ScholiumTypography.exactInline()
        value.foregroundColor = ScholiumColorRole.secondaryText.color
        return value
    }
}

struct ResearchRecordProseView: View {
    let source: String
    let sourceNote: VaultQualifiedNoteID?
    let navigation: ResearchRecordProseNavigation
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void

    private var presentation: ResearchRecordProsePresentation {
        ResearchRecordProsePresentation(
            source: source,
            sourceNote: sourceNote,
            navigation: navigation
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ForEach(presentation.blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let destination = navigation.destination(for: url) else {
                return .systemAction(url)
            }
            openNote(
                destination.stableNoteID,
                destination.note,
                destination.sourceLine
            )
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: ResearchRecordProsePresentationBlock) -> some View {
        switch block.kind {
        case .paragraph, .literal:
            proseText(block.text, isHeading: false)
                .padding(.leading, quoteIndent(block.quoteDepth))
                .overlay(alignment: .leading) {
                    quoteRule(depth: block.quoteDepth)
                }
        case .heading:
            proseText(block.text, isHeading: true)
                .padding(.leading, quoteIndent(block.quoteDepth))
                .overlay(alignment: .leading) {
                    quoteRule(depth: block.quoteDepth)
                }
        case .unorderedListItem(let depth):
            listRow(marker: "•", block: block, depth: depth)
        case .orderedListItem(let index, let depth):
            listRow(marker: "\(index).", block: block, depth: depth)
        case .listContinuation(let depth):
            listRow(marker: "", block: block, depth: depth)
        }
    }

    private func proseText(
        _ text: AttributedString,
        isHeading: Bool
    ) -> some View {
        Text(text)
            .lineSpacing(ScholiumGrid.Spacing.labelAccessoryGap)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHeading(isHeading ? .h3 : .unspecified)
    }

    private func listRow(
        marker: String,
        block: ResearchRecordProsePresentationBlock,
        depth: Int
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(marker)
                .font(ScholiumTypography.scholarly(.body))
                .scholiumForeground(.secondaryText)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
            proseText(block.text, isHeading: false)
        }
        .padding(
            .leading,
            CGFloat(depth) * ScholiumGrid.Spacing.nestedContentInset
                + quoteIndent(block.quoteDepth)
        )
        .overlay(alignment: .leading) {
            quoteRule(depth: block.quoteDepth)
        }
    }

    private func quoteIndent(_ depth: Int) -> CGFloat {
        CGFloat(depth) * ScholiumGrid.Spacing.inlineControlGap
    }

    @ViewBuilder
    private func quoteRule(depth: Int) -> some View {
        if depth > 0 {
            Rectangle()
                .fill(ScholiumColorRole.accent.color)
                .frame(width: 2)
                .accessibilityHidden(true)
        }
    }
}
