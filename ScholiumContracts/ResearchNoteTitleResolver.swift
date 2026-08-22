import Foundation

public enum ResearchNoteTitleSource: String, Codable, Hashable, Sendable {
    case managedMetadata = "managed_metadata"
    case firstLevelOneHeading = "first_level_one_heading"
    case filename
}

public struct ResearchNoteTitleResolution: Codable, Hashable, Sendable {
    public let title: String
    public let source: ResearchNoteTitleSource

    public init(title: String, source: ResearchNoteTitleSource) {
        self.title = title
        self.source = source
    }
}

/// Resolves the one human and agent-facing Note title. A managed Analysis
/// title is preferred when supplied explicitly; authored YAML `title` is
/// never interpreted. Otherwise the first H1 and then filename are used.
public enum ResearchNoteTitleResolver {
    public static func resolve(
        document: NoteDocument,
        profile: SchemaProfileID,
        metadata: NoteMetadataSnapshot? = nil,
        semantic: MarkdownSemanticDocument? = nil
    ) -> ResearchNoteTitleResolution {
        if profile == .analysis,
           case .string(let value)? = metadata?.record.fields["title"],
           let title = nonempty(value) {
            return ResearchNoteTitleResolution(
                title: title,
                source: .managedMetadata
            )
        }

        let semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        if let title = semantic.headings
            .first(where: { $0.level == 1 })
            .flatMap({ nonempty($0.text) }) {
            return ResearchNoteTitleResolution(
                title: title,
                source: .firstLevelOneHeading
            )
        }

        let filename = URL(fileURLWithPath: document.relativePath)
            .deletingPathExtension()
            .lastPathComponent
        return ResearchNoteTitleResolution(
            title: nonempty(filename) ?? document.relativePath,
            source: .filename
        )
    }

    public static func resolve(
        document: NoteDocument,
        vaultRole: VaultRole,
        metadata: NoteMetadataSnapshot? = nil,
        semantic: MarkdownSemanticDocument? = nil
    ) -> ResearchNoteTitleResolution {
        resolve(
            document: document,
            profile: WorkflowProfileResolver.resolve(
                vaultRole: vaultRole,
                frontmatter: document.parsedFrontmatter,
                relativePath: document.relativePath
            ),
            metadata: metadata,
            semantic: semantic
        )
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
