import Foundation
import ScholiumContracts

extension WorkspaceNoteSummary {
    /// Metadata-only publication may advance graph state while the exact
    /// source and stable Note identity remain the same.
    func hasSameSourceBinding(as other: WorkspaceNoteSummary) -> Bool {
        id.vaultID == other.id.vaultID
            && id.relativePath.utf8.elementsEqual(other.id.relativePath.utf8)
            && fingerprint == other.fingerprint
            && stableIdentity == other.stableIdentity
    }
}

struct MarkdownReviewSelection: Equatable, Sendable {
    let startLine: Int
    let endLine: Int
    let excerpt: String
    let utf16LowerBound: Int?
    let utf16UpperBound: Int?
    let contextBefore: String
    let contextAfter: String

    init(
        startLine: Int,
        endLine: Int,
        excerpt: String,
        utf16LowerBound: Int? = nil,
        utf16UpperBound: Int? = nil,
        contextBefore: String = "",
        contextAfter: String = ""
    ) {
        self.startLine = startLine
        self.endLine = endLine
        self.excerpt = excerpt
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }

    var exactUTF16Range: Range<Int>? {
        guard let utf16LowerBound, let utf16UpperBound,
            utf16UpperBound > utf16LowerBound
        else { return nil }
        return utf16LowerBound..<utf16UpperBound
    }

}

// MARK: - Workflow Profile

/// A note's semantic role is derived from the registered vault.
enum NoteProfile: String, Codable, Hashable {
    case paperAnalysis
    case topicKnowledge
    case draftProject
    case generic

    static func infer(vaultRole: VaultRole) -> Self {
        let resolved = WorkflowProfileResolver.resolve(vaultRole: vaultRole)
        switch resolved {
        case .analysis: return .paperAnalysis
        case .topicMarkdown: return .topicKnowledge
        case .draftProject: return .draftProject
        case .genericMarkdown: return .generic
        }
    }

    var displayName: String {
        switch self {
        case .paperAnalysis: ScholiumL10n.dynamicString("Analysis")
        case .topicKnowledge: ScholiumL10n.dynamicString("Topic")
        case .draftProject: ScholiumL10n.dynamicString("Work")
        case .generic: "Markdown"
        }
    }
}

// MARK: - Window Document Location

/// One window-visible document location backed by the shared immutable
/// Application snapshot for its exact Triptych vault.
enum WindowDocumentLocation: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case workspace(VaultQualifiedNoteID)
    }

    case workspace(WorkspaceNoteSummary)
    case hydrated(WorkspaceNoteSnapshot)

    var id: ID {
        switch self {
        case .workspace(let snapshot): .workspace(snapshot.id)
        case .hydrated(let snapshot): .workspace(snapshot.id)
        }
    }

    var summary: WorkspaceNoteSummary {
        switch self {
        case .workspace(let snapshot): snapshot
        case .hydrated(let snapshot): snapshot.summary
        }
    }

    var workspaceSnapshot: WorkspaceNoteSummary? { summary }

    var hydratedSnapshot: WorkspaceNoteSnapshot? {
        guard case .hydrated(let snapshot) = self else { return nil }
        return snapshot
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary == rhs.summary
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(summary)
    }
}

extension WindowDocumentLocation {
    /// Synthetic workspace-backed Note used only by SwiftUI previews and the
    /// component catalog. Production construction continues to consume an
    /// Application-owned `WorkspaceNoteSnapshot`.
    static func syntheticPreview(
        relativePath: String,
        rawContent: String,
        vaultRole: VaultRole = .other
    ) -> Self {
        let noteID = UUID()
        let document = NoteDocument(
            relativePath: relativePath,
            rawContent: rawContent
        )
        let summary = WorkspaceNoteSummary(
            id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: relativePath),
            vaultRole: vaultRole,
            stableIdentity: .resolved(noteID),
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: nil
            ),
            graphCounts: WorkspaceGraphCounts(
                incoming: 0, outgoing: 0, broken: 0, ambiguous: 0
            )
        )
        return .hydrated(WorkspaceNoteSnapshot(summary: summary, document: document))
    }
}

extension WindowDocumentLocation {
    var vaultID: UUID {
        switch self {
        case .workspace(let snapshot): snapshot.id.vaultID
        case .hydrated(let snapshot): snapshot.id.vaultID
        }
    }
    var relativePath: String { summary.id.relativePath }
    var fileName: String { (relativePath as NSString).lastPathComponent }
    var displayName: String {
        summary.title
    }
    var vaultRole: VaultRole { workspaceSnapshot?.vaultRole ?? .other }
    var profile: NoteProfile {
        NoteProfile.infer(vaultRole: vaultRole)
    }
    var title: String? { displayName }
    var aliases: [String] {
        summary.aliases
    }
    var tags: [String] { summary.keywords }
    var authors: [String] {
        summary.authors
    }

    func filterableProperties() -> [String: [String]] {
        summary.propertyTextValues
    }

    var fileModifiedAt: Date {
        workspaceSnapshot?.fileMetadata.modificationDate ?? .distantPast
    }

    var schemaProfile: SchemaProfileID {
        workspaceSnapshot?.schemaProfile
            ?? WorkflowProfileResolver.resolve(vaultRole: vaultRole)
    }

}

extension YAMLValue {
}
extension Array where Element == WindowDocumentLocation {
    /// Stable tag projection derived from the exact Core document.
    var orderedTags: [String] {
        var counts: [String: Int] = [:]
        for note in self {
            for tag in note.tags {
                let normalized = tag.lowercased().trimmingCharacters(in: .whitespaces)
                guard !normalized.isEmpty else { continue }
                counts[normalized, default: 0] += 1
            }
        }
        return counts.keys.sorted { left, right in
            let leftCount = counts[left, default: 0]
            let rightCount = counts[right, default: 0]
            return leftCount == rightCount ? left < right : leftCount > rightCount
        }
    }
}

// MARK: - Vault Configuration

struct VaultConfig: Codable {
    let path: URL
    let name: String
    let obsidianConfig: ObsidianConfig?

    struct ObsidianConfig: Codable {
        var vaultName: String?
        var theme: String?  // "obsidian" or custom theme name
        var showLineNumbers: Bool?
        var defaultViewMode: String?  // "source" or "preview"
        var attachmentFolderPath: String?
        var newLinkFormat: String?  // "shortest" or "relative" or "absolute"
    }
}
