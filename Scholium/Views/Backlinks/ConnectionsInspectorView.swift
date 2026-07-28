import ScholiumContracts
import SwiftUI

private struct InspectorRelationshipItem: Identifiable {
    let edge: LinkGraphEdge
    let peerID: VaultQualifiedNoteID?
    let peer: WorkspaceCatalogNote?
    let source: WorkspaceCatalogNote?
    let section: ScholiumConnectionPresentation

    var id: String {
        return [
            peerID?.vaultID.uuidString ?? edge.source.vaultID.uuidString,
            peerID?.relativePath ?? edge.occurrence.target,
            String(section.rawValue),
        ].joined(separator: ":")
    }

    var displayTitle: String {
        peer?.title
            ?? peerID.map {
                (($0.relativePath as NSString).lastPathComponent as NSString)
                    .deletingPathExtension
            }
            ?? edge.occurrence.target
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
        case (.sourceCorpus, .analyses): "NEIGHBOR ANALYSES"
        case (.sourceCorpus, .topics): "RELATED TOPICS"
        case (.sourceCorpus, .works): "RELATED WORKS"
        case (.topicKnowledge, .analyses): "RELATED SOURCES"
        case (.topicKnowledge, .topics): "NEIGHBOR TOPICS"
        case (.topicKnowledge, .works): "RELATED WORKS"
        case (.draftProject, .analyses): "RELATED SOURCES"
        case (.draftProject, .topics): "RELATED TOPICS"
        case (.draftProject, .works): "NEIGHBOR WORKS"
        case (.other, .analyses): "RELATED ANALYSES"
        case (.other, .topics): "RELATED TOPICS"
        case (.other, .works): "RELATED WORKS"
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
                    let lhsTitle = $0.displayTitle
                    let rhsTitle = $1.displayTitle
                    return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
                }
            groups[group] = unique
        }

        return Self(currentRole: currentRole, groups: groups)
    }
}

private struct InspectorRelationshipCluster: Identifiable {
    let presentation: ScholiumConnectionPresentation
    let items: [InspectorRelationshipItem]

    var id: ScholiumConnectionPresentation { presentation }
}

private let connectionScrollCoordinateSpace = "scholium.connect.scroll"

