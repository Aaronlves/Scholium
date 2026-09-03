import Foundation

/// Resolves the one human and agent-facing Note title from its filename.
/// Academic titles in Analysis Metadata, authored YAML, and body headings are
/// content rather than Note identity.
public enum ResearchNoteTitleResolver {
    public static func resolve(document: NoteDocument) -> String {
        let filename = URL(fileURLWithPath: document.relativePath)
            .deletingPathExtension()
            .lastPathComponent
        return nonempty(filename) ?? document.relativePath
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
