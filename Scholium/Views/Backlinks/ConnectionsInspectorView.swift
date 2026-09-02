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

    var emptyAnnouncement: String {
        switch self {
        case .incoming: "No Incoming Links"
        case .outgoing: "No Outgoing Links"
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
        case (.sourceCorpus, .analyses): "LINKED ANALYSES"
        case (.sourceCorpus, .topics): "LINKED TOPICS"
        case (.sourceCorpus, .works): "LINKED WORKS"
        case (.topicKnowledge, .analyses): "LINKED SOURCES"
        case (.topicKnowledge, .topics): "LINKED TOPICS"
        case (.topicKnowledge, .works): "LINKED WORKS"
        case (.draftProject, .analyses): "LINKED SOURCES"
        case (.draftProject, .topics): "LINKED TOPICS"
        case (.draftProject, .works): "LINKED WORKS"
        case (.other, .analyses): "LINKED ANALYSES"
        case (.other, .topics): "LINKED TOPICS"
        case (.other, .works): "LINKED WORKS"
        }
    }
}

private struct ConnectionsProjection {
    let currentRole: VaultRole
    let groups: [ConnectionPeerGroup: [InspectorLinkItem]]

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

        let edges = switch direction {
        case .incoming: graph.incoming[current] ?? []
        case .outgoing: graph.outgoing[current] ?? []
        }
        var groups: [ConnectionPeerGroup: [InspectorLinkItem]] = [:]
        for edge in edges {
            let peerID = direction == .incoming ? edge.source : edge.destination?.note
            let peer = peerID.flatMap { notesByID[$0] }
            let group = ConnectionPeerGroup(role: peer?.reference.vaultRole ?? currentRole)
            groups[group, default: []].append(InspectorLinkItem(
                edge: edge,
                peer: peer,
                source: notesByID[edge.source],
                direction: direction
            ))
        }
        for group in ConnectionPeerGroup.allCases {
            groups[group] = (groups[group] ?? []).sorted {
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
        }
        return Self(currentRole: currentRole, groups: groups)
    }
}

private let connectionScrollTopID = "scholium.connect.top"

struct ConnectionsInspectorView: View {
    let context: ConnectionsInspectorContext

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
        items: [InspectorLinkItem]
    ) -> some View {
        let isExpanded = expandedGroups.contains(group)
        return Section {
            if isExpanded && !items.isEmpty {
                LazyVStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.connectionOccurrenceSpacing) {
                    ForEach(items) { item in
                        LinkOccurrenceRow(
                            item: item,
                            openReference: context.openReference
                        )
                    }
                }
                .padding(.top, ScholiumMetrics.Apparatus.connectionGroupContentSpacing)
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
                    .font(ScholiumTypography.interface(.small, tabularDigits: true))
                    .scholiumForeground(.secondaryText)
            }
        )
        .scholiumSurface(.apparatus)
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
                .buttonStyle(ScholiumQuietRowButtonStyle(
                    isFocused: isFocused,
                    minimumHeight: ScholiumMetrics.Apparatus.connectionOccurrenceMinimumHeight,
                    verticalInset: ScholiumMetrics.Apparatus.connectionOccurrenceVerticalInset
                ))
                .scholiumActivationFocus($isFocused)
                .contextMenu {
                    if item.edge.occurrence.annotation != nil {
                        Button(sourceActionTitle, action: openSource)
                    }
                }
                .accessibilityAction(named: Text(sourceActionTitle), openSource)
            } else {
                label
                    .padding(.vertical, ScholiumMetrics.Apparatus.connectionOccurrenceVerticalInset)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
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
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.edge.occurrence.localContext.isEmpty {
                Text(item.edge.occurrence.localContext)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.mutedText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var peerLine: Int? {
        item.direction == .incoming ? item.edge.occurrence.linkSpan.start.line : nil
    }

    private var sourceActionTitle: String {
        item.direction == .incoming ? "Edit at Source" : "Edit Link Annotation"
    }

    private var accessibilityLabel: String {
        let directionText = item.direction == .incoming ? "Incoming link from" : "Outgoing link to"
        let annotation = item.edge.occurrence.annotation.map {
            ". Link annotation: \($0.text)"
        } ?? ". No link annotation"
        return "\(directionText) \(item.displayTitle)\(annotation)"
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
    ))
    .frame(width: 320, height: 600)
}
