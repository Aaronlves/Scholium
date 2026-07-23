import Foundation

public enum ResearchNoteTitleSource: String, Codable, Hashable, Sendable {
    case analysisProperty = "analysis_property"
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

/// Resolves the one human and agent-facing note title used by Workspace,
/// Search, Link Graph, and Research Functions. Only Analysis treats YAML
/// `title` as semantic; Topic and Work are titled by their first H1.
public enum ResearchNoteTitleResolver {
    public static func resolve(
        document: NoteDocument,
        profile: SchemaProfileID,
        semantic: MarkdownSemanticDocument? = nil
    ) -> ResearchNoteTitleResolution {
        if profile == .analysis,
           case .string(let value)? = document.parsedFrontmatter["title"],
           let title = nonempty(value) {
            return ResearchNoteTitleResolution(
                title: title,
                source: .analysisProperty
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
        semantic: MarkdownSemanticDocument? = nil
    ) -> ResearchNoteTitleResolution {
        resolve(
            document: document,
            profile: WorkflowProfileResolver.resolve(
                vaultRole: vaultRole,
                frontmatter: document.parsedFrontmatter,
                relativePath: document.relativePath
            ),
            semantic: semantic
        )
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
