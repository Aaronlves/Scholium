import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Markdown editor citation state")
struct MarkdownEditorCitationStateTests {
    private let source = "\u{FEFF}# 引文 😀 e\u{301}\r\n\r\n[(Author, 2020)](cite:cfixture)\r\n"
    private let noteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let vaultID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

    private func data(locator: String = "12") -> ZoteroCitationData {
        let code = "ITEM CSL_CITATION {\"citationID\":\"vendor-id\",\"citationItems\":[{\"id\":1,\"locator\":\"\(locator)\"}]}"
        return ZoteroCitationData(
            fields: [.init(id: "cfixture", kind: .citation, code: code, text: "(Author, 2020)")],
            documentData: "<data data-version=\"4\"><prefs/></data>",
            acceptedFields: [.init(id: "cfixture", code: code)]
        )
    }

    private func snapshot(
        data: ZoteroCitationData? = nil, revision: String = "exact companion preimage"
    ) -> ZoteroCitationSnapshot {
        ZoteroCitationSnapshot(
            noteID: noteID, vaultID: vaultID,
            revision: DocumentFingerprint(content: revision),
            sourceFingerprint: DocumentFingerprint(content: source),
            data: data ?? self.data(), status: .available
        )
    }

    private func metadataMessage(data: ZoteroCitationData?) throws -> [String: Any] {
        var object: [String: Any] = [
            "type": "documentChanged", "protocolVersion": markdownEditorProtocolVersion,
            "sessionID": UUID().uuidString, "documentID": "synthetic-citation-note",
            "startingFingerprint": DocumentFingerprint(content: source).sha256,
            "documentVersion": 1, "baseGeneration": 0, "resultingGeneration": 1,
            "changes": [], "citationManaged": true,
        ]
        if let data {
            object["citationData"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data))
        }
        return object
    }

    @Test("Managed initialization and commit acknowledgement round-trip independent source and companion revisions")
    func managedProtocolRoundTrip() throws {
        let base = snapshot()
        let updated = snapshot(data: data(locator: "13"), revision: "updated companion bytes")
        let operations: [MarkdownEditorOperation] = [
            .initialize(text: source, mode: .source, dialect: .current, initialSelection: nil, citationSnapshot: base),
            .acknowledgeCommittedSnapshot(
                expected: source, committed: source, fingerprint: DocumentFingerprint(content: source).sha256,
                expectedCitationData: updated.data, committedCitationSnapshot: updated
            ),
        ]
        #expect(markdownEditorProtocolVersion == 46)
        for operation in operations {
            let encoded = try JSONEncoder().encode(operation)
            #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: encoded) == operation)
        }
        #expect(base.sourceFingerprint != base.revision)
        #expect(base.data != updated.data)
        #expect(base.revision != updated.revision)
        #expect(base.sourceFingerprint == updated.sourceFingerprint)
    }

    @Test("Recovery and paired acknowledgement retain managed identity when Undo restores companion absence")
    func absentManagedCompanionWireRoundTrip() throws {
        let latestBaseline = snapshot(data: data(locator: "13"), revision: "latest committed companion bytes")
        let restoredSource = "# Restored plain Markdown\r\n"
        let absent = ZoteroCitationSnapshot(
            noteID: noteID, vaultID: vaultID,
            sourceFingerprint: DocumentFingerprint(content: restoredSource), status: .absent
        )
        let recovery = MarkdownEditorRecoverySnapshot(
            documentID: "synthetic-citation-note", fingerprint: DocumentFingerprint(content: source).sha256,
            generation: 2, ranges: [.init(anchor: 0, head: 0)], source: restoredSource,
            stateJSON: nil, undoHistoryPreserved: false, dirty: true, focusTarget: .editor,
            citationSnapshot: latestBaseline, citationData: nil
        )
        let restored = try JSONDecoder().decode(
            MarkdownEditorRecoverySnapshot.self, from: JSONEncoder().encode(recovery)
        )
        #expect(restored == recovery)
        #expect(restored.citationSnapshot?.noteID == noteID)
        #expect(restored.citationSnapshot == latestBaseline)
        #expect(restored.citationSnapshot?.data != nil)
        #expect(restored.citationData == nil)
        #expect(restored.citationSnapshot?.sourceFingerprint != DocumentFingerprint(content: restored.source))
        let acknowledgement = MarkdownEditorOperation.acknowledgeCommittedSnapshot(
            expected: restoredSource, committed: restoredSource,
            fingerprint: DocumentFingerprint(content: restoredSource).sha256,
            expectedCitationData: nil, committedCitationSnapshot: absent
        )
        let encoded = try JSONEncoder().encode(acknowledgement)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: encoded) == acknowledgement)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["committedCitationSnapshot"] != nil)
        #expect(object["expectedCitationData"] == nil)
    }

    @Test("Metadata-only changes require an explicit managed context and valid bounded data")
    func metadataOnlyDecoding() throws {
        let original = try metadataMessage(data: data())
        guard case .documentChanged(let decoded) = try #require(EditorBridgeMessageDecoder.decode(original)) else {
            Issue.record("Expected a typed metadata-only change")
            return
        }
        #expect(decoded.changes.isEmpty)
        #expect(decoded.citationManaged == true)
        #expect(decoded.citationData == data())
        #expect(EditorBridgeMessageDecoder.decode(try metadataMessage(data: nil)) != nil)

        for value in [false, 1, "true", NSNull()] as [Any] {
            var invalid = original
            invalid["citationManaged"] = value
            #expect(EditorBridgeMessageDecoder.decode(invalid) == nil)
        }
        var missingContext = original
        missingContext.removeValue(forKey: "citationManaged")
        #expect(EditorBridgeMessageDecoder.decode(missingContext) == nil)
        var malformedData = original
        malformedData["citationData"] = ["schemaVersion": 1, "fields": "invalid"]
        #expect(EditorBridgeMessageDecoder.decode(malformedData) == nil)
        #expect(EditorBridgeMessageDecoder.decode(try metadataMessage(data: .init(schemaVersion: 2))) == nil)
        #expect(
            EditorBridgeMessageDecoder.decode(
                try metadataMessage(
                    data: .init(fields: [
                        .init(
                            id: "cfixture", kind: .citation,
                            code: String(repeating: "x", count: ZoteroCitationData.maximumFieldUTF16Count + 1), text: "label")
                    ]))) == nil)
    }

    @Test("Valid companion data above the ordinary interaction envelope remains admissible")
    func boundedLargeMetadataChange() throws {
        let code = String(repeating: "x", count: 220_000)
        let largeData = ZoteroCitationData(
            fields: (0..<12).map {
                .init(id: "cfixture\($0)", kind: .citation, code: code, text: "Readable citation")
            })
        let encoded = try JSONEncoder().encode(largeData)
        #expect(encoded.count > markdownEditorMaximumInboundBytes)
        #expect(encoded.count < ZoteroCitationData.maximumEncodedByteCount)
        let message = try metadataMessage(data: largeData)
        guard
            case .documentChanged(let decoded) = try #require(
                EditorBridgeMessageDecoder.decode(message)
            )
        else {
            Issue.record("Valid bounded companion data was rejected by the interaction-message limit")
            return
        }
        #expect(decoded.citationData == largeData)
    }

    @Test("Metadata-only generations dirty the session and retain the companion save preimage")
    @MainActor
    func metadataOnlySessionGeneration() {
        let session = MarkdownEditorSession()
        let base = snapshot()
        let updated = data(locator: "13")
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        var changes = 0
        session.installSourceChangeHandler { changes += 1 }
        defer { session.removeSourceChangeHandler() }

        #expect(
            session.acceptEditorChanges(
                [], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: updated
            ))
        #expect(session.generation == 1)
        #expect(session.isDirty)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(session.checkedCitationData == updated)
        #expect(session.currentCitationSnapshot?.data == updated)
        #expect(session.committedCitationSnapshot == base)
        #expect(session.currentCitationSnapshot?.revision == base.revision)
        #expect(changes == 1)

        #expect(
            !session.acceptEditorChanges(
                [], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: base.data
            ))
        #expect(
            !session.acceptEditorChanges(
                [], baseGeneration: 1, resultingGeneration: 3, citationManaged: true, citationData: base.data
            ))
        #expect(session.checkedCitationData == updated)
        #expect(session.generation == 1)
        #expect(changes == 1)
    }

    @Test("Undo-shaped companion removal remains managed and keeps its deletion preimage")
    @MainActor
    func nilAfterStateRetainsManagedContext() {
        let session = MarkdownEditorSession()
        let base = snapshot()
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        let beforeCitation = "# Before citation\r\n"
        #expect(
            session.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: source.replacingOccurrences(of: "\r\n", with: "\n").utf16.count,
                        insert: beforeCitation.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: beforeCitation)
                ],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: nil
            ))
        #expect(Data(session.checkedSource.utf8) == Data(beforeCitation.utf8))
        #expect(session.checkedCitationData == nil)
        #expect(session.currentCitationSnapshot != nil)
        #expect(session.currentCitationSnapshot?.noteID == noteID)
        #expect(session.currentCitationSnapshot?.revision == nil)
        #expect(session.currentCitationSnapshot?.status == .absent)
        #expect(session.committedCitationSnapshot?.revision == base.revision)
        #expect(session.committedCitationSnapshot == base)
        #expect(session.isDirty)
        #expect(
            session.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: beforeCitation.replacingOccurrences(of: "\r\n", with: "\n").utf16.count,
                        insert: source.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: source)
                ],
                baseGeneration: 1, resultingGeneration: 2, citationManaged: true, citationData: base.data
            ))
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(session.checkedCitationData == base.data)
        #expect(session.committedCitationSnapshot == base)
    }

    @Test("Rejected source deltas cannot publish companion changes and current source retains its own binding")
    @MainActor
    func sourceAndMetadataAdmission() {
        let session = MarkdownEditorSession()
        let base = snapshot()
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        #expect(
            !session.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "é", exactInsert: "e\u{301}")],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: data(locator: "99")
            ))
        #expect(!session.isDirty)
        #expect(session.checkedCitationData == base.data)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))

        #expect(
            session.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "Prefix\n", exactInsert: "Prefix\r\n")],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: base.data
            ))
        #expect(Data(session.checkedSource.utf8) == Data(("Prefix\r\n" + source).utf8))
        #expect(session.currentCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: session.checkedSource))
        #expect(session.committedCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: source))
        #expect(session.currentCitationSnapshot?.revision == base.revision)
    }

    @Test("Standalone source refuses managed metadata and ordinary edits stay standalone")
    @MainActor
    func standaloneCannotAcquireManagedAuthority() {
        let session = MarkdownEditorSession()
        session.loadDocument(source, documentID: "standalone-fixture", mode: .source)
        #expect(
            !session.acceptEditorChanges(
                [], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: data()
            ))
        #expect(session.generation == 0)
        #expect(!session.isDirty)
        #expect(
            session.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "Text ", exactInsert: "Text ")],
                baseGeneration: 0, resultingGeneration: 1
            ))
        #expect(session.currentCitationSnapshot == nil)
        #expect(session.checkedCitationData == nil)
        #expect(Data(session.checkedSource.utf8) == Data(("Text " + source).utf8))
    }

    @Test("A checked mirror without frozen renderer capture cannot acknowledge a paired detached commit")
    @MainActor
    func detachedAcknowledgementRequiresCapture() async {
        let session = MarkdownEditorSession()
        let base = snapshot()
        let updated = data(locator: "13")
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        #expect(
            session.acceptEditorChanges(
                [], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: updated
            ))
        let persistence = MarkdownEditorPersistenceSnapshot(
            text: source, generation: 1, documentID: session.documentID,
            fingerprint: session.startingFingerprint, suspensionID: "unproven-suspension",
            citationData: updated, companionRevision: base.revision
        )
        do {
            _ = try await session.acknowledgePersistenceSnapshot(
                persistence, committedText: source, fingerprint: DocumentFingerprint(content: source),
                citationSnapshot: snapshot(data: updated)
            )
            Issue.record("An unfrozen detached mirror acknowledged a paired commit")
        } catch MarkdownEditorSession.SessionError.invalidResult {
            // Only a retained atomic renderer suspension can authorize this path.
        } catch {
            Issue.record("Unexpected refusal: \(error)")
        }
        #expect(session.isDirty)
        #expect(session.committedCitationSnapshot == base)
        #expect(session.checkedCitationData == updated)
        #expect(!session.hasDetachedPersistenceSnapshot)
    }
}
