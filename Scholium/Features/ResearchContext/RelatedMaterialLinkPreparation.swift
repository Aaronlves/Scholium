import ScholiumContracts

/// One immutable catalog serves the complete, bounded card publication. This
/// prepares display controls; insertion still resolves against the live catalog.
enum RelatedMaterialLinkPreparation {
    static func targets(
        for references: [VaultNoteReference], catalog: [WorkspaceCatalogNote], from source: VaultQualifiedNoteID
    ) -> [VaultNoteReference: String] {
        guard !references.isEmpty else { return [:] }
        let requested = Set(references)
        let available = Set(catalog.lazy.map(\.reference).filter { requested.contains($0) })
        guard !available.isEmpty else { return [:] }
        let resolver = LinkResolutionCatalog(
            catalog: catalog.map {
                LinkCatalogNote(
                    id: .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath),
                    title: $0.title, aliases: $0.aliases)
            })
        var targets: [VaultNoteReference: String] = [:]
        for reference in available {
            if case .available(let target) = resolver.wikilinkTarget(
                for: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), from: source)
            {
                targets[reference] = target
            }
        }
        return targets
    }
}
