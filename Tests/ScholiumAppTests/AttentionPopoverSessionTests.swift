import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Notifications catalog projection")
@MainActor
struct AttentionPopoverSessionTests {
    @Test("Activation uses the current saved change and dismisses only after the destination accepts it")
    func activationOutcome() {
        let fixture = Fixture()
        let shown = fixture.change(path: "Before move.md")
        let current = DocumentChangeSummary(
            noteID: shown.noteID, vaultID: shown.vaultID, role: shown.role, relativePath: "After move.md",
            startingRevision: shown.startingRevision, endingRevision: DocumentFingerprint(content: "Newer saved source"),
            savedAt: Date(), baselineState: .known)
        fixture.changes.send([shown])
        fixture.session.present()
        fixture.changes.send([current])
        fixture.opening.accepts = false
        #expect(!fixture.session.inspect(shown))
        #expect(fixture.session.isPresented)
        #expect(fixture.opening.changes == [current])

        fixture.opening.accepts = true
        #expect(fixture.session.inspect(shown))
        #expect(fixture.opening.changes == [current, current])
        #expect(!fixture.session.isPresented)
        #expect(!fixture.session.inspect(shown))
        #expect(fixture.opening.changes.count == 2)
    }

    @Test("Removed, filtered and closed notification targets cannot dispatch a stale action")
    func obsoleteActivation() {
        let fixture = Fixture()
        let shown = fixture.change(path: "First.md")
        fixture.changes.send([shown])
        fixture.session.present()
        fixture.changes.send([])
        #expect(!fixture.session.inspect(shown))
        fixture.changes.send([shown])
        fixture.session.presentation.filter = .init(query: "Unrelated")
        #expect(!fixture.session.inspect(shown))
        fixture.session.dismiss()
        fixture.session.presentation.filter = .init()
        #expect(!fixture.session.inspect(shown))
        #expect(fixture.opening.changes.isEmpty)
    }

    @Test("Equal-date refreshes retain deterministic ordering")
    func stableOrdering() {
        let fixture = Fixture()
        let first = fixture.change(path: "First.md")
        let second = fixture.change(path: "Second.md")
        fixture.changes.send([first, second])
        let initial = fixture.visible()
        fixture.changes.send([second, first])
        #expect(fixture.visible() == initial)
    }

    @Test("The complete queue preserves vault-qualified titles when stable Note IDs collide")
    func vaultQualifiedTitles() {
        let fixture = Fixture()
        let first = fixture.change(path: "First.md")
        let second = DocumentChangeSummary(
            noteID: first.noteID, vaultID: UUID(), role: .sourceCorpus, relativePath: "Second.md",
            startingRevision: first.startingRevision, endingRevision: first.endingRevision,
            savedAt: first.savedAt, baselineState: .known)
        let other = WorkspaceCatalogNote(
            reference: .init(
                vaultID: second.vaultID, vaultName: "Analyses", vaultRole: second.role,
                relativePath: second.relativePath, stableNoteID: second.noteID.uuidString),
            title: "Second title", fingerprint: second.endingRevision, validationWarnings: [])
        fixture.replace([fixture.note(first, title: "First title"), other])
        fixture.changes.send([first, second])
        #expect(Set(fixture.visible()) == Set([first, second]))
        #expect(fixture.session.noteTitle(for: first) == "First title")
        #expect(fixture.session.noteTitle(for: second) == "Second title")
    }

    @Test("Filtering uses current catalog titles and retires removed titles")
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
        fixture.session.presentation.select("change:\(second.vaultID.uuidString.lowercased()):\(second.noteID.uuidString.lowercased())")
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
        let opening = Opening()

        init() {
            let opening = opening
            session = AttentionPopoverSession(
                presentation: AttentionPresentationState(),
                workspaceController: WindowWorkspaceController(workspaceStore: makeTestWorkspaceStore(), requestedTriptychID: nil),
                projectionController: projection,
                dependencies: .init(
                    documentChangeChanges: changes.eraseToAnyPublisher(),
                    documentChangeErrorChanges: Just(nil).eraseToAnyPublisher(),
                    refresh: {},
                    showDocumentChange: { change in
                        opening.changes.append(change)
                        return opening.accepts
                    }))
        }

        func replace(_ notes: [WorkspaceCatalogNote]) {
            projection.replaceCatalog(.init(generatedAt: Date(), notes: notes, attention: [], graph: nil))
        }

        func visible() -> [DocumentChangeSummary] {
            session.visibleDocumentChanges(locale: Locale(identifier: "en_US"))
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

    @MainActor
    private final class Opening {
        var accepts = true
        var changes: [DocumentChangeSummary] = []
    }
}
