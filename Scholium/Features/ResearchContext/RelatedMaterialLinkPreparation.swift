import ScholiumContracts

/// One immutable catalog serves the complete, bounded card publication off the
/// UI actor. Callers revalidate that catalog before publishing or inserting.
enum RelatedMaterialLinkPreparation {
    @concurrent
    static func targets(
        for references: [VaultNoteReference], catalog: [WorkspaceCatalogNote], from source: VaultQualifiedNoteID
    ) async throws -> [VaultNoteReference: String] {
        try Task.checkCancellation()
        guard !references.isEmpty else { return [:] }
        let requested = Set(references)
        let available = Set(catalog.lazy.map(\.reference).filter { requested.contains($0) })
        try Task.checkCancellation()
        guard !available.isEmpty else { return [:] }
        let notes = try catalog.map {
            try Task.checkCancellation()
            return LinkCatalogNote(
                id: .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath),
                title: $0.title, aliases: $0.aliases)
        }
        let resolver = LinkResolutionCatalog(catalog: notes)
        try Task.checkCancellation()
        var targets: [VaultNoteReference: String] = [:]
        for reference in available {
            try Task.checkCancellation()
            if case .available(let target) = resolver.wikilinkTarget(
                for: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), from: source)
            {
                targets[reference] = target
            }
        }
        return targets
    }
}