/// One scrollable Connections page. Its major groups describe the other note's
/// Triptych role. Each relationship cluster owns one quiet glyph; individual
/// rows remain text-first navigation targets.
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
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing,
                pinnedViews: [.sectionHeaders]
            ) {
                ResearchProjectionFreshnessView(
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
        .coordinateSpace(name: connectionScrollCoordinateSpace)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func connectionGroup(
        _ group: ConnectionPeerGroup,
        items: [InspectorRelationshipItem]
    ) -> some View {
        let isExpanded = expandedGroups.contains(group)
        return Section {
            if isExpanded {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.relationClusterSpacing
                ) {
                    ForEach(relationshipClusters(from: items)) { cluster in
                        ConnectionRelationshipCluster(
                            cluster: cluster,
                            openReference: context.openReference
                        )
                    }
                }
                .padding(.top, ScholiumMetrics.Apparatus.sectionContentSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            connectionGroupHeader(group, itemCount: items.count, isExpanded: isExpanded)
        }
    }

    private func connectionGroupHeader(
        _ group: ConnectionPeerGroup,
        itemCount: Int,
        isExpanded: Bool
    ) -> some View {
        Button {
            if isExpanded { expandedGroups.remove(group) }
            else { expandedGroups.insert(group) }
        } label: {
            ScholiumApparatusRow(
                leading: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                },
                content: {
                    Text(group.title(currentRole: projection.currentRole))
                        .scholiumApparatusHeadingStyle()
                        .fixedSize(horizontal: false, vertical: true)
                },
                trailing: {
                    Text(itemCount.formatted())
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
        .background(ScholiumColorRole.surfaceBackground.color)
        .frame(minHeight: ScholiumGrid.Dimension.compactHierarchyRowHeight)
        .accessibilityLabel(group.title(currentRole: projection.currentRole))
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("scholium.connectionGroup.\(group.rawValue)")
    }

    private func relationshipClusters(
        from items: [InspectorRelationshipItem]
    ) -> [InspectorRelationshipCluster] {
        Dictionary(grouping: items, by: \.section)
            .map { presentation, items in
                InspectorRelationshipCluster(
                    presentation: presentation,
                    items: items
                )
            }
            .sorted { $0.presentation.rawValue < $1.presentation.rawValue }
    }
}

private struct ConnectionRelationshipCluster: View {
    let cluster: InspectorRelationshipCluster
    let openReference: (VaultNoteReference, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(cluster.items) { item in
                CombinedConnectionRow(
                    item: item,
                    openReference: openReference
                )
            }
        }
        .padding(
            .leading,
            ScholiumMetrics.Apparatus.relationGlyphColumnWidth
                + ScholiumMetrics.Apparatus.relationGlyphToTextSpacing
        )
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(connectionScrollCoordinateSpace))
                let desiredOffset = max(
                    0,
                    ScholiumMetrics.Apparatus.relationPinnedGlyphTop - frame.minY
                )
                let maximumOffset = max(
                    0,
                    geometry.size.height
                        - ScholiumMetrics.Apparatus.relationRowMinimumHeight
                )

                ScholiumConnectionGlyph(kind: cluster.presentation.glyphKind)
                    .frame(
                        width: ScholiumMetrics.Apparatus.relationGlyphSize,
                        height: ScholiumMetrics.Apparatus.relationGlyphSize
                    )
                    .frame(
                        width: ScholiumMetrics.Apparatus.relationGlyphColumnWidth,
                        height: ScholiumMetrics.Apparatus.relationRowMinimumHeight
                    )
                    .background(ScholiumColorRole.surfaceBackground.color)
                    .offset(y: min(desiredOffset, maximumOffset))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CombinedConnectionRow: View {
    let item: InspectorRelationshipItem
    let openReference: (VaultNoteReference, Int?) -> Void

    @State private var isHovering = false

    private var title: String {
        item.displayTitle
    }

    var body: some View {
        Group {
            if primaryReference != nil {
                if hasDistinctSourceRoute {
                    relationButton
                        .contextMenu {
                            Button("Open relation source", action: openSource)
                        }
                        .accessibilityAction(
                            named: Text("Open relation source"),
                            openSource
                        )
                } else {
                    relationButton
                }
            } else {
                relationLabel
                    .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                    .padding(.vertical, ScholiumMetrics.Apparatus.relationRowVerticalInset)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ScholiumMetrics.Apparatus.relationRowMinimumHeight,
                        alignment: .leading
                    )
            }
        }
        .help(item.section.title)
        .accessibilityLabel("\(item.section.title): \(title)")
    }

    private var relationButton: some View {
        Button(action: openPrimary) {
            relationLabel
        }
        .buttonStyle(ScholiumApparatusQuietRowButtonStyle(
            isHovering: isHovering,
            minimumHeight: ScholiumMetrics.Apparatus.relationRowMinimumHeight,
            verticalInset: ScholiumMetrics.Apparatus.relationRowVerticalInset
        ))
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .onHover { isHovering = $0 }
    }

    private var relationLabel: some View {
        Text(title)
            .font(ScholiumInterfaceTypography.apparatusResearchContent)
            .foregroundStyle(
                isHovering
                    ? ScholiumColorRole.primaryText.color
                    : ScholiumColorRole.secondaryText.color
            )
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryReference: VaultNoteReference? {
        item.peer?.reference ?? item.source?.reference
    }

    private var primaryLine: Int? {
        guard let primaryReference else { return nil }
        if item.peer == nil || item.source?.reference == primaryReference {
            return item.edge.occurrence.span.start.line
        }
        return nil
    }

    private var hasDistinctSourceRoute: Bool {
        guard let source = item.source?.reference,
              let primaryReference else { return false }
        return source != primaryReference || primaryLine == nil
    }

    private func openPrimary() {
        guard let primaryReference else { return }
        openReference(primaryReference, primaryLine)
    }

    private func openSource() {
        guard let source = item.source else { return }
        openReference(source.reference, item.edge.occurrence.span.start.line)
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
