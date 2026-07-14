import ScholiumCore
import SwiftUI

// MARK: - Relationship projection

private enum InspectorRelationshipMode {
    case incoming
    case outgoing
}

private enum VectorRelationshipSection: String, CaseIterable, Identifiable {
    case supports
    case supportedBy
    case incompatible
    case related

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supports: "Supports"
        case .supportedBy: "Supported By"
        case .incompatible: "Incompatible With"
        case .related: "Related"
        }
    }

    var symbol: String {
        switch self {
        case .supports: "arrow.right.circle"
        case .supportedBy: "arrow.left.circle"
        case .incompatible: "xmark.circle"
        case .related: "link"
        }
    }

    var color: Color {
        switch self {
        case .supports, .supportedBy: .teal
        case .incompatible: .purple
        case .related: .secondary
        }
    }
}

private struct InspectorRelationshipItem: Identifiable {
    let edge: LinkGraphEdge
    let peerID: VaultQualifiedNoteID?
    let peer: WorkspaceCatalogNote?
    let source: WorkspaceCatalogNote?
    let section: VectorRelationshipSection

    var id: String {
        let span = edge.occurrence.span
        return [
            edge.source.vaultID.uuidString,
            edge.source.relativePath,
            peerID?.vaultID.uuidString ?? "unresolved",
            peerID?.relativePath ?? edge.occurrence.target,
            String(span.utf16LowerBound),
            section.rawValue,
        ].joined(separator: ":")
    }
}

private struct InspectorRelationshipProjection {
    let sections: [(VectorRelationshipSection, [InspectorRelationshipItem])]

    var count: Int {
        sections.reduce(0) { $0 + $1.1.count }
    }

    static func make(
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        current: VaultQualifiedNoteID?,
        mode: InspectorRelationshipMode
    ) -> Self {
        guard let graph, let current else { return Self(sections: []) }
        let notesByID = Dictionary(uniqueKeysWithValues: (catalog?.notes ?? []).map {
            (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0)
        })
        var groups: [VectorRelationshipSection: [InspectorRelationshipItem]] = [:]

        for edge in graph.outgoing[current] ?? [] {
            append(
                edge: edge,
                peerID: edge.destination?.note,
                currentIsAuthoredSource: true,
                requestedMode: mode,
                notesByID: notesByID,
                groups: &groups
            )
        }
        for edge in graph.incoming[current] ?? [] {
            append(
                edge: edge,
                peerID: edge.source,
                currentIsAuthoredSource: false,
                requestedMode: mode,
                notesByID: notesByID,
                groups: &groups
            )
        }

        let visibleSections: [VectorRelationshipSection] = mode == .incoming
            ? [.supportedBy, .incompatible, .related]
            : [.supports, .incompatible, .related]
        return Self(sections: visibleSections.compactMap { section in
            guard let items = groups[section], !items.isEmpty else { return nil }
            return (section, items.sorted(by: relationshipOrder))
        })
    }

    private static func append(
        edge: LinkGraphEdge,
        peerID: VaultQualifiedNoteID?,
        currentIsAuthoredSource: Bool,
        requestedMode: InspectorRelationshipMode,
        notesByID: [VaultQualifiedNoteID: WorkspaceCatalogNote],
        groups: inout [VectorRelationshipSection: [InspectorRelationshipItem]]
    ) {
        let semantic: (VectorRelationshipSection, InspectorRelationshipMode)
        if edge.destination == nil {
            semantic = (.related, .outgoing)
        } else {
            semantic = switch (edge.occurrence.vectorKind, currentIsAuthoredSource) {
            case (.supportsTarget, true), (.supportedByTarget, false):
                (.supports, .outgoing)
            case (.supportsTarget, false), (.supportedByTarget, true):
                (.supportedBy, .incoming)
            case (.incompatible, true):
                (.incompatible, .outgoing)
            case (.incompatible, false):
                (.incompatible, .incoming)
            case (.neutral, true), (.none, true):
                (.related, .outgoing)
            case (.neutral, false), (.none, false):
                (.related, .incoming)
            }
        }
        guard semantic.1 == requestedMode else { return }
        groups[semantic.0, default: []].append(InspectorRelationshipItem(
            edge: edge,
            peerID: peerID,
            peer: peerID.flatMap { notesByID[$0] },
            source: notesByID[edge.source],
            section: semantic.0
        ))
    }

    private static func relationshipOrder(
        _ lhs: InspectorRelationshipItem,
        _ rhs: InspectorRelationshipItem
    ) -> Bool {
        let lhsTitle = lhs.peer?.title ?? lhs.edge.occurrence.target
        let rhsTitle = rhs.peer?.title ?? rhs.edge.occurrence.target
        if lhsTitle != rhsTitle {
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
        }
        return lhs.edge.occurrence.span.utf16LowerBound < rhs.edge.occurrence.span.utf16LowerBound
    }
}

