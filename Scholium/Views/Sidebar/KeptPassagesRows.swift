import ScholiumContracts
import SwiftUI

/// Both discovery panes borrow the same window-local snapshots. These are
/// ordinary rows in their existing List, never a second scroll or source owner.
struct KeptPassagesRows: View {
    @ObservedObject var session: KeptPassagesSession
    let open: (KeptPassage) -> Void

    var body: some View {
        if !session.entries.isEmpty {
            Text("Kept Passages")
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                .accessibilityAddTraits(.isHeader)
                .help("Kept passages stay in this window until removed or the Triptych closes.")
                .id("scholium.kept.heading")
                .researchListRow()
            ForEach(session.entries) { entry in
                KeptPassageRow(entry: entry, open: { open(entry) }, remove: { session.remove(entry.id) })
                    .researchListRow()
            }
            Divider().accessibilityHidden(true).researchListRow()
        }
        if let error = session.errorMessage {
            ScholiumApparatusStateView(
                "Kept Passage", detail: error, systemImage: "exclamationmark.triangle", density: .block
            ) {
                Button("Dismiss") { session.dismissError() }
                    .buttonStyle(.borderless)
            }
            .accessibilityIdentifier("scholium.kept.error")
            .researchListRow()
        }
    }
}

private struct KeptPassageRow: View {
    let entry: KeptPassage
    let open: () -> Void
    let remove: () -> Void
    @State private var expanded = true
    @State private var contextExpanded = false

    private var identity: String {
        [entry.title, ScholiumL10n.dynamicString(entry.reference.vaultRole.displayName), entry.reference.relativePath]
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResearchNoteGroupHeader(
                title: entry.title, role: entry.reference.vaultRole, expanded: $expanded,
                relativePath: entry.reference.relativePath
            ) {
                Button("Open Source", action: open)
                Button("Remove Kept Passage", action: remove)
                    .accessibilityIdentifier("scholium.kept.remove.\(entry.id)")
            }
            if expanded {
                Text("Kept snapshot")
                    .font(ScholiumTypography.interface(.small))
                    .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                    .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
                    .help("Captured text stays unchanged. Open Source checks its saved revision before locating the passage.")
                    .accessibilityIdentifier("scholium.kept.snapshot.\(entry.id)")
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
                .help("Open Source")
                .accessibilityLabel(Text(verbatim: identity + ", " + entry.displayText))
                .accessibilityHint("Open Source")
                .accessibilityIdentifier("scholium.kept.open.\(entry.id)")
                ResearchPassageContextDisclosure(expanded: $contextExpanded, identity: identity, identifier: "kept.\(entry.id)")
                    .padding(.leading, ScholiumGrid.Apparatus.passageLeadingInset)
            }
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
