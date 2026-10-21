import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Notifications catalog projection")
@MainActor
struct AttentionPopoverSessionTests {
    @Test("Filtering uses the current catalog title and exact scoped stable identity")
    func catalogReplacement() {
        let fixture = Fixture()
        let first = fixture.change(path: "First.md")
        let second = fixture.change(path: "Second.md")
        fixture.changes.send([first, second])
        fixture.replace([fixture.note(first, title: "Éthique"), fixture.note(second, title: "Another")])
        fixture.session.presentation.filter = .init(query: "ethique")
        #expect(fixture.visible() == [first])

        fixture.replace([fixture.note(first, title: "Revised"), fixture.note(second, title: "Another")])
        #expect(fixture.visible().isEmpty)
        fixture.session.presentation.filter = .init(query: "revised")
        #expect(fixture.visible() == [first])
        fixture.session.presentQueue(
            anchor: .inspector, workspaceSlot: nil,
            noteScope: .init(vaultID: fixture.vault.id, relativePath: first.relativePath))
        #expect(fixture.visible() == [first])

        fixture.replace([fixture.note(second, title: "Another")])
        #expect(fixture.visible().isEmpty)
        #expect(fixture.session.noteTitle(for: first) == "First.md")
    }

    @Test("Duplicate identities retain catalog ordering and unavailable titles use the receipt path")
    func duplicateAndUnavailableTitles() {
        let fixture = Fixture()
        let change = fixture.change(path: "Folder/Receipt.md")
        fixture.replace([
            fixture.note(change, title: "First title"),
            fixture.note(change, title: "Second title", path: "Duplicate.md"),
        ])
        #expect(fixture.session.noteTitle(for: change) == "First title")
        fixture.replace([
            fixture.note(change, title: ""),
            fixture.note(change, title: "Second title", path: "Duplicate.md"),
        ])
        #expect(fixture.session.noteTitle(for: change) == "Receipt.md")
        fixture.replace([])
        #expect(fixture.session.noteTitle(for: change) == "Receipt.md")
    }

    @Test("Catalog status and row selection do not alter filtered identity or sort order")
    func independentPresentationChanges() {
        let fixture = Fixture()
        let first = fixture.change(path: "First.md", savedAt: 2)
        let second = fixture.change(path: "Second.md", savedAt: 1)
        fixture.changes.send([second, first])
        fixture.replace([fixture.note(first, title: "Topic"), fixture.note(second, title: "Topic")])
        fixture.session.presentation.filter = .init(query: "Topic")
        fixture.session.presentation.select("change:\(second.id.uuidString.lowercased())")
        fixture.projection.reportCatalogError("Synthetic refresh failure")
        #expect(fixture.visible() == [first, second])
        #expect(fixture.session.catalogIsAvailable)
        #expect(fixture.session.catalogError == "Synthetic refresh failure")
    }

    @MainActor
    private final class Fixture {
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics")
        let changes = PassthroughSubject<[DocumentChangeSummary]?, Never>()
        let projection = WindowWorkspaceProjectionController { throw DiscoverySearchExecutionError.workspaceUnavailable }
        let session: AttentionPopoverSession

        init() {
            session = AttentionPopoverSession(
                presentation: AttentionPresentationState(),
                workspaceController: WindowWorkspaceController(workspaceStore: makeTestWorkspaceStore(), requestedTriptychID: nil),
                projectionController: projection,
                dependencies: .init(
                    documentChangeChanges: changes.eraseToAnyPublisher(),
                    documentChangeErrorChanges: Just(nil).eraseToAnyPublisher(),
                    refresh: {}, showDocumentChange: { _ in }))
        }

        func replace(_ notes: [WorkspaceCatalogNote]) {
            projection.replaceCatalog(.init(generatedAt: Date(), notes: notes, attention: [], graph: nil))
        }

        func visible() -> [DocumentChangeSummary] {
            session.visibleDocumentChanges(for: session.presentation, locale: Locale(identifier: "en_US"))
        }

        func change(path: String, savedAt: TimeInterval = 0) -> DocumentChangeSummary {
            .init(
                noteID: UUID(), vaultID: vault.id, role: vault.role, relativePath: path,
                startingRevision: DocumentFingerprint(content: "Before"), endingRevision: DocumentFingerprint(content: "After"),
                savedAt: Date(timeIntervalSince1970: savedAt), baselineState: .known)
        }

        func note(_ change: DocumentChangeSummary, title: String, path: String? = nil) -> WorkspaceCatalogNote {
            .init(
                reference: .init(
                    vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                    relativePath: path ?? change.relativePath, stableNoteID: change.noteID.uuidString),
                title: title, fingerprint: change.endingRevision, validationWarnings: [])
        }
    }
}
