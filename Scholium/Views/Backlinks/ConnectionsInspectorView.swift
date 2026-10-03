import ScholiumContracts
import SwiftUI

/// Window-local navigation context; it never owns graph or source data.
@MainActor
final class LinksInspectorSession: ObservableObject {
    struct Location {
        var query = ""
        var scrollID: String?
        var collapsedGroups: Set<String> = []
    }
    @Published var direction: ConnectionDirection = .incoming
    @Published private var locations: [String: Location] = [:]

    func location(for key: String) -> Location { locations[key] ?? Location() }
    func update(_ key: String, _ change: (inout Location) -> Void) {
        var location = location(for: key)
        change(&location)
        locations[key] = location
    }
    func reset() {
        locations = [:]
        direction = .incoming
    }
}

struct InspectorLinkItem: Identifiable {
    let edge: LinkGraphEdge
    let peer: WorkspaceCatalogNote?
    let source: WorkspaceCatalogNote?
    let direction: ConnectionDirection
    let diagnostic: LinkGraphDiagnostic?

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

    func matches(_ term: String) -> Bool {
        term.isEmpty
            || [
                displayTitle,
                peer?.reference.relativePath ?? "",
                edge.occurrence.target,
                edge.occurrence.localContext,
                edge.occurrence.annotation?.text ?? "",
            ].contains { $0.localizedStandardContains(term) }
    }

    var diagnosticTitle: String? {
        guard let diagnostic else { return nil }
        switch diagnostic.code {
        case .broken: return ScholiumL10n.string("Missing target note")
        case .ambiguous: return ScholiumL10n.string("Ambiguous target note")
        case .missingHeading: return ScholiumL10n.string("Missing heading")
        case .ambiguousHeading: return ScholiumL10n.string("Ambiguous heading")
        case .missingBlock: return ScholiumL10n.string("Missing paragraph anchor")
        case .ambiguousBlock: return ScholiumL10n.string("Ambiguous paragraph anchor")
        }
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
    var externalLinks: [SourceResourceReferences.ExternalLink] = []
    var openExternalURL: (URL) -> Void = { _ in }
}

enum ConnectionDirection: String, CaseIterable, Identifiable, Sendable {
    case incoming
    case outgoing
    case external

    var id: Self { self }

    var tabTitle: String {
        switch self {
        case .incoming: "Incoming"
        case .outgoing: "Outgoing"
        case .external: "External"
        }
    }

    var symbol: String {
        switch self {
        case .incoming: "arrow.down.left"
        case .outgoing: "arrow.up.right"
        case .external: "globe"
        }
    }

    var title: String {
        switch self {
        case .incoming: "Incoming Links"
        case .outgoing: "Outgoing Links"
        case .external: "External Links"
        }
    }

    var emptyAnnouncement: LocalizedStringResource {
        switch self {
        case .incoming: "No Incoming Links"
        case .outgoing: "No Outgoing Links"
        case .external: "No External Links"
        }
    }
}

struct ConnectionsProjection {
    let items: [InspectorLinkItem]

    private struct OccurrenceLocation: Hashable {
        let source: VaultQualifiedNoteID
        let span: SourceSpan
    }

