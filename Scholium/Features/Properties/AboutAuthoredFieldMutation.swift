import ScholiumContracts

/// Pure translation from one About-authored field draft to the existing exact
/// source mutation contract. It owns no source bytes or persistence.
enum AboutAuthoredFieldMutation {
    static func changeSet(
        document: NoteDocument,
        key: String,
        value: YAMLValue?
    ) throws -> NoteChangeSet? {
        let edit = try frontmatterEdit(key: key, value: value)
        if document.rawFrontmatter == nil {
            if case .remove = edit { return nil }
            return .insertFrontmatter([key: edit])
        }
        return .frontmatter([key: edit])
    }

    private static func frontmatterEdit(
        key: String,
        value: YAMLValue?
    ) throws -> FrontmatterEditValue {
        guard key == "summary" || key == "keywords" else {
            throw VaultRepositoryError.invalidFrontmatter(
                "Only Summary and Keywords are authored About fields."
            )
        }
        guard let value else { return .remove }
        switch (key, value) {
        case ("summary", .string(let text)):
            return .string(text)
        case ("keywords", .array(let values)):
            let strings = try values.map { value -> String in
                guard case .string(let text) = value else {
                    throw VaultRepositoryError.invalidFrontmatter(
                        "Keywords must contain only text values."
                    )
                }
                return text
            }
            return .array(strings)
        default:
            throw VaultRepositoryError.invalidFrontmatter(
                "The authored About value does not match its source field."
            )
        }
    }
}
