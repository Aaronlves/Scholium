import ScholiumContracts
import SwiftUI

private struct InspectorLinkItem: Identifiable {
    let edge: LinkGraphEdge
    let peer: WorkspaceCatalogNote?
    let source: WorkspaceCatalogNote?
    let direction: ConnectionDirection

    var id: String {
        [
            edge.source.vaultID.uuidString,
            edge.source.relativePath,
            String(edge.occurrence.span.utf16LowerBound),
            String(edge.occurrence.span.utf16UpperBound),
            direction.rawValue,
        ].joined(separator: ":")
    }

    var displayTitle: String {
        peer?.title
            ?? edge.destination.map {
                (($0.note.relativePath as NSString).lastPathComponent as NSString)
                    .deletingPathExtension
            }
            ?? edge.occurrence.target
    }
}

/// Immutable authored-link inputs for one selected document.
struct ConnectionsInspectorContext {
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let current: VaultQualifiedNoteID?
    let freshness: ResearchProjectionFreshness
    let retryRefresh: () -> Void
    let openReference: (VaultNoteReference, Int?) -> Void
}

enum ConnectionDirection: String, CaseIterable, Identifiable {
    case incoming
    case outgoing

    var id: Self { self }

    var title: String {
        switch self {
        case .incoming: "Incoming Links"
        case .outgoing: "Outgoing Links"
        }
    }

    var emptyAnnouncement: LocalizedStringResource {
        switch self {
        case .incoming: "No Incoming Links"
        case .outgoing: "No Outgoing Links"
        }
    }
}

private struct ConnectionsProjection {
    let items: [InspectorLinkItem]

    static func make(
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        current: VaultQualifiedNoteID?,
        direction: ConnectionDirection
    ) -> Self {
        let notesByID = Dictionary(uniqueKeysWithValues: (catalog?.notes ?? []).map {
            (VaultQualifiedNoteID(
                vaultID: $0.reference.vaultID,
                relativePath: $0.reference.relativePath
            ), $0)
        })
        guard let graph, let current else {
            return Self(items: [])
        }

        let edges = switch direction {
        case .incoming: graph.incoming[current] ?? []
        case .outgoing: graph.outgoing[current] ?? []
        }
        let items = edges.map { edge in
            let peerID = direction == .incoming ? edge.source : edge.destination?.note
            let peer = peerID.flatMap { notesByID[$0] }
            return InspectorLinkItem(
                edge: edge,
                peer: peer,
                source: notesByID[edge.source],
                direction: direction
            )
        }.sorted {
            if $0.displayTitle != $1.displayTitle {
                return $0.displayTitle.localizedStandardCompare($1.displayTitle)
                    == .orderedAscending
            }
            if $0.edge.source != $1.edge.source {
                return $0.edge.source < $1.edge.source
            }
            return $0.edge.occurrence.span.utf16LowerBound
                < $1.edge.occurrence.span.utf16LowerBound
        }
        return Self(items: items)
    }
}

struct ConnectionsInspectorView: View {
    let context: ConnectionsInspectorContext
    let direction: ConnectionDirection

    private var projection: ConnectionsProjection {
        ConnectionsProjection.make(
            graph: context.graph,
            catalog: context.catalog,
            current: context.current,
            direction: direction
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing
            ) {
                if context.freshness.isActionable {
                    ResearchProjectionFreshnessView(
                        freshness: context.freshness,
                        retry: context.retryRefresh
                    )
                }

                if projection.items.isEmpty {
                    ScholiumApparatusStateView(
                        direction.emptyAnnouncement,
                        systemImage: "link"
                    )
                    .accessibilityIdentifier("scholium.connections.empty")
                } else {
                    LazyVStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.connectionOccurrenceSpacing
                    ) {
                        ForEach(projection.items) { item in
                            LinkOccurrenceRow(
                                item: item,
                                openReference: context.openReference
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
            .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
            .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel(Text(verbatim: direction.title))
    }
}

private struct LinkOccurrenceRow: View {
    let item: InspectorLinkItem
    let openReference: (VaultNoteReference, Int?) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let peer = item.peer {
                Button {
                    openReference(peer.reference, peerLine)
                } label: {
                    label
                }
                .scholiumActivationPointer()
                .buttonStyle(ScholiumQuietRowButtonStyle(
                    isFocused: isFocused,
                    minimumHeight: ScholiumMetrics.Apparatus.connectionOccurrenceMinimumHeight,
                    verticalInset: ScholiumMetrics.Apparatus.connectionOccurrenceVerticalInset
                ))
                .scholiumActivationFocus($isFocused)
                .contextMenu {
                    if item.edge.occurrence.annotation != nil {
                        Button(sourceActionTitle, action: openSource)
                        .scholiumActivationPointer()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text(sourceActionTitle), openSource)
            } else {
                label
                    .padding(.vertical, ScholiumMetrics.Apparatus.connectionOccurrenceVerticalInset)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(accessibilityHint)
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(item.displayTitle)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumContentControlInk()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                if item.edge.occurrence.annotation != nil {
                    Image(systemName: "text.bubble")
                        .symbolRenderingMode(.monochrome)
                        .scholiumForeground(.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            if let annotation = item.edge.occurrence.annotation {
                Text(annotation.text)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.edge.occurrence.localContext.isEmpty {
                Text(item.edge.occurrence.localContext)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peerLine: Int? {
        item.direction == .incoming ? item.edge.occurrence.linkSpan.start.line : nil
    }

    private var sourceActionTitle: String {
        ScholiumL10n.dynamicString(
            item.direction == .incoming ? "Edit at Source" : "Edit Link Annotation"
        )
    }

    private var accessibilityLabel: String {
        let sourceContext = item.edge.occurrence.localContext.isEmpty
            ? ""
            : " " + ScholiumL10n.string(
                "Context: \(item.edge.occurrence.localContext)"
            )
        if let annotation = item.edge.occurrence.annotation {
            return switch item.direction {
            case .incoming:
                ScholiumL10n.string(
                    "Incoming link from \(item.displayTitle). Link annotation: \(annotation.text)"
                ) + sourceContext
            case .outgoing:
                ScholiumL10n.string(
                    "Outgoing link to \(item.displayTitle). Link annotation: \(annotation.text)"
                ) + sourceContext
            }
        }

        return switch item.direction {
        case .incoming:
            ScholiumL10n.string("Incoming link from \(item.displayTitle). No link annotation")
                + sourceContext
        case .outgoing:
            ScholiumL10n.string("Outgoing link to \(item.displayTitle). No link annotation")
                + sourceContext
        }
    }

    private var accessibilityHint: Text {
        item.direction == .incoming
            ? Text("The annotation is owned by the source Note. Use Edit at Source to change it.")
            : Text("Opens the linked Note. Use Edit Link Annotation to return to this source occurrence.")
    }

    private func openSource() {
        guard let source = item.source else { return }
        openReference(source.reference, item.edge.occurrence.linkSpan.start.line)
    }
}

#Preview {
    ConnectionsInspectorView(context: ConnectionsInspectorContext(
        graph: nil,
        catalog: nil,
        current: nil,
        freshness: .unavailable("No workspace is open."),
        retryRefresh: {},
        openReference: { _, _ in }
    ), direction: .outgoing)
    .frame(width: 320, height: 600)
}
