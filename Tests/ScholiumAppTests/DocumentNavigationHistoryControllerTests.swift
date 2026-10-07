import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document navigation history controller")
@MainActor
struct DocumentNavigationHistoryControllerTests {
    @Test("Back and Forward traverse the successful visit sequence")
    func backAndForwardTraverseVisits() throws {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let third = fixtureDocument(path: "Topics/Normativity.md")

        controller.record(first)
        controller.record(second)
        controller.record(third)

        #expect(controller.canGoBack)
        #expect(!controller.canGoForward)
        #expect(controller.target(for: .back) == second)
        #expect(controller.commit(.back, to: second))
        #expect(controller.target(for: .back) == first)
        #expect(controller.target(for: .forward) == third)
        #expect(controller.commit(.forward, to: third))
        #expect(!controller.canGoForward)
    }

    @Test("A new visit after Back discards the abandoned Forward branch")
    func newVisitDiscardsForwardBranch() throws {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let abandoned = fixtureDocument(path: "Topics/Abandoned.md")
        let replacement = fixtureDocument(path: "Topics/Replacement.md")

        controller.record(first)
        controller.record(second)
        controller.record(abandoned)
        #expect(controller.commit(.back, to: second))

        controller.record(replacement)

        #expect(controller.count == 3)
        #expect(controller.target(for: .back) == second)
        #expect(!controller.canGoForward)
    }

    @Test("Repeated activation of the current document creates no duplicate")
    func repeatedActivationCreatesNoDuplicate() {
        let controller = DocumentNavigationHistoryController()
        let document = fixtureDocument(path: "Topics/Agency.md")

        controller.record(document)
        controller.record(document)

        #expect(controller.count == 1)
        #expect(!controller.canGoBack)
        #expect(!controller.canGoForward)
    }

    @Test("Each visit retains its own revision-bound departure viewport")
    func visitPositionsRemainDistinct() {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let firstPosition = DocumentNavigationVisitPosition(
            sourceFingerprint: "agency-revision",
            scrollPosition: ObservedScrollPosition(fraction: 0.72)
        )
        let secondPosition = DocumentNavigationVisitPosition(
            sourceFingerprint: "reasons-revision",
            scrollPosition: ObservedScrollPosition(fraction: 0.31)
        )

        controller.record(first)
        controller.captureCurrent(document: first, position: firstPosition)
        controller.record(second)
        controller.captureCurrent(document: second, position: secondPosition)
        #expect(controller.position(for: .back) == firstPosition)
        #expect(controller.commit(.back, to: first))
        #expect(controller.position(for: .forward) == secondPosition)
        #expect(controller.commit(.forward, to: second))
        #expect(controller.position(for: .back) == firstPosition)
    }

    @Test("A renamed stable note keeps one current visit and its viewport")
    func renameDoesNotCreateVisit() throws {
        let controller = DocumentNavigationHistoryController()
        let original = fixtureDocument(path: "Topics/Before.md")
        let descriptor = try #require(original.workspaceDescriptor)
        let renamed = WindowSelectedDocument.workspace(
            .init(
                sessionKey: descriptor.sessionKey,
                reference: .init(
                    vaultID: descriptor.reference.vaultID,
                    vaultName: descriptor.reference.vaultName,
                    vaultRole: descriptor.reference.vaultRole,
                    relativePath: "Topics/After.md",
                    stableNoteID: descriptor.reference.stableNoteID
                )
            ))
        let position = DocumentNavigationVisitPosition(
            sourceFingerprint: "same-revision",
            scrollPosition: ObservedScrollPosition(fraction: 0.6)
        )
        controller.record(original)
        controller.captureCurrent(document: renamed, position: position)
        controller.record(renamed)
        #expect(controller.count == 1)
        #expect(controller.currentDocument == renamed)
    }

    @Test("A move retargets every visit of that identity and preserves independent return positions")
    func moveRetargetsVisits() throws {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Nested/Before.md")
        let descriptor = try #require(first.workspaceDescriptor)
        let other = fixtureDocument(path: "Other.md")
        let foreign = fixtureDocument(path: "Nested/Before.md")
        let position = DocumentNavigationVisitPosition(
            sourceFingerprint: "exact-revision", scrollPosition: ObservedScrollPosition(fraction: 0.6)
        )
        controller.record(first)
        controller.captureCurrent(document: first, position: position)
        controller.record(other)
        controller.record(first)
        controller.record(foreign)
        let revision = controller.revision

        controller.migratePath(from: "Nested/Before.md", to: "After.md", key: descriptor.sessionKey)
        #expect(controller.count == 4)
        #expect(controller.currentDocument == foreign)
        #expect(controller.target(for: .back)?.relativePath == "After.md")
        let moved = try #require(controller.target(for: .back))
        #expect(controller.commit(.back, to: moved))
        #expect(controller.commit(.back, to: other))
        #expect(controller.target(for: .back)?.relativePath == "After.md")
        #expect(controller.position(for: .back) == position)
        #expect(controller.revision > revision)
        let settledRevision = controller.revision
        controller.migratePath(from: "Nested/Before.md", to: "After.md", key: descriptor.sessionKey)
        #expect(controller.revision == settledRevision)
    }

    private func fixtureDocument(path: String) -> WindowSelectedDocument {
        let vaultID = UUID()
        let noteID = UUID()
        return .workspace(
            WindowDocumentDescriptor(
                sessionKey: DocumentSessionKey(vaultID: vaultID, noteID: noteID),
                reference: VaultNoteReference(
                    vaultID: vaultID,
                    vaultName: "Fixture Topics",
                    vaultRole: .topicKnowledge,
                    relativePath: path,
                    stableNoteID: noteID.uuidString.lowercased()
                )
            ))
    }
}
