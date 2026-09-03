import Foundation

public enum ResearchNoteTitleSource: String, Codable, Hashable, Sendable {
    case managedMetadata = "managed_metadata"
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
/// title is preferred when supplied explicitly; every other Note uses its
/// filename. Authored YAML and body headings never establish Note identity.
public enum ResearchNoteTitleResolver {
    public static func resolve(
        document: NoteDocument,
        profile: SchemaProfileID,
        metadata: NoteMetadataSnapshot? = nil
    ) -> ResearchNoteTitleResolution {
        if profile == .analysis,
           case .string(let value)? = metadata?.record.fields["title"],
           let title = nonempty(value) {
            return ResearchNoteTitleResolution(
                title: title,
                source: .managedMetadata
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
        metadata: NoteMetadataSnapshot? = nil
    ) -> ResearchNoteTitleResolution {
        resolve(
            document: document,
            profile: WorkflowProfileResolver.resolve(vaultRole: vaultRole),
            metadata: metadata
        )
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