// MARK: - Incoming relationships

struct BacklinksPanelView: View {
    @EnvironmentObject var appState: AppState

    private var currentID: VaultQualifiedNoteID? {
        guard let vaultID = appState.currentRegisteredVault?.id,
              let path = appState.currentNote?.relativePath else { return nil }
        return VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
    }

    private var projection: InspectorRelationshipProjection {
        InspectorRelationshipProjection.make(
            graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
            catalog: appState.workspaceCatalog,
            current: currentID,
            mode: .incoming
        )
    }

    var body: some View {
        RelationshipPanel(
            title: "Incoming Links",
            symbol: "arrow.turn.down.left",
            emptyTitle: "No Incoming Links",
            emptyDescription: "Supporting, incompatible, and related notes will appear here with their authoritative source line.",
            projection: projection
        )
    }
}

// MARK: - Outgoing relationships

struct OutgoingLinksPanelView: View {
    @EnvironmentObject var appState: AppState
    let note: Note

    private var currentID: VaultQualifiedNoteID? {
        guard let vaultID = appState.currentRegisteredVault?.id else { return nil }
        return VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
    }

    private var projection: InspectorRelationshipProjection {
        InspectorRelationshipProjection.make(
            graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
            catalog: appState.workspaceCatalog,
            current: currentID,
            mode: .outgoing
        )
    }

    var body: some View {
        RelationshipPanel(
            title: "Outgoing Links",
            symbol: "arrow.turn.up.right",
            emptyTitle: "No Outgoing Links",
            emptyDescription: "Supported, incompatible, and related notes will appear here with their authoritative source line.",
            projection: projection
        )
    }
}

// MARK: - Shared panel
// MARK: - Shared panel

private struct RelationshipPanel: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let symbol: String
    let emptyTitle: String
    let emptyDescription: String
    let projection: InspectorRelationshipProjection

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
                Text(projection.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if appState.workspaceCatalog?.graph == nil && appState.relationshipGraph == nil {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing Relationships…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projection.count == 0 {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "link",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(projection.sections, id: \.0) { section, items in
                        Section {
                            ForEach(items) { item in
                                InspectorRelationshipRow(item: item)
                            }
                        } header: {
                            VectorSectionHeader(section: section, count: items.count)
                        }
                    }

                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct VectorSectionHeader: View {
    let section: VectorRelationshipSection
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.symbol)
                .foregroundStyle(section.color)
            Text(section.title)
                .foregroundStyle(.primary)
            Spacer()
            Text(count.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .textCase(nil)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct InspectorRelationshipRow: View {
    @EnvironmentObject private var appState: AppState
    let item: InspectorRelationshipItem

    private var peerTitle: String {
        item.peer?.title
            ?? item.peerID.map {
                (($0.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            }
            ?? item.edge.occurrence.target
    }

    private var sourceTitle: String {
        guard let source = item.source else {
            return "Authored in \(item.edge.source.relativePath)"
        }
        if source.reference.vaultID == appState.currentRegisteredVault?.id,
           source.reference.relativePath == appState.currentNote?.relativePath {
            return "Authored here"
        }
        return "Authored in \(source.title)"
    }

    private var resolutionText: String? {
        switch item.edge.occurrence.resolution {
        case .resolved: nil
        case .ambiguous(let candidates): "Ambiguous · \(candidates.count) matches"
        case .broken: "Broken link"
        case .unresolved: "Unresolved"
        }
    }

    private var sourceLine: Int {
        item.edge.occurrence.span.start.line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let peer = item.peer {
                Button {
                    Task { await appState.openWorkspaceReference(peer.reference) }
                } label: {
                    relationLabel
                }
                .buttonStyle(.plain)
                .help("Open \(peerTitle)")
            } else {
                relationLabel
            }

            HStack(spacing: 5) {
                Text(sourceTitle)
                    .lineLimit(1)
                if let resolutionText {
                    Text("·")
                    Text(resolutionText)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                Button {
                    guard let source = item.source else { return }
                    Task {
                        await appState.openWorkspaceReference(
                            source.reference,
                            line: sourceLine
                        )
                    }
                } label: {
                    Label("Line \(sourceLine)", systemImage: "text.alignleft")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .disabled(item.source == nil)
                .help("Open the authoritative relation source")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.section.title): \(peerTitle)")
    }

    private var relationLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.section.symbol)
                .font(.callout)
                .foregroundStyle(item.section.color)
                .frame(width: 16)
            Text(peerTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    BacklinksPanelView()
        .environmentObject(AppState())
        .frame(width: 320, height: 600)
}
