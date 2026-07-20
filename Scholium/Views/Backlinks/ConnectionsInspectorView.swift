import ScholiumContracts
import SwiftUI

private struct InspectorRelationshipItem: Identifiable {
    let edge: LinkGraphEdge
    let peerID: VaultQualifiedNoteID?
    let peer: WorkspaceCatalogNote?
    let source: WorkspaceCatalogNote?
    let section: ScholiumConnectionPresentation

    var id: String {
        let span = edge.occurrence.span
        return [
            edge.source.vaultID.uuidString,
            edge.source.relativePath,
            peerID?.vaultID.uuidString ?? "unresolved",
            peerID?.relativePath ?? edge.occurrence.target,
            String(span.utf16LowerBound),
            String(section.rawValue),
        ].joined(separator: ":")
    }
}

/// Immutable relationship inputs for one selected document. The feature root
/// supplies the cross-feature navigation closure; inspector leaves never
/// borrow the complete window model.
struct RelationshipInspectorContext {
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let current: VaultQualifiedNoteID?
    let freshness: ResearchProjectionFreshness
    let retryRefresh: () -> Void
    let openReference: (VaultNoteReference, Int?) -> Void
}

// MARK: - Combined Connections apparatus

private enum ConnectionPeerGroup: Int, CaseIterable, Hashable {
    case analyses
    case topics
    case works

    init(role: VaultRole) {
        self = switch role {
        case .sourceCorpus: .analyses
        case .topicKnowledge: .topics
        case .draftProject: .works
        case .other: .analyses
        }
    }

    func title(currentRole: VaultRole) -> String {
        switch (currentRole, self) {
        case (.sourceCorpus, .analyses): "Neighbor Analyses"
        case (.sourceCorpus, .topics): "Related Topics"
        case (.sourceCorpus, .works): "Related Works"
        case (.topicKnowledge, .analyses): "Related Sources"
        case (.topicKnowledge, .topics): "Neighbor Topics"
        case (.topicKnowledge, .works): "Related Works"
        case (.draftProject, .analyses): "Related Sources"
        case (.draftProject, .topics): "Related Topics"
        case (.draftProject, .works): "Neighbor Works"
        case (.other, .analyses): "Related Analyses"
        case (.other, .topics): "Related Topics"
        case (.other, .works): "Related Works"
        }
    }
}

private struct CombinedConnectionsProjection {
    let currentRole: VaultRole
    let groups: [ConnectionPeerGroup: [InspectorRelationshipItem]]

    static func make(
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        current: VaultQualifiedNoteID?
    ) -> Self {
        let notesByID = Dictionary(uniqueKeysWithValues: (catalog?.notes ?? []).map {
            (VaultQualifiedNoteID(
                vaultID: $0.reference.vaultID,
                relativePath: $0.reference.relativePath
            ), $0)
        })
        let currentRole = current.flatMap { notesByID[$0]?.reference.vaultRole } ?? .other
        guard let graph, let current else {
            return Self(currentRole: currentRole, groups: [:])
        }

        var groups: [ConnectionPeerGroup: [InspectorRelationshipItem]] = [:]

        func append(
            edge: LinkGraphEdge,
            peerID: VaultQualifiedNoteID?,
            currentIsSource: Bool
        ) {
            let peer = peerID.flatMap { notesByID[$0] }
            let group = ConnectionPeerGroup(role: peer?.reference.vaultRole ?? currentRole)
            let presentation = edge.destination == nil
                ? ScholiumConnectionPresentation.neutral
                : ScholiumConnectionPresentation(
                    vectorKind: edge.occurrence.vectorKind,
                    currentIsSource: currentIsSource
                )
            groups[group, default: []].append(InspectorRelationshipItem(
                edge: edge,
                peerID: peerID,
                peer: peer,
                source: notesByID[edge.source],
                section: presentation
            ))
        }

        for edge in graph.outgoing[current] ?? [] {
            append(edge: edge, peerID: edge.destination?.note, currentIsSource: true)
        }
        for edge in graph.incoming[current] ?? [] {
            append(edge: edge, peerID: edge.source, currentIsSource: false)
        }

        for group in ConnectionPeerGroup.allCases {
            let unique = Dictionary(grouping: groups[group] ?? [], by: \.id)
                .compactMap { $0.value.first }
                .sorted {
                    if $0.section.rawValue != $1.section.rawValue {
                        return $0.section.rawValue < $1.section.rawValue
                    }
                    let lhsTitle = $0.peer?.title ?? $0.edge.occurrence.target
                    let rhsTitle = $1.peer?.title ?? $1.edge.occurrence.target
                    return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
                }
            groups[group] = unique
        }

        return Self(currentRole: currentRole, groups: groups)
    }
}

