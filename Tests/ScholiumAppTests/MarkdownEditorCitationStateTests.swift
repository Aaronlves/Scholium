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
            .initialize(text: source, mode: .source, dialect: .current, initialSelection: nil, citationSnapshot: base, presentation: .init()),
            .acknowledgeCommittedSnapshot(
                expected: source, committed: source, fingerprint: DocumentFingerprint(content: source).sha256,
                expectedCitationData: updated.data, committedCitationSnapshot: updated
            ),
        ]
        #expect(markdownEditorProtocolVersion == 51)
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
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.first?.code == base.data?.fields.first?.code)
        var changes = 0
        session.installSourceChangeHandler(owner: session) { changes += 1 }
        defer { session.removeSourceChangeHandler(owner: session) }

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
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.first?.code == updated.fields.first?.code)
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
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.first?.code == updated.fields.first?.code)
        #expect(session.generation == 1)
        #expect(changes == 1)
    }

    @Test("Undo-shaped companion removal remains managed and keeps its deletion preimage")
    @MainActor
    func nilAfterStateRetainsManagedContext() {
        let session = MarkdownEditorSession()
        let base = snapshot()
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.count == 1)
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
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.isEmpty == true)
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
        #expect(session.citationFields(forDocumentID: session.documentID)?.fields.first?.code == base.data?.fields.first?.code)
    }

    @Test("Rejected source deltas cannot publish companion changes and current source retains its own binding")
    @MainActor
    func sourceAndMetadataAdmission() throws {
        let session = MarkdownEditorSession()
        let base = snapshot()
        session.loadDocument(source, documentID: "synthetic-citation-note", mode: .source, citationSnapshot: base)
        let originalFields = try #require(session.citationFields(forDocumentID: session.documentID))
        let originalStart = try #require(originalFields.fields.first?.span.utf16LowerBound)
        #expect(
            !session.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "é", exactInsert: "e\u{301}")],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: data(locator: "99")
            ))
        #expect(!session.isDirty)
        #expect(session.checkedCitationData == base.data)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(session.citationFields(forDocumentID: session.documentID) == originalFields)

        #expect(
            session.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "Prefix\n", exactInsert: "Prefix\r\n")],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: base.data
            ))
        #expect(Data(session.checkedSource.utf8) == Data(("Prefix\r\n" + source).utf8))
        #expect(session.currentCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: session.checkedSource))
        #expect(session.committedCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: source))
        #expect(session.currentCitationSnapshot?.revision == base.revision)
        let shiftedFields = try #require(session.citationFields(forDocumentID: session.documentID))
        #expect(shiftedFields.fingerprint == DocumentFingerprint(content: "Prefix\r\n" + source))
        #expect(shiftedFields.fields.first?.span.utf16LowerBound == originalStart + "Prefix\r\n".utf16.count)
        #expect(
            shiftedFields
                == ZoteroMarkdownFields(
                    parsing: NoteDocument(
                        relativePath: session.documentID, rawContent: session.checkedSource, citationSnapshot: session.currentCitationSnapshot)))
    }

    @Test("First attachment consumes admitted source once while updating mode and exact companion bytes")
    @MainActor
    func firstAttachmentReusesPendingSource() throws {
        let original = data()
        let composed = ZoteroCitationData(
            fields: original.fields, documentData: "<data>é</data>", acceptedFields: original.acceptedFields)
        let decomposed = ZoteroCitationData(
            fields: original.fields, documentData: "<data>e\u{301}</data>", acceptedFields: original.acceptedFields)
        let baseline = snapshot(data: composed)
        let replacement = snapshot(data: decomposed)
        #expect(baseline == replacement)
        #expect(Data(composed.documentData!.utf8) != Data(decomposed.documentData!.utf8))
        let session = MarkdownEditorSession()
        let identity = session.bridgeDocumentID
        session.loadDocument(source, documentID: identity, mode: .livePreview, citationSnapshot: baseline)
        let first = try #require(session.citationFields(forDocumentID: identity)?.documentState?.data)
        #expect(Data(first.utf8) == Data(composed.documentData!.utf8))
        session.setScrollPosition(anchor: nil, fallbackFraction: 0.37)
        session.authorizeAutomaticFocus(target: .title)
        let focusRevision = session.focusRequestRevision
        #expect(session.canAttemptPreview)

        session.prepareForViewAttachment(source, documentID: identity, mode: .source, citationSnapshot: replacement)

        #expect(session.startingFingerprint == DocumentFingerprint(content: source).sha256)
        #expect(session.documentID == identity)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(!session.canAttemptPreview)
        #expect(session.retainedScrollFraction(fallback: 0) == 0.37)
        #expect(session.preferredDocumentFocusTarget == .title)
        #expect(session.focusRequestRevision == focusRevision)
        #expect(session.generation == 0 && !session.isDirty)
        #expect(!session.isReady && !session.isLoaded && !session.hasAttachedWebView)
        let changed = try #require(session.citationFields(forDocumentID: identity)?.documentState?.data)
        #expect(Data(changed.utf8) == Data(decomposed.documentData!.utf8))
        #expect(Data(try #require(session.committedCitationSnapshot?.data?.documentData).utf8) == Data(decomposed.documentData!.utf8))
        #expect(Data(try #require(session.checkedCitationData?.documentData).utf8) == Data(decomposed.documentData!.utf8))
    }

    @Test("A foreign identity or canonically equal different source requires a complete attachment load")
    @MainActor
    func attachmentAdmissionRejectsDifferentIdentityAndBytes() throws {
        let session = MarkdownEditorSession()
        session.loadDocument(source, documentID: session.bridgeDocumentID, mode: .livePreview, citationSnapshot: snapshot())
        let foreignIdentity = UUID().uuidString

        session.prepareForViewAttachment(source, documentID: foreignIdentity, mode: .source, citationSnapshot: snapshot())

        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(session.documentID == foreignIdentity)
        #expect(session.citationFields(forDocumentID: session.bridgeDocumentID) == nil)
        let replacementSource = source.replacingOccurrences(of: "e\u{301}", with: "é")
        #expect(replacementSource == source)
        #expect(Data(replacementSource.utf8) != Data(source.utf8))
        let replacementSnapshot = ZoteroCitationSnapshot(
            noteID: noteID, vaultID: vaultID, revision: DocumentFingerprint(content: "Replacement companion preimage"),
            sourceFingerprint: DocumentFingerprint(content: replacementSource), data: data(locator: "99"), status: .available)

        session.prepareForViewAttachment(replacementSource, documentID: foreignIdentity, mode: .livePreview, citationSnapshot: replacementSnapshot)

        #expect(Data(session.checkedSource.utf8) == Data(replacementSource.utf8))
        #expect(session.startingFingerprint == DocumentFingerprint(content: replacementSource).sha256)
        #expect(session.currentCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: replacementSource))
        #expect(session.checkedCitationData == replacementSnapshot.data)
        #expect(session.canAttemptPreview)
        #expect(session.generation == 0 && !session.isDirty)
        #expect(!session.isReady && !session.isLoaded && !session.hasAttachedWebView)
    }

    @Test("Citation catalogs preserve opaque companion bytes even when Unicode values compare equal")
    @MainActor
    func citationCatalogPreservesOpaqueCompanionBytes() throws {
        let original = data()
        let composed = ZoteroCitationData(
            fields: original.fields, documentData: "<data>é</data>", acceptedFields: original.acceptedFields)
        let decomposed = ZoteroCitationData(
            fields: original.fields, documentData: "<data>e\u{301}</data>", acceptedFields: original.acceptedFields)
        #expect(composed == decomposed)
        #expect(Data(composed.documentData!.utf8) != Data(decomposed.documentData!.utf8))
        let session = MarkdownEditorSession()
        let identity = session.bridgeDocumentID
        let baseline = snapshot(data: composed)
        session.loadDocument(source, documentID: identity, mode: .source, citationSnapshot: baseline)
        let first = try #require(session.citationFields(forDocumentID: identity)?.documentState?.data)
        #expect(Data(first.utf8) == Data(composed.documentData!.utf8))

        #expect(session.acceptEditorChanges([], baseGeneration: 0, resultingGeneration: 1, citationManaged: true, citationData: decomposed))
        let changed = try #require(session.citationFields(forDocumentID: identity)?.documentState?.data)
        #expect(Data(changed.utf8) == Data(decomposed.documentData!.utf8))
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        #expect(session.committedCitationSnapshot == baseline)

        // Reload resets generation while keeping identical source and a
        // canonically equal pair; the newly supplied opaque bytes still win.
        session.loadDocument(source, documentID: identity, mode: .source, citationSnapshot: baseline)
        let reloaded = try #require(session.citationFields(forDocumentID: identity)?.documentState?.data)
        #expect(Data(reloaded.utf8) == Data(composed.documentData!.utf8))
        #expect(session.generation == 0)
    }

    @Test(
        "Citation catalog identity, companion status and detached reset follow the exact source owner",
        arguments: [ZoteroCitationSnapshot.Status.absent, .available, .unresolved, .unsupported])
    @MainActor
    func citationCatalogFollowsLoadAndReset(_ status: ZoteroCitationSnapshot.Status) throws {
        let session = MarkdownEditorSession()
        let identity = session.bridgeDocumentID
        #expect(session.citationFields(forDocumentID: identity) == nil)
        session.loadDocument(source, documentID: identity, mode: .source, citationSnapshot: snapshot())
        #expect(session.citationFields(forDocumentID: identity)?.diagnostics.isEmpty == true)
        let next = status == .available ? snapshot(data: data(locator: "99")) : ZoteroCitationSnapshot(noteID: noteID, vaultID: vaultID, status: status)
        session.loadDocument(source, documentID: identity, mode: .source, citationSnapshot: next)
        let fields = try #require(session.citationFields(forDocumentID: identity))
        #expect(
            fields == ZoteroMarkdownFields(parsing: NoteDocument(relativePath: identity, rawContent: source, citationSnapshot: session.currentCitationSnapshot))
        )
        #expect(session.generation == 0)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))

        let replacementIdentity = UUID().uuidString
        let ordinary = "\u{FEFF}No citation 😀 e\u{301}\r\n"
        session.loadDocument(ordinary, documentID: replacementIdentity, mode: .source)
        #expect(session.citationFields(forDocumentID: identity) == nil)
        let empty = try #require(session.citationFields(forDocumentID: replacementIdentity))
        #expect(empty.fields.isEmpty && empty.diagnostics.isEmpty)
        #expect(empty.fingerprint == DocumentFingerprint(content: ordinary))
        session.shutdownDetachedSession()
        let reset = try #require(session.citationFields(forDocumentID: replacementIdentity))
        #expect(reset.fields.isEmpty && reset.diagnostics.isEmpty && reset.fingerprint == DocumentFingerprint(content: ""))
        session.loadDocument(source, documentID: identity, mode: .source, citationSnapshot: snapshot())
        #expect(session.citationFields(forDocumentID: identity)?.fields.first?.code == data().fields.first?.code)
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