    static func make(
        graph: GraphSnapshot?,
        catalogNotes: [WorkspaceCatalogNote]?,
        current: VaultQualifiedNoteID?,
        direction: ConnectionDirection
    ) -> Self {
        let notesByID = Dictionary(
            uniqueKeysWithValues: (catalogNotes ?? []).map {
                (
                    VaultQualifiedNoteID(
                        vaultID: $0.reference.vaultID,
                        relativePath: $0.reference.relativePath
                    ), $0
                )
            })
        guard let graph, let current else {
            return Self(items: [])
        }
        let diagnosticsByLocation = Dictionary(
            grouping: graph.diagnostics,
            by: { OccurrenceLocation(source: $0.source, span: $0.span) }
        )

        let edges: [LinkGraphEdge] =
            switch direction {
            case .incoming: graph.incoming[current] ?? []
            case .outgoing: graph.outgoing[current] ?? []
            case .external: []
            }
        let items = edges.map { edge in
            let peerID = direction == .incoming ? edge.source : edge.destination?.note
            let peer = peerID.flatMap { notesByID[$0] }
            return InspectorLinkItem(
                edge: edge,
                peer: peer,
                source: notesByID[edge.source],
                direction: direction,
                diagnostic: diagnosticsByLocation[
                    OccurrenceLocation(source: edge.source, span: edge.occurrence.span)
                ]?.first
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

struct InspectorLinkGroup: Identifiable {
    let id: String
    let title: String
    let items: [InspectorLinkItem]
    var directoryContext: String? = nil

    var relativePath: String? { items.first?.peer?.reference.relativePath }

    static func make(_ items: [InspectorLinkItem]) -> [Self] {
        var groups: [Self] = []
        for item in items {
            let peer = item.peer?.reference
            let key =
                peer.map { "\($0.vaultID):\($0.relativePath)" }
                ?? "unresolved:" + item.edge.occurrence.target
            if let index = groups.firstIndex(where: { $0.id == key }) {
                let previous = groups[index]
                groups[index] = Self(id: key, title: previous.title, items: previous.items + [item])
            } else {
                groups.append(Self(id: key, title: item.displayTitle, items: [item]))
            }
        }
        let titleCounts = Dictionary(
            groups.map { ($0.title, 1) },
            uniquingKeysWith: +
        )
        for index in groups.indices {
            guard titleCounts[groups[index].title, default: 0] > 1,
                let reference = groups[index].items.first?.peer?.reference
            else { continue }
            let folder = (reference.relativePath as NSString).deletingLastPathComponent
            groups[index].directoryContext =
                folder.isEmpty
                ? reference.vaultName
                : reference.vaultName + " / " + folder
        }
        return groups
    }
}

/// One immutable native List row per element. Disclosure changes the input
/// collection rather than the number of rows emitted by a nested ForEach.
enum InspectorLinkRow: Identifiable {
    case freshness(ResearchProjectionFreshness)
    case empty(LocalizedStringResource)
    case external([SourceResourceReferences.ExternalLink])
    case group(InspectorLinkGroup, separatesFromPrevious: Bool)
    case occurrence(InspectorLinkItem)

    var id: String {
        switch self {
        case .freshness: "links-state:freshness"
        case .empty: "links-state:empty"
        case .external: "links-state:external"
        case .group(let group, _): group.id
        case .occurrence(let item): "links-occurrence:" + item.id
        }
    }

    static func make(
        groups: [InspectorLinkGroup],
        external: [SourceResourceReferences.ExternalLink],
        collapsedGroups: Set<String>,
        freshness: ResearchProjectionFreshness,
        emptyAnnouncement: LocalizedStringResource
    ) -> [Self] {
        var rows: [Self] = freshness.isActionable ? [.freshness(freshness)] : []
        if groups.isEmpty, external.isEmpty { rows.append(.empty(emptyAnnouncement)) }
        if !external.isEmpty { rows.append(.external(external)) }
        for (index, group) in groups.enumerated() {
            rows.append(.group(group, separatesFromPrevious: index > 0))
            if !collapsedGroups.contains(group.id) {
                rows.append(contentsOf: group.items.map(Self.occurrence))
            }
        }
        return rows
    }
}

struct ConnectionsInspectorView: View {
    let context: ConnectionsInspectorContext
    @ObservedObject var session: LinksInspectorSession
    var isActive = true

    private var direction: ConnectionDirection { session.direction }
    private var locationKey: String {
        "\(context.current?.vaultID.uuidString ?? ""):\(context.current?.relativePath ?? ""):\(direction.rawValue)"
    }
    private func query(for key: String) -> Binding<String> {
        Binding(
            get: { session.location(for: key).query },
            set: { value in session.update(key) { $0.query = value } })
    }

    var body: some View {
        let key = locationKey
        let location = session.location(for: key)
        let term = location.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = ConnectionsProjection.make(
            graph: context.graph, catalogNotes: context.catalog?.notes,
            current: context.current, direction: direction
        ).items.filter { $0.matches(term) }
        let groups = InspectorLinkGroup.make(items)
        let external =
            direction == .external
            ? context.externalLinks.filter {
                term.isEmpty || $0.label.localizedStandardContains(term)
                    || $0.destination.localizedStandardContains(term)
            } : []
        let rows = InspectorLinkRow.make(
            groups: groups, external: external,
            collapsedGroups: location.collapsedGroups, freshness: context.freshness,
            emptyAnnouncement: location.query.isEmpty ? direction.emptyAnnouncement : "No Results")
        VStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            InspectorLinkDirectionControl(direction: $session.direction, isActive: isActive)
                .padding(.horizontal, ResearchInspectorLayout.contentInset)
            ContextSearchField(
                text: query(for: key), prompt: "Find in Links",
                identifier: "scholium.links.search", isActive: isActive
            )
            .padding(.horizontal, ResearchInspectorLayout.contentInset)
            ScrollViewReader { proxy in
                List {
                    ForEach(rows) { row in
                        // Keep one concrete native row even when its semantic
                        // content is conditional or a group is collapsed.
                        VStack(alignment: .leading, spacing: 0) {
                            rowContent(row, locationKey: key)
                        }
                        .id(row.id)
                        .researchListRow()
                    }
                }
                .researchListStyle()
                .scrollPosition(
                    id: Binding(
                        get: { session.location(for: key).scrollID },
                        set: { value in if let value { session.update(key) { $0.scrollID = value } } }
                    )
                )
                .onChange(of: key, initial: true) { _, key in
                    if let id = session.location(for: key).scrollID {
                        proxy.scrollTo(id, anchor: .top)
                    } else if let id = groups.first?.id {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
                .accessibilityLabel(Text(verbatim: ScholiumL10n.dynamicString(direction.title)))
            }
        }
        .padding(.top, ResearchInspectorLayout.topInset)
    }

    @ViewBuilder
    private func rowContent(_ row: InspectorLinkRow, locationKey key: String) -> some View {
        switch row {
        case .freshness(let freshness):
            ResearchProjectionFreshnessView(freshness: freshness, retry: context.retryRefresh)
        case .empty(let announcement):
            ScholiumApparatusStateView(announcement, systemImage: "link")
                .accessibilityIdentifier("scholium.connections.empty")
        case .external(let links):
            VStack(alignment: .leading, spacing: ScholiumGrid.Apparatus.contentRowGap) {
                ForEach(links) { link in
                    Button {
                        context.openExternalURL(link.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.label.isEmpty ? link.url.absoluteString : link.label)
                                .foregroundStyle(ScholiumNativeColorRole.label.color)
                                .scholiumContentControlInk(resting: .primaryText, emphasized: .accent)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .scholiumActivationPointer()
                    .scholiumContentControlPointerFeedback(
                        in: RoundedRectangle(cornerRadius: ScholiumShape.editorialControlCornerRadius, style: .continuous)
                    )
                    .disabled(!link.canOpen)
                    .help(link.destination)
                    .contextMenu {
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.destination, forType: .string)
                        }
                    }
                    .accessibilityHint("Open External Link")
                    .accessibilityIdentifier("scholium.links.external.\(link.id)")
                }
            }
            .accessibilityElement(children: .contain)
        case .group(let group, let separatesFromPrevious):
            let expanded = Binding(
                get: { !session.location(for: key).collapsedGroups.contains(group.id) },
                set: { expanded in
                    session.update(key) {
                        if expanded { $0.collapsedGroups.remove(group.id) } else { $0.collapsedGroups.insert(group.id) }
                    }
                })
            ResearchNoteGroupHeader(
                title: group.title, role: group.items.first?.peer?.reference.vaultRole,
                expanded: expanded, occurrenceCount: group.items.count,
                directoryContext: group.directoryContext, relativePath: group.relativePath,
                separatesFromPreviousGroup: separatesFromPrevious
            ) {
                if let peer = group.items.first?.peer {
                    Button("Open Linked Note") { context.openReference(peer.reference, nil) }
                }
            }
            .contextMenu {
                if let peer = group.items.first?.peer {
                    Button("Open Linked Note") { context.openReference(peer.reference, nil) }
                }
            }
            .accessibilityIdentifier("scholium.links.group." + group.id)
        case .occurrence(let item):
            LinkOccurrenceRow(
                item: item,
                activate: {
                    guard let source = item.source else { return }
                    context.openReference(source.reference, item.edge.occurrence.linkSpan.start.line)
                }, openReference: context.openReference)
        }
    }
}

private struct LinkOccurrenceRow: View {
    let item: InspectorLinkItem
    let activate: () -> Void
    let openReference: (VaultNoteReference, Int?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: activate) {
                ResearchPassageCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ResearchPassageHighlight.link(
                            in: contextText, label: item.edge.occurrence.alias ?? item.edge.occurrence.target
                        )
                        .textRenderer(ResearchHighlightRenderer())
                        .foregroundStyle(ScholiumNativeColorRole.label.color)
                        .scholiumContentControlInk(
                            resting: .primaryText,
                            emphasized: .accent
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let diagnosticTitle = item.diagnosticTitle {
                            Label(diagnosticTitle, systemImage: "exclamationmark.triangle")
                                .font(ScholiumTypography.interface(.small))
                                .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                                .help(diagnosticTitle)
                        }
                        if let annotation = item.edge.occurrence.annotation {
                            Divider()
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "text.bubble")
                                    .accessibilityHidden(true)
                                Text(annotation.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(ScholiumTypography.interface(.body))
                            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .scholiumActivationPointer()
            .scholiumContentControlPointerFeedback(
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialPanelCornerRadius,
                    style: .continuous
                )
            )
            .disabled(item.source == nil)
            .help("Show this passage")
            .accessibilityLabel(Text(verbatim: [item.diagnosticTitle, contextText].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityValue(Text(item.edge.occurrence.annotation?.text ?? ""))
            .accessibilityIdentifier("scholium.links.occurrence." + item.id)
            if item.direction == .outgoing, item.edge.occurrence.fragment != nil,
                let peer = item.peer, let line = item.edge.destination?.span?.start.line
            {
                Button {
                    openReference(peer.reference, line)
                } label: {
                    Text("Open Linked Passage")
                }
                .buttonStyle(ScholiumContentActionButtonStyle())
            }
        }
    }

    private var contextText: String {
        let occurrence = item.edge.occurrence
        return ResearchExcerptPresentation.readableText(
            occurrence.localContext.isEmpty ? occurrence.target : occurrence.localContext)
    }

}

#Preview {
    ConnectionsInspectorView(
        context: ConnectionsInspectorContext(
            graph: nil,
            catalog: nil,
            current: nil,
            freshness: .unavailable("No workspace is open."),
            retryRefresh: {},
            openReference: { _, _ in }
        ), session: LinksInspectorSession()
    )
    .frame(width: 320, height: 600)
}
