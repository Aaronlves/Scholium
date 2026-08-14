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

// MARK: - Connections apparatus

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

    var emptyAnnouncement: String {
        switch self {
        case .incoming: "No Incoming Links"
        case .outgoing: "No Outgoing Links"
        }
    }

    func includes(
        currentIsSource: Bool,
        vectorKind: VectorLinkKind?
    ) -> Bool {
        if vectorKind.isUndirectedConnection { return true }
        return switch self {
        case .incoming: !currentIsSource
        case .outgoing: currentIsSource
        }
    }
}

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

private struct ConnectionsProjection {
    let currentRole: VaultRole
    let groups: [ConnectionPeerGroup: [InspectorRelationshipItem]]

    var totalCount: Int {
        groups.values.reduce(0) { $0 + $1.count }
    }

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
            let presentation = ScholiumConnectionPresentation(
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

        let candidates = (graph.outgoing[current] ?? []).map {
            (edge: $0, peerID: $0.destination?.note, currentIsSource: true)
        } + (graph.incoming[current] ?? []).map {
            (edge: $0, peerID: Optional($0.source), currentIsSource: false)
        }
        for candidate in candidates where direction.includes(
            currentIsSource: candidate.currentIsSource,
            vectorKind: candidate.edge.occurrence.vectorKind
        ) {
            append(
                edge: candidate.edge,
                peerID: candidate.peerID,
                currentIsSource: candidate.currentIsSource
            )
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

private extension Optional where Wrapped == VectorLinkKind {
    var isUndirectedConnection: Bool {
        switch self {
        case .none, .some(.neutral), .some(.incompatible): true
        case .some(.supports), .some(.opposes): false
        }
    }
}

private struct InspectorRelationshipCluster: Identifiable {
    let presentation: ScholiumConnectionPresentation
    let items: [InspectorRelationshipItem]

    var id: ScholiumConnectionPresentation { presentation }
}

private let connectionScrollTopID = "scholium.connect.top"

/// One scrollable Connections page. Its major groups describe the other note's
/// Triptych role. One native local control selects the visible direction;
/// individual rows remain text-first navigation targets.
struct ConnectionsInspectorView: View {
    let context: RelationshipInspectorContext

    @State private var expandedGroups = Set(ConnectionPeerGroup.allCases)
    @State private var direction: ConnectionDirection = .outgoing

    private var projection: ConnectionsProjection {
        ConnectionsProjection.make(
            graph: context.graph,
            catalog: context.catalog,
            current: context.current,
            direction: direction
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.sectionSpacing,
                    pinnedViews: [.sectionHeaders]
                ) {
                    if context.freshness.isActionable {
                        ResearchProjectionFreshnessView(
                            freshness: context.freshness,
                            retry: context.retryRefresh
                        )
                    }

                    ScholiumSegmentedControl(
                        selection: $direction,
                        options: ConnectionDirection.allCases.map { candidate in
                            ScholiumSegmentedControlOption(
                                candidate,
                                title: ScholiumL10n.dynamicString(candidate.title)
                            )
                        },
                        label: ScholiumL10n.dynamicString("Link Direction"),
                        size: .compact,
                        accessibilityIdentifier: "scholium.connectionDirection"
                    )
                    .frame(
                        maxWidth: ScholiumMetrics.Apparatus
                            .connectionDirectionControlMaximumWidth
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                    ForEach(ConnectionPeerGroup.allCases, id: \.self) { group in
                        connectionGroup(group, items: projection.groups[group] ?? [])
                    }
                }
                .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
                .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
                .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .id(connectionScrollTopID)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: direction) { _, selectedDirection in
                scrollProxy.scrollTo(connectionScrollTopID, anchor: .top)
                if projection.totalCount == 0 {
                    AccessibilityNotification.Announcement(
                        ScholiumL10n.dynamicString(selectedDirection.emptyAnnouncement)
                    ).post()
                }
            }
        }
    }

    private func connectionGroup(
        _ group: ConnectionPeerGroup,
        items: [InspectorRelationshipItem]
    ) -> some View {
        let isExpanded = expandedGroups.contains(group)
        return Section {
            if isExpanded && !items.isEmpty {
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
                .padding(
                    .top,
                    ScholiumMetrics.Apparatus.connectionGroupContentSpacing
                )
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
        let title = group.title(currentRole: projection.currentRole)
        return ScholiumDisclosureHeaderButton(
            isExpanded: isExpanded,
            accessibilityLabel: Text(title),
            accessibilityIdentifier: "scholium.connectionGroup.\(group.rawValue)",
            minimumHeight: ScholiumGrid.Dimension.compactHierarchyRowHeight,
            action: {
                if isExpanded { expandedGroups.remove(group) }
                else { expandedGroups.insert(group) }
            },
            label: {
                Text(title)
                    .scholiumApparatusHeadingStyle()
                    .fixedSize(horizontal: false, vertical: true)
            },
            trailing: {
                Text(itemCount.formatted())
                    .font(
                        ScholiumTypography.interface(.small, tabularDigits: true)
                    )
                    .scholiumForeground(.secondaryText)
            }
        )
        .scholiumSurface(.apparatus)
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
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            relationshipHeading

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relationshipHeading: some View {
        HStack(spacing: ScholiumMetrics.Apparatus.relationGlyphToTextSpacing) {
            Image(systemName: cluster.presentation.systemSymbol.systemName)
                .scholiumSymbolStyle(.relationship)
                .symbolRenderingMode(.monochrome)
                .scholiumForeground(.mutedText)
                .frame(width: ScholiumMetrics.Apparatus.relationGlyphColumnWidth)
                .accessibilityHidden(true)

            Text(cluster.presentation.title)
                .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                .scholiumForeground(.secondaryText)

            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)

            Text(cluster.items.count.formatted())
                .font(
                    ScholiumTypography.interface(.small, tabularDigits: true)
                )
                .scholiumForeground(.mutedText)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(cluster.presentation.title), \(cluster.items.count.formatted())"
        )
        .accessibilityAddTraits(.isHeader)
    }
}

private struct CombinedConnectionRow: View {
    let item: InspectorRelationshipItem
    let openReference: (VaultNoteReference, Int?) -> Void

    @FocusState private var isFocused: Bool

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
        .accessibilityLabel("\(item.section.title): \(title)")
        .accessibilityHint(
            item.section.isUndirected
                ? Text("This relation is undirected and appears in both link directions.")
                : Text("")
        )
    }

    private var relationButton: some View {
        Button(action: openPrimary) {
            relationLabel
        }
        .buttonStyle(ScholiumQuietRowButtonStyle(
            isFocused: isFocused,
            minimumHeight: ScholiumMetrics.Apparatus.relationRowMinimumHeight,
            verticalInset: ScholiumMetrics.Apparatus.relationRowVerticalInset
        ))
        .scholiumActivationFocus($isFocused)
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
    }

    private var relationLabel: some View {
        Text(title)
            .font(ScholiumTypography.interface(.body))
            .scholiumContentControlInk()
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
