import ScholiumContracts
import SwiftUI

struct RelatedMaterialNoteGroupView: View {
    let group: RelatedMaterialsSession.NoteGroup
    let canInsert: Bool
    let isLoading: Bool
    let entranceProgress: CGFloat
    let open: (RelatedMaterialCard) -> Void
    let insert: (RelatedMaterialCard) -> Void
    let addToChat: (RelatedMaterialCard) -> Void
    @State private var expanded = true

    var body: some View {
        if let first = group.passages.first {
            ResearchNoteGroupHeader(
                title: first.candidate.title, role: first.reference.vaultRole,
                expanded: $expanded,
                entranceProgress: entranceProgress
            ) {
                Button("Link to This Note") { insert(first) }
                    .disabled(!canInsert || first.linkTarget == nil)
                Button("Open Linked Note") { open(first) }
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
                        isLoading: isLoading,
                        entranceProgress: entranceProgress,
                        open: { open(card) }, addToChat: { addToChat(card) }
                    )
                    .accessibilityHidden(isLoading)
                }
            }
        }
    }
}

private struct RelatedMaterialPassageView: View {
    let card: RelatedMaterialCard
    let isLoading: Bool
    let entranceProgress: CGFloat
    let open: () -> Void
    let addToChat: () -> Void

    var body: some View {
        Button(action: open) {
            ResearchPassageCard {
                ResearchPassageHighlight.matches(
                    in: card.passage.excerpt, ranges: card.passage.excerptMatches
                )
                .textRenderer(ResearchHighlightRenderer())
                .font(ScholiumTypography.interface(.control)).lineLimit(3)
                .foregroundStyle(ScholiumNativeColorRole.label.color)
                .scholiumContentControlInk(
                    resting: .primaryText,
                    emphasized: .accent
                )
            }
            .researchGroupEntrance(entranceProgress)
        }
        .buttonStyle(.borderless)
        .scholiumActivationPointer()
        .scholiumContentControlPointerFeedback(
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialPanelCornerRadius,
                style: .continuous
            )
        )
        .accessibilityLabel(Text(card.passage.excerpt))
        .help("Show this passage")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isLoading {
                Button(action: addToChat) { Label("Add to Chat", systemImage: "plus.bubble") }
                    .disabled(card.attachment == nil)
            }
        }
        .contextMenu {
            if !isLoading {
                Button("Add to Chat", action: addToChat).disabled(card.attachment == nil)
                Button("Open Linked Note", action: open)
            }
        }
        .accessibilityActions {
            if !isLoading && card.attachment != nil {
                Button("Add to Chat", action: addToChat)
            }
        }
        .accessibilityIdentifier("scholium.related.card.\(card.id)")
    }
}

/// Initial-search preview of the same information regions used by a result card.
struct RelatedMaterialSkeleton: View {
    var body: some View {
        Group {
            HStack(spacing: ScholiumGrid.Apparatus.iconToTextGap) {
                Image(systemName: "doc.text").frame(width: ScholiumGrid.Apparatus.iconColumnWidth)
                Text("Writing References").redacted(reason: .placeholder)
                Spacer()
            }
            .font(ScholiumTypography.interface(.control, emphasis: .strong))
            .frame(minHeight: ScholiumSidebarLayout.controlHeight)
            ResearchPassageCard {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ForEach(0..<3) { _ in
                        Text("Writing References").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(ScholiumTypography.interface(.control))
                .redacted(reason: .placeholder)
            }
        }
        .foregroundStyle(.quaternary)
        .modifier(ResearchSkeletonPulse(isActive: true))
        .accessibilityHidden(true)
    }
}
