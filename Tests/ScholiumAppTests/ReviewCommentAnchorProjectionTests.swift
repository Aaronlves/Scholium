import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

struct ReviewCommentAnchorProjectionTests {
    @Test("Review Comment anchors group a current line range and ignore stale or nonresearcher turns")
    func groupsOnlyCurrentResearcherComments() throws {
        let noteID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let discussionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let earlierID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let latestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let fingerprint = DocumentFingerprint(content: "current Note")
        let staleFingerprint = DocumentFingerprint(content: "earlier Note")
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let statements = [
            try statement(
                id: earlierID,
                author: .researcher,
                line: 4,
                endLine: 6,
                fingerprint: fingerprint,
                date: start
            ),
            try statement(
                id: latestID,
                author: .researcher,
                line: 4,
                endLine: 6,
                fingerprint: fingerprint,
                date: start.addingTimeInterval(1)
            ),
            try statement(
                author: .researcher,
                line: 4,
                endLine: 6,
                fingerprint: staleFingerprint,
                date: start.addingTimeInterval(2)
            ),
            try statement(
                author: .agent,
                line: 4,
                endLine: 6,
                fingerprint: fingerprint,
                date: start.addingTimeInterval(3)
            ),
        ]
        let discussion = try PortableResearchDiscussion(
            id: discussionID,
            triptychID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            primaryNoteID: noteID,
            participatingNotes: [try noteRevision(noteID: noteID, fingerprint: fingerprint)],
            statements: statements,
            createdAt: start,
            updatedAt: start.addingTimeInterval(3)
        )

        let anchors = ReviewCommentAnchorProjection.anchors(
            for: noteID,
            fingerprint: fingerprint,
            in: [discussion]
        )

        let anchor = try #require(anchors.first)
        #expect(anchors.count == 1)
        #expect(anchor.discussionID == discussionID)
        #expect(anchor.statementID == latestID)
        #expect(anchor.startLine == 4)
        #expect(anchor.endLine == 6)
        #expect(anchor.commentCount == 2)
    }

    @Test("Review Comment anchors remain scoped to the primary Note")
    func scopesAnchorsToPrimaryNote() throws {
        let noteID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let otherNoteID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let fingerprint = DocumentFingerprint(content: "current Note")
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let discussion = try PortableResearchDiscussion(
            triptychID: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            primaryNoteID: otherNoteID,
            participatingNotes: [
                try noteRevision(noteID: otherNoteID, fingerprint: fingerprint),
            ],
            statements: [
                try statement(
                    author: .researcher,
                    line: 2,
                    endLine: 2,
                    fingerprint: fingerprint,
                    date: start
                ),
            ],
            createdAt: start,
            updatedAt: start
        )

        #expect(
            ReviewCommentAnchorProjection.anchors(
                for: noteID,
                fingerprint: fingerprint,
                in: [discussion]
            ).isEmpty
        )
    }

    private func statement(
        id: UUID = UUID(),
        author: PortableResearchStatementAuthor,
        line: Int,
        endLine: Int,
        fingerprint: DocumentFingerprint,
        date: Date
    ) throws -> PortableResearchStatement {
        try PortableResearchStatement(
            id: id,
            author: author,
            kind: .discussionTurn,
            attribution: author == .researcher ? "Researcher" : "Agent",
            text: "A bounded Comment.",
            createdAt: date,
            lineReference: try ResearchLineReference(
                fingerprint: fingerprint,
                line: line,
                endLine: endLine,
                commentedText: "A bounded selection."
            )
        )
    }

    private func noteRevision(
        noteID: UUID,
        fingerprint: DocumentFingerprint
    ) throws -> PortableResearchNoteRevision {
        try PortableResearchNoteRevision(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                relativePath: "Notes/Commented.md"
            ),
            role: .topic,
            title: "Commented Note",
            startingRevision: fingerprint,
            endingRevision: fingerprint
        )
    }
}
