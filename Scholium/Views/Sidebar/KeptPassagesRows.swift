import ScholiumContracts
import SwiftUI

/// Both discovery panes borrow the same window-local snapshots. These are
/// ordinary rows in their existing List, never a second scroll or source owner.
struct KeptPassagesRows: View {
    @ObservedObject var session: KeptPassagesSession
    let open: (KeptPassage) -> Void

    var body: some View {
        if !session.entries.isEmpty {
            Button {
                session.isExpanded.toggle()
            } label: {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("Kept Passages")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    Text(session.entries.count.formatted())
                        .font(ScholiumTypography.interface(.small))
                    Image(systemName: session.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(session.isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("scholium.kept.toggle")
            .help(
                Text(
                    verbatim:
                        ScholiumL10n.string("Captured text stays unchanged. Open Source checks its saved revision before locating the passage.")
                        + " " + ScholiumL10n.string("Kept passages stay in this window until removed or the Triptych closes."))
            )
            .id("scholium.kept.heading")
            .researchListRow()
            if session.isExpanded {
                ForEach(session.entries) { entry in
                    KeptPassageRow(
                        entry: entry,
                        directoryContext: session.directoryContext(for: entry),
                        open: { open(entry) }, remove: { session.remove(entry.id) },
                        contextExpanded: Binding(
                            get: { session.isContextExpanded(entry.id) },
                            set: { session.setContextExpanded($0, for: entry.id) }
                        )
                    )
                    .researchListRow()
                }
            }
            Divider().accessibilityHidden(true).researchListRow()
        }
        if let error = session.errorMessage {
            ScholiumApparatusStateView(
                "Kept Passage", detail: error, systemImage: "exclamationmark.triangle", density: .block
            ) {
                Button(action: session.dismissError) {
                    Text("Dismiss").researchInspectorActionLabel()
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("scholium.kept.error")
            .researchListRow()
        }
    }
}

private struct KeptPassageRow: View {
    let entry: KeptPassage
    let directoryContext: String?
    let open: () -> Void
    let remove: () -> Void
    @Binding var contextExpanded: Bool

    private var identity: String {
        [entry.title, ScholiumL10n.dynamicString(entry.reference.vaultRole.displayName), entry.reference.vaultName, entry.reference.relativePath]
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: ScholiumGrid.Apparatus.iconToTextGap) {
                ResearchNoteRoleIcon(role: entry.reference.vaultRole)
                    .font(ScholiumTypography.interface(.small))
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ResearchText(text: Text(verbatim: entry.title))
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .lineLimit(1)
                    if let directoryContext {
                        ResearchText(text: Text(verbatim: directoryContext))
                            .font(ScholiumTypography.interface(.small))
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: identity))
                .help(identity)
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .researchInspectorActionLabel(iconOnly: true)
                }
                .buttonStyle(.plain)
                .help("Remove Kept Passage")
                .accessibilityLabel(Text(verbatim: ScholiumL10n.string("Remove Kept Passage") + ", " + identity))
                .accessibilityIdentifier("scholium.kept.remove.\(entry.id)")
            }
            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
            Button(action: open) {
                ResearchPassageLayout {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        if contextExpanded {
                            ResearchPassageExcerpt(text: Text(verbatim: entry.displayText), isExpanded: true)
                        } else {
                            ResearchPassagePreview(source: entry.excerpt, matches: entry.excerptFocus) {
                                ResearchPassageHighlight.matches(in: $0.text, ranges: entry.excerptMatches.isEmpty ? [] : $0.matches)
                            }
                        }
                        if !contextExpanded, let annotation = entry.linkOccurrence?.annotation {
                            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                Image(systemName: "text.bubble").accessibilityHidden(true)
                                ResearchPassageExcerpt(
                                    text: Text(verbatim: annotation.text), lineLimit: 2
                                )
                            }
                            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                        }
                    }
                    .foregroundStyle(ScholiumNativeColorRole.label.color)
                }
            }
            .buttonStyle(.plain)
            .scholiumActivationPointer()
            .help("Captured text stays unchanged. Open Source checks its saved revision before locating the passage.")
            .accessibilityLabel(Text(verbatim: identity + ", " + ScholiumL10n.string("Kept snapshot") + ", " + entry.displayText))
            .accessibilityHint("Open Source")
            .accessibilityIdentifier("scholium.kept.open.\(entry.id)")
            ResearchPassageContextDisclosure(expanded: $contextExpanded, identity: identity, identifier: "kept.\(entry.id)")
                .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
        }
        .contextMenu {
            Button("Open Source", action: open)
            Button("Remove Kept Passage", action: remove)
        }
        .accessibilityActions {
            Button("Open Source", action: open)
            Button("Remove Kept Passage", action: remove)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: remove) { Label("Remove Kept Passage", systemImage: "pin.slash") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.kept.row.\(entry.id)")
    }
}

/// Kept source remains reachable after closing the last document tab.
struct KeptPassagesWithoutDocumentView: View {
    @ObservedObject var session: KeptPassagesSession
    let open: (KeptPassage) -> Void

    var body: some View {
        if session.entries.isEmpty && session.errorMessage == nil {
            ScholiumContentStateView("No Document Selected", indicator: .symbol("doc.text"))
                .accessibilityIdentifier("scholium.noDocumentInspectorState")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                KeptPassagesRows(session: session, open: open)
                ScholiumApparatusStateView("No Document Selected", systemImage: "doc.text")
                    .accessibilityIdentifier("scholium.noDocumentInspectorState")
                    .researchListRow()
            }
            .researchListStyle()
        }
    }
}
