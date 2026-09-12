import ScholiumContracts
import SwiftUI

struct RelatedMaterialNoteGroupView: View {
    let group: RelatedMaterialsSession.NoteGroup
    let canInsert: Bool
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
                Button {
                    insert(first)
                } label: {
                    Label("Link to This Note", systemImage: "link")
                }
                .disabled(!canInsert || first.linkTarget == nil)
            }
            if expanded {
                ForEach(group.passages) { card in
                    RelatedMaterialPassageView(
                        card: card,
                        entranceProgress: entranceProgress,
                        open: { open(card) }, addToChat: { addToChat(card) })
                }
            }
        }
    }
}

private struct RelatedMaterialPassageView: View {
    let card: RelatedMaterialCard
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
            }
            .researchGroupEntrance(entranceProgress)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(card.passage.excerpt))
        .help("Show this passage")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: addToChat) { Label("Add to Chat", systemImage: "plus.bubble") }
                .disabled(card.attachment == nil)
        }
        .contextMenu {
            Button("Add to Chat", action: addToChat).disabled(card.attachment == nil)
            Button("Open Linked Note", action: open)
        }
        .accessibilityAction(named: Text("Add to Chat")) {
            if card.attachment != nil { addToChat() }
        }
        .accessibilityIdentifier("scholium.related.card.\(card.id)")
    }
}

/// First-load preview of the same information regions used by a result card.
struct RelatedMaterialSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, phase in
            content.opacity(phase ? 0.45 : 0.9)
        } animation: { _ in
            .easeInOut(duration: 1.1)
        }
        .accessibilityHidden(true)
    }
}
