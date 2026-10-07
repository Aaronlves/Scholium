import ScholiumContracts
import SwiftUI

struct RelatedMaterialNoteGroupView: View {
    let group: RelatedMaterialsSession.NoteGroup
    @ObservedObject var keptPassages: KeptPassagesSession
    var termGroup: SearchTermGroup? = nil
    let canInsert: Bool
    let canInsertParagraph: Bool
    let canAddToChat: Bool
    let isLoading: Bool
    let entranceProgress: CGFloat
    var separatesFromPreviousGroup = false
    let open: (RelatedMaterialCard) -> Void
    let insert: (RelatedMaterialCard) -> Void
    let insertParagraph: (RelatedMaterialCard) -> Void
    let addToChat: (RelatedMaterialCard) -> Void
    let keepRelated: (RelatedMaterialCard) -> Void
    @State private var expanded = true

    var body: some View {
        if let first = group.passages.first {
            ResearchNoteGroupHeader(
                title: first.candidate.title, role: first.reference.vaultRole,
                expanded: $expanded,
                entranceProgress: entranceProgress,
                directoryContext: group.directoryContext,
                relativePath: first.reference.relativePath,
                separatesFromPreviousGroup: separatesFromPreviousGroup
            ) {
                Button("Link to This Note") { insert(first) }
                    .disabled(!canInsert || first.linkTarget == nil)
                    .accessibilityLabel(Text(verbatim: ScholiumL10n.string("\(ScholiumL10n.string("Link to This Note")), \(first.sourceIdentity)")))
                Menu("Insert Paragraph Link") {
                    ForEach(Array(group.passages.enumerated()), id: \.element.id) { index, card in
                        Button {
                            insertParagraph(card)
                        } label: {
                            Text(
                                verbatim: "\(index + 1). " + String(card.passage.excerpt.prefix(8))
                                    + (card.passage.excerpt.count > 8 ? "…" : ""))
                        }.disabled(!canInsertParagraph || card.linkTarget == nil)
                    }
                }
                .disabled(!canInsertParagraph)
                .accessibilityLabel(Text(verbatim: ScholiumL10n.string("\(ScholiumL10n.string("Insert Paragraph Link")), \(first.sourceIdentity)")))
                .help("Creates a paragraph anchor in the source note when needed, then inserts a link at the writing cursor.")
                Button("Open Source") { open(first) }
                    .accessibilityLabel(Text(verbatim: ScholiumL10n.string("\(ScholiumL10n.string("Open Source")), \(first.sourceIdentity)")))
                if canAddToChat {
                    Menu("Add to Chat") {
                        ForEach(Array(group.passages.enumerated()), id: \.element.id) { index, card in
                            Button {
                                addToChat(card)
                            } label: {
                                Text(
                                    verbatim: "\(index + 1). " + String(card.passage.excerpt.prefix(8))
                                        + (card.passage.excerpt.count > 8 ? "…" : ""))
                            }.disabled(card.attachment == nil)
                        }
                    }
                    .accessibilityLabel(Text(verbatim: ScholiumL10n.string("\(ScholiumL10n.string("Add to Chat")), \(first.sourceIdentity)")))
                }
                if !isLoading {
                    keptPassageMenus
                }
            }
            .accessibilityActions {
                if !isLoading {
                    if canInsert && first.linkTarget != nil {
                        Button("Link to This Note") { insert(first) }
                    }
                    Button("Open Source") { open(first) }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !isLoading {
                    Button {
                        insert(first)
                    } label: {
                        Label("Link to This Note", systemImage: "link")
                    }
                    .disabled(!canInsert || first.linkTarget == nil)
                }
            }
            .accessibilityHidden(isLoading)
            if expanded {
                ForEach(group.passages) { card in
                    RelatedMaterialPassageView(
                        card: card,
                        termGroup: termGroup,
                        isLoading: isLoading,
                        entranceProgress: entranceProgress,
                        canInsertParagraph: canInsertParagraph && card.linkTarget != nil,
                        canAddToChat: canAddToChat,
                        isKept: keptPassages.contains(card),
                        insertParagraph: { insertParagraph(card) },
                        open: { open(card) }, addToChat: { addToChat(card) },
                        toggleKept: { toggleKept(card) }
                    )
                    .accessibilityHidden(isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private var keptPassageMenus: some View {
        if group.passages.contains(where: { !keptPassages.contains($0) }) {
            Menu("Keep Passage") {
                ForEach(Array(group.passages.enumerated()), id: \.element.id) { index, card in
                    if !keptPassages.contains(card) {
                        Button {
                            toggleKept(card)
                        } label: {
                            passageChoice(index: index, card: card)
                        }
                    }
                }
            }
        }
        if group.passages.contains(where: { keptPassages.contains($0) }) {
            Menu("Remove Kept Passage") {
                ForEach(Array(group.passages.enumerated()), id: \.element.id) { index, card in
                    if keptPassages.contains(card) {
                        Button {
                            toggleKept(card)
                        } label: {
                            passageChoice(index: index, card: card)
                        }
                    }
                }
            }
        }
    }

    private func passageChoice(index: Int, card: RelatedMaterialCard) -> Text {
        Text(
            verbatim: "\(index + 1). " + String(card.passage.excerpt.prefix(8))
                + (card.passage.excerpt.count > 8 ? "…" : ""))
    }

    private func toggleKept(_ card: RelatedMaterialCard) {
        guard !isLoading else { return }
        if let entry = keptPassages.entry(for: card) {
            keptPassages.remove(entry.id)
        } else {
            keepRelated(card)
        }
    }
}

private struct RelatedMaterialPassageView: View {
    @Environment(\.locale) private var locale
    let card: RelatedMaterialCard
    let termGroup: SearchTermGroup?
    let isLoading: Bool
    let entranceProgress: CGFloat
    let canInsertParagraph: Bool
    let canAddToChat: Bool
    let isKept: Bool
    let insertParagraph: () -> Void
    let open: () -> Void
    let addToChat: () -> Void
    let toggleKept: () -> Void
    @State private var contextExpanded = false
    private var keptActionTitle: LocalizedStringKey { isKept ? "Remove Kept Passage" : "Keep Passage" }

    var body: some View {
        let preview = ResearchCompactExcerpt(text: card.passage.excerpt, matches: card.passage.excerptMatches)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                ResearchPassageLayout {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Group {
                            if contextExpanded {
                                ResearchPassageExcerpt(text: Text(verbatim: card.passage.displayText), isExpanded: true)
                            } else {
                                ResearchPassagePreview(source: card.passage.excerpt, matches: card.passage.excerptMatches) {
                                    ResearchPassageHighlight.matches(in: $0.text, ranges: $0.matches)
                                }
                            }
                        }.foregroundStyle(ScholiumNativeColorRole.label.color)
                        if termGroup != nil, !card.matchedTermGroupAlternatives.isEmpty {
                            Text("Matched alternative: \(card.matchedTermGroupAlternatives.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                        }
                    }
                }
                .researchGroupEntrance(entranceProgress)
            }
            .buttonStyle(.plain)
            .scholiumActivationPointer()
            .accessibilityLabel(
                Text(
                    verbatim:
                        "\(card.sourceIdentity), \(contextExpanded ? card.passage.displayText : preview.text)"
                        + (termGroup != nil && !card.matchedTermGroupAlternatives.isEmpty
                            ? ", " + ScholiumL10n.string("Matched alternative: \(card.matchedTermGroupAlternatives.joined(separator: ", "))", locale: locale)
                            : ""))
            )
            .accessibilityHint(Text(verbatim: RelatedMaterialGraphExplanation.passageHint(for: card.candidate, locale: locale)))
            .help(Text(verbatim: RelatedMaterialGraphExplanation.passageHint(for: card.candidate, locale: locale)))
            .contextMenu {
                if !isLoading {
                    Button("Insert Paragraph Link", action: insertParagraph).disabled(!canInsertParagraph)
                    if canAddToChat {
                        Button("Add to Chat", action: addToChat).disabled(card.attachment == nil)
                    }
                    Button("Open Source", action: open)
                    Button(keptActionTitle, action: toggleKept)
                }
            }
            .accessibilityActions {
                if !isLoading && canInsertParagraph {
                    Button("Insert Paragraph Link", action: insertParagraph)
                }
                if !isLoading && canAddToChat && card.attachment != nil {
                    Button("Add to Chat", action: addToChat)
                }
                if !isLoading {
                    Button(keptActionTitle, action: toggleKept)
                }
            }
            .accessibilityIdentifier("scholium.related.card.\(card.id)")
            ResearchPassageContextDisclosure(
                expanded: $contextExpanded, identity: card.sourceIdentity, identifier: card.id
            )
            .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
            .researchGroupEntrance(entranceProgress)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isLoading {
                Button(action: toggleKept) {
                    Label(keptActionTitle, systemImage: isKept ? "pin.slash" : "pin")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isLoading && canAddToChat {
                Button(action: addToChat) { Label("Add to Chat", systemImage: "plus.bubble") }
                    .disabled(card.attachment == nil)
            }
        }
    }
}

/// Initial-search preview of the same information regions used by a result card.
struct RelatedMaterialSkeleton: View {
    var separatesFromPreviousGroup = false

    var body: some View {
        Group {
            ResearchNoteGroupHeader(
                title: ScholiumL10n.dynamicString("Writing References"), role: nil,
                expanded: .constant(true),
                separatesFromPreviousGroup: separatesFromPreviousGroup
            ) {}
            VStack(alignment: .leading, spacing: 0) {
                ResearchPassageLayout {
                    // Redacted text uses the same natural wrapping as a result,
                    // rather than three short fixed-width bars unrelated to the pane.
                    ResearchPassageExcerpt(
                        text: Text(
                            verbatim: Array(repeating: ScholiumL10n.dynamicString("Writing References"), count: 10)
                                .joined(separator: " ")))
                }
                ResearchPassageContextDisclosure(expanded: .constant(false), identity: "", identifier: "placeholder")
                    .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
            }
        }
        .redacted(reason: .placeholder)
        .modifier(ResearchSkeletonPulse(isActive: true))
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
