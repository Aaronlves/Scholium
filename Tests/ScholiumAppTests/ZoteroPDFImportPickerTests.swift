import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Zotero PDF picker request lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct ZoteroPDFImportPickerTests {
    @Test("A delayed search cannot replace a newer completed query")
    func delayedSearch() async throws {
        let gate = DeferredPDFPickerValue<[ZoteroSearchHit]>()
        let oldHit = hit("OLD00001")
        let newHit = hit("NEW00001")
        let model = model(search: { query in query == "old" ? await gate.value() : [newHit] })
        model.query = "old"
        model.search()
        let old = try #require(model.operationForTesting)
        await gate.waitForRequest()
        model.query = "new"
        model.search()
        await model.operationForTesting?.value
        #expect(model.hits == [newHit])
        await gate.release([oldHit])
        await old.value
        #expect(model.hits == [newHit])
        #expect(model.phase == nil)
        #expect(model.error == nil)
    }

    @Test("Changing selected item rejects an earlier attachment completion")
    func delayedAttachments() async throws {
        let gate = DeferredPDFPickerValue<[ZoteroPDFImportOption]>()
        let first = hit("OLD00001")
        let second = hit("NEW00001")
        let oldSource = try source(first, key: "OLDPDF01")
        let newSource = try source(second, key: "NEWPDF01")
        let model = model(
            search: { _ in [first, second] },
            attachments: { hit in
                hit.id == first.id ? await gate.value() : [.verifiedSource(newSource)]
            })
        model.query = "fixture"
        model.search()
        await model.operationForTesting?.value
        model.selectItem(first.id)
        let old = try #require(model.operationForTesting)
        await gate.waitForRequest()
        model.selectItem(second.id)
        await model.operationForTesting?.value
        await gate.release([.verifiedSource(oldSource)])
        await old.value
        #expect(model.selectedHitID == second.id)
        #expect(model.sources == [.verifiedSource(newSource)])
        #expect(model.selectedSource == .verifiedSource(newSource))
        #expect(model.phase == nil)
    }

    @Test("Sheet cancellation clears a local-file preview and rejects its late resolution")
    func cancelledImportResolution() async throws {
        let gate = DeferredPDFPickerValue<ZoteroPDFLocalCopyCandidate>()
        let hit = hit("PARENT01")
        let observation = try observation(hit, key: "PDF00001")
        var imported = false
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.localCopy(observation)] },
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in imported = true },
            resolveLocalCopy: { _ in await gate.value() }, importLocalCopy: { _ in imported = true })
        model.query = "fixture"
        model.search()
        await model.operationForTesting?.value
        model.selectItem(hit.id)
        await gate.waitForRequest()
        let old = try #require(model.operationForTesting)
        #expect(model.cancel())
        await gate.release(ZoteroPDFLocalCopyCandidate(observation: observation, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf")))
        await old.value
        #expect(!imported)
        #expect(!model.completed)
        #expect(model.phase == nil)
        #expect(model.error == nil)
        #expect(model.localCopyCandidate == nil && !model.localCopyAcknowledged)
    }

    @Test("A successful import completes once and retains its selected provenance")
    func successfulImport() async throws {
        let hit = hit("PARENT01")
        let source = try source(hit, key: "PDF00001")
        let candidate = ZoteroPDFImportCandidate(source: source, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf"))
        var imported: [ZoteroPDFImportCandidate] = []
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.verifiedSource(source)] },
            resolve: { _ in candidate }, importPDF: { imported.append($0) },
            resolveLocalCopy: { _ in throw ZoteroPDFImportError.originalUnavailable }, importLocalCopy: { _ in })
        model.query = "fixture"
        model.search()
        await model.operationForTesting?.value
        model.selectItem(hit.id)
        await model.operationForTesting?.value
        model.importSelection()
        model.importSelection()
        await model.operationForTesting?.value
        #expect(imported == [candidate])
        #expect(model.completed)
        #expect(model.error == nil)
        model.importSelection()
        model.search()
        model.selectAttachment(nil)
        #expect(model.operationForTesting == nil && !model.canImport)
        #expect(imported == [candidate])
    }

    @Test("Local Copy requires acknowledgment of its resolved file and uses only its dedicated callback")
    func explicitLocalCopyConfirmation() async throws {
        let hit = hit("PARENT01")
        let observation = try observation(hit, key: "PDF00001")
        let candidate = ZoteroPDFLocalCopyCandidate(observation: observation, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf"))
        var strictImports = 0
        var localImports: [ZoteroPDFLocalCopyCandidate] = []
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.localCopy(observation)] },
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in strictImports += 1 },
            resolveLocalCopy: { _ in candidate }, importLocalCopy: { localImports.append($0) })
        model.query = "fixture"
        model.search()
        await settle(model)
        model.selectItem(hit.id)
        await settle(model)
        #expect(model.localCopyCandidate?.originalURL.path == "/fixture/Fixture.pdf")
        #expect(model.isLocalCopySelected && !model.canImport)
        model.importSelection()
        #expect(localImports.isEmpty && model.phase == nil)
        model.localCopyAcknowledged = true
        #expect(model.canImport)
        model.importSelection()
        await settle(model)
        #expect(localImports == [candidate] && strictImports == 0)
        #expect(model.completed)
    }

    @Test("Changing the local attachment clears the earlier file acknowledgment")
    func localCopySelectionInvalidatesConfirmation() async throws {
        let hit = hit("PARENT01")
        let first = try observation(hit, key: "PDF00001")
        let second = try observation(hit, key: "PDF00002")
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.localCopy(first), .localCopy(second)] },
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in },
            resolveLocalCopy: { ZoteroPDFLocalCopyCandidate(observation: $0, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf")) },
            importLocalCopy: { _ in })
        model.query = "fixture"
        model.search()
        await settle(model)
        model.selectItem(hit.id)
        await settle(model)
        model.selectAttachment(ZoteroPDFImportOption.localCopy(first).id)
        await settle(model)
        model.localCopyAcknowledged = true
        #expect(model.canImport)
        model.selectAttachment(ZoteroPDFImportOption.localCopy(second).id)
        #expect(model.localCopyCandidate == nil && !model.localCopyAcknowledged)
        await settle(model)
        #expect(model.localCopyCandidate?.observation == second && !model.canImport)
    }

    @Test("Final local-copy commit cannot be canceled by a stale Cancel action")
    func localCopyCommitBoundary() async throws {
        let hit = hit("PARENT01")
        let observation = try observation(hit, key: "PDF00001")
        let candidate = ZoteroPDFLocalCopyCandidate(observation: observation, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf"))
        let gate = DeferredPDFPickerValue<Bool>()
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.localCopy(observation)] },
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in },
            resolveLocalCopy: { _ in candidate }, importLocalCopy: { _ in _ = await gate.value() })
        model.query = "fixture"
        model.search()
        await settle(model)
        model.selectItem(hit.id)
        await settle(model)
        model.localCopyAcknowledged = true
        model.importSelection()
        await gate.waitForRequest()
        #expect(!model.cancel())
        #expect(model.phase == .importing && model.localCopyCandidate == candidate)
        await gate.release(true)
        await settle(model)
        #expect(model.completed)
    }

    @Test("Failed local-copy revalidation clears confirmation and requires a fresh file lookup")
    func localCopyFailureInvalidatesConfirmation() async throws {
        let hit = hit("PARENT01")
        let observation = try observation(hit, key: "PDF00001")
        let candidate = ZoteroPDFLocalCopyCandidate(observation: observation, originalURL: URL(fileURLWithPath: "/fixture/Fixture.pdf"))
        let model = ZoteroPDFImportPickerModel(
            search: { _ in [hit] }, attachments: { _ in [.localCopy(observation)] },
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in },
            resolveLocalCopy: { _ in candidate }, importLocalCopy: { _ in throw ZoteroPDFImportError.sourceChanged })
        model.query = "fixture"
        model.search()
        await settle(model)
        model.selectItem(hit.id)
        await settle(model)
        model.localCopyAcknowledged = true
        model.importSelection()
        await settle(model)
        #expect(model.localCopyCandidate == nil && !model.localCopyAcknowledged && !model.canImport)
        #expect(model.error != nil && model.canRetryLocalCopy)
        model.retryLocalCopy()
        await settle(model)
        #expect(model.localCopyCandidate == candidate && !model.canImport)
    }

    @Test("Presentation teardown rejects subsequent stale actions")
    func terminalPresentation() async throws {
        let hit = hit("PARENT01")
        let model = model(search: { _ in [hit] })
        model.query = "fixture"
        model.invalidatePresentation()
        model.search()
        model.selectItem(hit.id)
        model.selectAttachment("stale")
        model.importSelection()
        #expect(model.operationForTesting == nil && model.selectedHitID == nil && !model.canImport)
    }

    @Test("Clearing an item selection keeps the picker available for another search")
    func itemDeselection() async throws {
        let hit = hit("PARENT01")
        let model = model(search: { _ in [hit] })
        model.query = "fixture"
        model.search()
        await settle(model)
        model.selectItem(hit.id)
        await settle(model)
        model.selectItem(nil)
        #expect(model.selectedHitID == nil && model.phase == nil)
        model.search()
        #expect(model.phase == .searching)
        await settle(model)
        #expect(model.hits == [hit])
    }

    private func model(
        search: @escaping ZoteroPDFImportPickerModel.Search,
        attachments: @escaping ZoteroPDFImportPickerModel.Attachments = { _ in [] }
    ) -> ZoteroPDFImportPickerModel {
        ZoteroPDFImportPickerModel(
            search: search, attachments: attachments,
            resolve: { _ in throw ZoteroPDFImportError.originalUnavailable }, importPDF: { _ in },
            resolveLocalCopy: { _ in throw ZoteroPDFImportError.originalUnavailable }, importLocalCopy: { _ in })
    }

    private func settle(_ model: ZoteroPDFImportPickerModel) async {
        while let operation = model.operationForTesting { await operation.value }
    }

    private func hit(_ key: String) -> ZoteroSearchHit {
        ZoteroSearchHit(
            library: ZoteroLibraryMetadata(identity: .user, name: "Fixture Library"),
            item: ZoteroItemMetadata(key: key, itemType: "book", title: key))
    }

    private func source(_ hit: ZoteroSearchHit, key: String) throws -> ZoteroPDFSource {
        try ZoteroPDFSource(
            library: hit.library, item: hit.item, attachmentKey: key, attachmentVersion: 1,
            title: "Fixture PDF", filename: "Fixture.pdf", linkMode: .importedFile, serverID: "FIXTURE-DATABASE",
            attachmentMetadataFingerprint: DocumentFingerprint(content: key))
    }

    private func observation(_ hit: ZoteroSearchHit, key: String) throws -> ZoteroPDFLocalCopyObservation {
        try ZoteroPDFLocalCopyObservation(
            library: hit.library, observedLibraryID: 0, item: hit.item,
            parentVersion: 0, parentMetadataFingerprint: DocumentFingerprint(content: "parent metadata"),
            attachmentKey: key, attachmentVersion: 0, attachmentMetadataFingerprint: DocumentFingerprint(content: key),
            title: "Fixture PDF", filename: "Fixture.pdf", linkMode: .importedFile)
    }
}

/// Deliberately ignores Task cancellation to prove generation admission alone
/// prevents stale publication. Every test explicitly releases the continuation.
private actor DeferredPDFPickerValue<Value: Sendable> {
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<Value, Never>?

    func value() async -> Value {
        requested = true
        requestWaiter?.resume()
        requestWaiter = nil
        return await withCheckedContinuation { result = $0 }
    }

    func waitForRequest() async {
        if requested { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func release(_ value: Value) {
        result?.resume(returning: value)
        result = nil
    }
}
