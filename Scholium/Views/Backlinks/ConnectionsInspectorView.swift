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

    static func make(
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        current: VaultQualifiedNoteID?,
        direction: ConnectionDirection
    ) -> Self {
        let notesByID = Dictionary(
            uniqueKeysWithValues: (catalog?.notes ?? []).map {
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

struct InspectorLinkGroup: Identifiable {
    let id: String
    let title: String
    let items: [InspectorLinkItem]

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
        return groups
    }
}

struct ConnectionsInspectorView: View {
    let context: ConnectionsInspectorContext
    @ObservedObject var session: LinksInspectorSession

    private var direction: ConnectionDirection { session.direction }
    private var locationKey: String {
        "\(context.current?.vaultID.uuidString ?? ""):\(context.current?.relativePath ?? ""):\(direction.rawValue)"
    }
    private var query: Binding<String> {
        Binding(
            get: { session.location(for: locationKey).query },
            set: { value in session.update(locationKey) { $0.query = value } })
    }
    private var groups: [InspectorLinkGroup] {
        let term = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = ConnectionsProjection.make(
            graph: context.graph, catalog: context.catalog,
            current: context.current, direction: direction
        ).items.filter { item in
            term.isEmpty
                || [
                    item.displayTitle, item.edge.occurrence.localContext,
                    item.edge.occurrence.annotation?.text ?? "",
                ].contains { $0.localizedStandardContains(term) }
        }
        return InspectorLinkGroup.make(items)
    }

    private var externalLinks: [SourceResourceReferences.ExternalLink] {
        guard direction == .external else { return [] }
        let term = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.externalLinks.filter {
            term.isEmpty || $0.label.localizedStandardContains(term)
                || $0.destination.localizedStandardContains(term)
        }
    }

    var body: some View {
        VStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            InspectorLinkDirectionControl(direction: $session.direction)
                .padding(.horizontal, ResearchInspectorLayout.contentInset)
            ContextSearchField(text: query, prompt: "Find in Links", identifier: "scholium.links.search")
                .padding(.horizontal, ResearchInspectorLayout.contentInset)
            ScrollViewReader { proxy in
                List {
                    Group {
                        ResearchProjectionFreshnessView(
                            freshness: context.freshness, retry: context.retryRefresh)
                        if groups.isEmpty && externalLinks.isEmpty {
                            ScholiumApparatusStateView(
                                query.wrappedValue.isEmpty ? direction.emptyAnnouncement : "No Results",
                                systemImage: "link"
                            )
                            .accessibilityIdentifier("scholium.connections.empty")
                        }
                        if !externalLinks.isEmpty {
                            VStack(alignment: .leading, spacing: ScholiumGrid.Apparatus.contentRowGap) {
                                ForEach(externalLinks) { link in
                                    Button {
                                        context.openExternalURL(link.url)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(link.label.isEmpty ? link.url.absoluteString : link.label)
                                                .foregroundStyle(ScholiumNativeColorRole.label.color)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderless)
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
                        }
                        ForEach(groups) { group in
                            let expanded = Binding(
                                get: { !session.location(for: locationKey).collapsedGroups.contains(group.id) },
                                set: { expanded in
                                    session.update(locationKey) {
                                        if expanded {
                                            $0.collapsedGroups.remove(group.id)
                                        } else {
                                            $0.collapsedGroups.insert(group.id)
                                        }
                                    }
                                }
                            )
                            ResearchNoteGroupHeader(
                                title: group.title, role: group.items.first?.peer?.reference.vaultRole,
                                expanded: expanded
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
                            .id(group.id)
                            if expanded.wrappedValue {
                                ForEach(group.items) { item in
                                    LinkOccurrenceRow(
                                        item: item,
                                        activate: {
                                            guard let source = item.source else { return }
                                            context.openReference(
                                                source.reference, item.edge.occurrence.linkSpan.start.line)
                                        }, openReference: context.openReference)
                                }
                            }
                        }
                    }
                    .researchListRow()
                }
                .researchListStyle()
                .scrollPosition(
                    id: Binding(
                        get: { session.location(for: locationKey).scrollID },
                        set: { value in if let value { session.update(locationKey) { $0.scrollID = value } } }
                    )
                )
                .onChange(of: locationKey, initial: true) { _, key in
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
                        .font(ScholiumTypography.interface(.control))
                        .foregroundStyle(ScholiumNativeColorRole.label.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            .disabled(item.source == nil)
            .help("Show this passage")
            .accessibilityLabel(Text(contextText))
            .accessibilityValue(Text(item.edge.occurrence.annotation?.text ?? ""))
            .accessibilityIdentifier("scholium.links.occurrence." + item.id)
            if item.direction == .outgoing, item.edge.occurrence.fragment != nil,
                let peer = item.peer, let line = item.edge.destination?.span?.start.line
            {
                Button("Open Linked Passage") { openReference(peer.reference, line) }
                    .buttonStyle(.borderless)
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