/// One scrollable Connections page. Its groups describe the other note's
/// Triptych role; the row symbol carries the explicit relationship predicate.
struct ConnectionsInspectorView: View {
    let context: RelationshipInspectorContext

    @State private var expandedGroups = Set(ConnectionPeerGroup.allCases)

    private var projection: CombinedConnectionsProjection {
        CombinedConnectionsProjection.make(
            graph: context.graph,
            catalog: context.catalog,
            current: context.current
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionSpacing) {
                ResearchProjectionFreshnessBanner(
                    freshness: context.freshness,
                    retry: context.retryRefresh
                )
                ForEach(ConnectionPeerGroup.allCases, id: \.self) { group in
                    connectionGroup(group, items: projection.groups[group] ?? [])
                }
            }
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
            .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
            .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func connectionGroup(
        _ group: ConnectionPeerGroup,
        items: [InspectorRelationshipItem]
    ) -> some View {
        let isExpanded = expandedGroups.contains(group)
        return VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            Button {
                if isExpanded { expandedGroups.remove(group) }
                else { expandedGroups.insert(group) }
            } label: {
                ScholiumApparatusRow(
                    leading: {
                        Image(systemName: "chevron.right")
                            .font(ScholiumInterfaceTypography.apparatusBody)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    },
                    content: {
                        Text(group.title(currentRole: projection.currentRole))
                            .font(ScholiumInterfaceTypography.apparatusLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    },
                    trailing: {
                        Text(items.count.formatted())
                            .font(
                                ScholiumInterfaceTypography.apparatusMetadata
                                    .monospacedDigit()
                            )
                            .foregroundStyle(.secondary)
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(group.title(currentRole: projection.currentRole))
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.rowSpacing
                ) {
                    if items.isEmpty {
                        ScholiumApparatusRow(
                            leading: {
                                Color.clear
                                    .accessibilityHidden(true)
                            },
                            content: {
                                Text("None")
                                    .font(ScholiumInterfaceTypography.apparatusBody)
                                    .foregroundStyle(.secondary)
                            }
                        )
                    } else {
                        ForEach(items) { item in
                            CombinedConnectionRow(
                                item: item,
                                openReference: context.openReference
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ScholiumMetrics.Apparatus.sectionContentInset)
            }
        }
        .accessibilityIdentifier("scholium.connectionGroup.\(group.rawValue)")
    }
}

private struct CombinedConnectionRow: View {
    let item: InspectorRelationshipItem
    let openReference: (VaultNoteReference, Int?) -> Void

    private var title: String {
        item.peer?.title
            ?? item.peerID.map {
                (($0.relativePath as NSString).lastPathComponent as NSString)
                    .deletingPathExtension
            }
            ?? item.edge.occurrence.target
    }

    var body: some View {
        ScholiumApparatusRow(
            leading: {
                Image(systemName: item.section.symbolName)
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .scholiumForeground(item.section.colorRole)
                    .accessibilityHidden(true)
            },
            content: {
                Group {
                    if let peer = item.peer {
                        Button {
                            openReference(peer.reference, nil)
                        } label: {
                            Text(title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .fixedSize(horizontal: false, vertical: true)
            },
            trailing: {
                if let source = item.source {
                    Button {
                        openReference(
                            source.reference,
                            item.edge.occurrence.span.start.line
                        )
                    } label: {
                        Image(systemName: "text.alignleft")
                            .frame(
                                width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                                height: ScholiumMetrics.Accessibility.preferredCustomTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Open the relation source")
                    .accessibilityLabel("Open relation source")
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.section.title): \(title)")
    }
}

#Preview {
    ConnectionsInspectorView(context: RelationshipInspectorContext(
        graph: nil,
        catalog: nil,
        current: nil,
        freshness: .unavailable("No workspace is open."),
        retryRefresh: {},
        openReference: { _, _ in }
    ))
        .frame(width: 320, height: 600)
}
