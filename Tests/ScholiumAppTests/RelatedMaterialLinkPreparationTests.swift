import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Related material link preparation")
struct RelatedMaterialLinkPreparationTests {
    private let vault = UUID(uuidString: "B28BF38A-416C-4269-832A-35C0C0C72D6A")!
    private var origin: VaultQualifiedNoteID { .init(vaultID: vault, relativePath: "Writing/Draft.md") }
    private func reference(_ path: String, identity: String = "source") -> VaultNoteReference {
        .init(vaultID: vault, vaultName: "Analyses", vaultRole: .sourceCorpus, relativePath: path, stableNoteID: identity)
    }
    private func note(_ reference: VaultNoteReference) -> WorkspaceCatalogNote {
        .init(
            reference: reference, title: "Synthetic source", aliases: ["自主"],
            fingerprint: .init(content: "Synthetic source"), validationWarnings: [])
    }

    @Test("A batch retains exact resolver semantics for repeated, missing and unsupported references")
    func exactTargets() {
        let source = reference("FolderA/Source.md")
        let unsupported = reference("Bad#path.md", identity: "bad")
        let bad = WorkspaceCatalogNote(
            reference: unsupported, title: "Bad|title", aliases: [],
            fingerprint: .init(content: "Other"), validationWarnings: [])
        let catalog = [note(source), bad]
        let references = [source, source, reference("Missing.md"), unsupported]
        let actual = RelatedMaterialLinkPreparation.targets(for: references, catalog: catalog, from: origin)
        let resolver = LinkResolutionCatalog(
            catalog: catalog.map {
                .init(id: .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), title: $0.title, aliases: $0.aliases)
            })
        var expected: [VaultNoteReference: String] = [:]
        for reference in references where catalog.contains(where: { $0.reference == reference }) {
            if case .available(let target) = resolver.wikilinkTarget(
                for: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), from: origin)
            {
                expected[reference] = target
            }
        }
        #expect(actual == expected && actual[source] != nil)
        #expect(actual[unsupported] == nil && actual[references[2]] == nil)
        #expect(RelatedMaterialLinkPreparation.targets(for: [], catalog: catalog, from: origin).isEmpty)
    }

    @Test("A same-path replacement cannot prepare a target for the displaced stable identity")
    func replacementIdentity() {
        let displaced = reference("Source.md", identity: "displaced")
        let replacement = reference("Source.md", identity: "replacement")
        let actual = RelatedMaterialLinkPreparation.targets(for: [displaced, replacement], catalog: [note(replacement)], from: origin)
        #expect(actual[displaced] == nil && actual[replacement] != nil)
    }

    @Test("Each preparation uses its supplied catalog rather than an earlier navigation cohort")
    func independentCohorts() {
        let source = reference("FolderA/Source.md")
        let collision = reference("FolderB/Source.md", identity: "collision")
        let before = RelatedMaterialLinkPreparation.targets(for: [source], catalog: [note(source)], from: origin)
        let after = RelatedMaterialLinkPreparation.targets(for: [source], catalog: [note(source), note(collision)], from: origin)
        #expect(before[source] != nil && after[source] != nil && before[source] != after[source])
        #expect(RelatedMaterialLinkPreparation.targets(for: [source], catalog: [], from: origin).isEmpty)
        #expect(RelatedMaterialLinkPreparation.targets(for: [source], catalog: [note(source)], from: origin) == before)
    }
}
