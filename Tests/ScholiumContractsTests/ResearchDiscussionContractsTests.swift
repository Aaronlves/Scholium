import Foundation
import ScholiumContracts
import Testing

@Suite("Portable Discussion contracts")
struct ResearchDiscussionContractsTests {
    @Test("One Discussion carries passage, whole-note, and focal-note context")
    func multiNoteDiscussionRoundTrip() throws {
        let fixture = try makeDiscussion()
        let data = try JSONEncoder.scholium.encode(fixture.discussion)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schema_version", "id", "triptych_id", "primary_note_id",
            "participating_notes", "statements", "created_at", "updated_at",
        ])
        #expect(fixture.discussion.participatingNotes.count == 2)
        #expect(fixture.discussion.primaryNoteID == fixture.primary.noteID)
        #expect(fixture.discussion.passage?.quotation == "bounded claim")
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchDiscussion.self,
            from: data
        ) == fixture.discussion)

        var unknown = object
        unknown["approval_state"] = "approved"
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchDiscussion.self,
                from: JSONSerialization.data(withJSONObject: unknown)
            )
        }
    }

    @Test("Finish creates one neutral Research Record without changing the exchange")
    func finishIsNeutralRecordTransition() throws {
        let fixture = try makeDiscussion()
        let agent = try PortableResearchStatement(
            author: .agent,
            kind: .agentFeedback,
            attribution: "Research Agent",
            text: "I could not establish the stronger conclusion.",
            createdAt: Date(timeIntervalSince1970: 12)
        )
        let discussion = try fixture.discussion.appending(
            agent,
            at: Date(timeIntervalSince1970: 12)
        )
        let ending = DocumentFingerprint(content: "topic revised")
        let finishedPrimary = try PortableResearchNoteRevision(
            noteID: fixture.primary.noteID,
            note: fixture.primary.note,
            role: fixture.primary.role,
            title: fixture.primary.title,
            startingRevision: fixture.primary.startingRevision,
            endingRevision: ending
        )
        let record = try discussion.finishedRecord(
            participatingNotes: [finishedPrimary, fixture.focal],
            finishedAt: Date(timeIntervalSince1970: 20)
        )

        #expect(record.kind == .discussion)
        #expect(record.primaryNoteID == fixture.primary.noteID)
        #expect(record.statements == discussion.statements)
        #expect(record.confirmedChanges.isEmpty)
        #expect(record.discrepancies.isEmpty)
        #expect(record.participatingNotes.first {
            $0.noteID == fixture.primary.noteID
        }?.endingRevision == ending)
        let encoded = String(decoding: try JSONEncoder.scholium.encode(record), as: UTF8.self)
        #expect(encoded.contains("\"primary_note_id\""))
        for verdict in ["approved", "rejected", "successful", "failed"] {
            #expect(!encoded.contains("\"\(verdict)\""))
        }
    }

    private func makeDiscussion() throws -> (
        discussion: PortableResearchDiscussion,
        primary: PortableResearchNoteRevision,
        focal: PortableResearchNoteRevision
    ) {
        let primaryID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let focalID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let vaultID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let primaryRevision = DocumentFingerprint(content: "bounded claim")
        let focalRevision = DocumentFingerprint(content: "analysis")
        let primary = try PortableResearchNoteRevision(
            noteID: primaryID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Topic.md"),
            role: .topic,
            title: "Topic",
            startingRevision: primaryRevision,
            endingRevision: primaryRevision
        )
        let focal = try PortableResearchNoteRevision(
            noteID: focalID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Analysis.md"),
            role: .analysis,
            title: "Analysis",
            startingRevision: focalRevision,
            endingRevision: focalRevision
        )
        let passage = CommentAnchor(
            fingerprint: primaryRevision,
            utf8Range: 0..<13,
            utf16Range: 0..<13,
            line: 1,
            endLine: 1,
            quotation: "bounded claim"
        )
        let statement = try PortableResearchStatement(
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: "Does this claim survive the objection?",
            createdAt: Date(timeIntervalSince1970: 10),
            passage: passage
        )
        return (
            try PortableResearchDiscussion(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                triptychID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                primaryNoteID: primaryID,
                participatingNotes: [primary, focal],
                statements: [statement],
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            ),
            primary,
            focal
        )
    }
}

private extension JSONEncoder {
    static var scholium: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
