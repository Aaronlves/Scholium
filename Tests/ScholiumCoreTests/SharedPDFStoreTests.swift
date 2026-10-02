import Darwin
import Foundation
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Shared portable PDF persistence")
struct SharedPDFStoreTests {
    @Test("PDF recovery storage permits only its two UUID-scoped snapshots while JSON stores stay JSON-only")
    func recoveryFilePolicy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let json = SecureRecordDirectory(
            trustedRootURL: fixture.support, components: ["JSONPolicy"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 32)
        let recovery = SecureRecordDirectory(
            trustedRootURL: fixture.support, components: ["PDFPolicy"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 32, filePolicy: .pdfRecovery)
        let transaction = UUID().uuidString
        let bytes = Data("immutable bytes".utf8)
        #expect(try json.createExclusive(bytes, directory: nil, fileName: "record.json") == bytes)
        #expect(throws: SecureRecordDirectoryError.self) { try json.createExclusive(bytes, directory: transaction, fileName: "candidate.pdf") }
        #expect(try recovery.createExclusive(bytes, directory: transaction, fileName: "baseline.pdf") == bytes)
        #expect(try recovery.createExclusive(bytes, directory: transaction, fileName: "candidate.pdf") == bytes)
        #expect(try recovery.read(directory: transaction, fileName: "candidate.pdf") == bytes)
        #expect(throws: SecureRecordDirectoryError.self) { try recovery.createExclusive(bytes, directory: nil, fileName: "candidate.pdf") }
        #expect(throws: SecureRecordDirectoryError.self) { try recovery.createExclusive(bytes, directory: transaction, fileName: "arbitrary.pdf") }
        #expect(throws: SecureRecordDirectoryError.self) { try recovery.createExclusive(bytes, directory: "unowned", fileName: "candidate.pdf") }
        #expect(throws: SecureRecordDirectoryError.self) { try recovery.createExclusive(bytes, directory: transaction, fileName: "../candidate.pdf") }
        #expect(throws: SecureRecordDirectoryError.self) {
            try recovery.createExclusive(Data(repeating: 0, count: 33), directory: transaction, fileName: "candidate.pdf")
        }
        try recovery.remove(directory: transaction, fileName: "candidate.pdf", expected: bytes)
        #expect(try recovery.readIfPresent(directory: transaction, fileName: "candidate.pdf") == nil)
    }

    @Test("Concurrent imports publish one shared copy and canceled queued work publishes nothing")
    func concurrentImports() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        try Self.pdf("Concurrent source").write(to: fixture.source)
        let gate = ImportGate()
        let first = Task { try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) { await gate.wait() } }
        await gate.reached()
        let second = Task { try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) }
        let anotherSource = fixture.root.appendingPathComponent("Canceled.pdf")
        try Self.pdf("Canceled source").write(to: anotherSource)
        let canceled = Task { try await store.importPDF(at: anotherSource, zoteroSource: nil, allowNewVersion: false) }
        canceled.cancel()
        await gate.release()
        let results = try await (first.value, second.value)
        #expect(results.0.snapshot.record.id == results.1.snapshot.record.id)
        #expect(results.0.wasNew != results.1.wasNew)
        #expect(try await store.records().count == 1)
        await #expect(throws: CancellationError.self) { try await canceled.value }
        #expect(try await store.records().count == 1)
    }

    @Test("Shutdown drains delayed imports without publishing a late shared copy")
    func shutdownDuringImport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Delayed import")
        try original.write(to: fixture.source)
        let gate = ImportGate()
        let importing = Task { try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) { await gate.wait() } }
        await gate.reached()
        let queued = Task { try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) }
        let closingEvents = AsyncStream<Void>.makeStream()
        await store.setOnClosingForTesting { closingEvents.continuation.yield(()) }
        let closing = Task { await store.close() }
        var events = closingEvents.stream.makeAsyncIterator()
        _ = await events.next()
        await #expect(throws: PDFReaderError.unreadable) { try await store.records() }
        await gate.release()
        await #expect(throws: PDFReaderError.unreadable) { try await importing.value }
        await #expect(throws: PDFReaderError.unreadable) { try await queued.value }
        await closing.value
        closingEvents.continuation.finish()
        let reopened = try fixture.store()
        #expect(try await reopened.records().isEmpty)
        #expect(try Data(contentsOf: fixture.source) == original)
    }

    @Test("Imported source stays exact, annotations round-trip, and local reimport reuses the annotated copy")
    func sourcePreservationAndReimport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Source")
        try original.write(to: fixture.source)
        let imported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false)
        #expect(imported.wasNew)
        #expect(imported.snapshot.record.vaultID == nil)
        #expect(imported.snapshot.record.importedSourceFingerprint == DocumentFingerprint(data: original))
        let candidate = try Self.annotated(imported.snapshot.data, comment: "Research comment 中文")
        let saved = try await store.save(candidate: candidate, expected: imported.snapshot)
        #expect(try Data(contentsOf: fixture.source) == original)
        #expect(saved.data == candidate)
        #expect(saved.recoveryCandidates.isEmpty)
        #expect(saved.revision != imported.snapshot.revision)
        let comment = PDFDocument(data: saved.data)?.page(at: 0)?.annotations.first?.contents
        #expect(comment == "Research comment 中文")
        let reimported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false)
        #expect(!reimported.wasNew)
        #expect(reimported.snapshot.record.id == saved.record.id)
        #expect(reimported.snapshot.data == candidate)
        #expect(try await store.records().count == 1)
    }

    @Test("One shared copy resolves from Notes in all roles and rejects unregistered traversal")
    func sharedBindingAcrossRoles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        try Self.pdf("Bound").write(to: fixture.source)
        let imported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false)
        for folder in ["Analyses/Deep", "Topics", "Works/Deep/Nested"] {
            let noteURL = fixture.root.appendingPathComponent("\(folder)/Note.md")
            let path = try await store.authoredPath(attachmentID: imported.snapshot.record.id, noteURL: noteURL)
            let bound = try await store.resolve(noteURL: noteURL, authoredPath: path)
            #expect(bound.record.id == imported.snapshot.record.id)
        }
        await #expect(throws: PDFReaderError.invalidBinding) {
            try await store.resolve(noteURL: fixture.root.appendingPathComponent("Topics/Note.md"), authoredPath: "../../outside.pdf")
        }
        await #expect(throws: PDFReaderError.invalidBinding) {
            try await store.resolve(noteURL: fixture.root.appendingPathComponent("Topics/Note.md"), authoredPath: fixture.source.path)
        }
    }

    @Test("Literal YAML paths preserve spaces, Unicode, question marks, and hash marks in PDF filenames")
    func literalFilesystemBinding() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = fixture.root.appendingPathComponent("Why? #1 中文.pdf")
        try Self.pdf("Literal filename").write(to: source)
        let imported = try await store.importPDF(at: source, zoteroSource: nil, allowNewVersion: false).snapshot
        let note = fixture.root.appendingPathComponent("Topics/Nested/Note.md")
        let path = try await store.authoredPath(attachmentID: imported.record.id, noteURL: note)
        #expect(path.hasSuffix("/Why? #1 中文.pdf"))
        #expect(try await store.resolve(noteURL: note, authoredPath: path).record.id == imported.record.id)
        let recreated = try fixture.store()
        #expect(try await recreated.resolve(noteURL: note, authoredPath: path).data == imported.data)
    }

    @Test("A peer save and same-byte pathname replacement reject stale writers")
    func staleWritersAndReplacements() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        try Self.pdf("Source").write(to: fixture.source)
        let original = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        let first = try Self.annotated(original.data, comment: "First window")
        let second = try Self.annotated(original.data, comment: "Second window")
        let saved = try await store.save(candidate: first, expected: original)
        await #expect(throws: PDFReaderError.changed) { try await store.save(candidate: second, expected: original) }
        #expect(try await store.load(attachmentID: original.record.id).data == first)
        let file = try fixture.file(saved.record)
        try first.write(to: file, options: .atomic)
        await #expect(throws: PDFReaderError.changed) { try await store.save(candidate: second, expected: saved) }
        #expect(try Data(contentsOf: file) == first)
    }

    @Test("A same-byte external replacement in the final swap interval retains the external file's identity")
    func finalIntervalIdentityRace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Self.pdf("Exact identity")
        try original.write(to: fixture.source)
        let starting = try PDFReaderFileAccess.read(at: fixture.source)
        let candidate = try Self.annotated(original, comment: "Stale writer")
        let identity = ExactFileReplacementIdentity(
            device: starting.revision.device, inode: starting.revision.inode,
            parentDevice: starting.revision.parentDevice, parentInode: starting.revision.parentInode)
        do {
            _ = try ExactFileReplacement.replace(
                at: fixture.source, expected: original, candidate: candidate,
                preCommitHook: { try original.write(to: $0, options: .atomic) }, expectedIdentity: identity)
            Issue.record("A replaced file cannot retain the earlier physical save authority.")
        } catch ExactFileReplacementError.revisionConflict {}
        let current = try PDFReaderFileAccess.read(at: fixture.source)
        #expect(current.data == original)
        #expect(current.revision.inode != starting.revision.inode)
    }

    @Test("A deterministic precommit external edit is preserved and the candidate remains exportable after recreation")
    func interruptedSaveRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        try Self.pdf("Source").write(to: fixture.source)
        let original = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        let candidate = try Self.annotated(original.data, comment: "Unsaved candidate")
        let external = try Self.annotated(original.data, comment: "External participant")
        await store.setBeforeCommitForTesting { location in try external.write(to: location, options: .atomic) }
        await #expect(throws: PDFReaderError.changed) { try await store.save(candidate: candidate, expected: original) }
        #expect(try Data(contentsOf: fixture.file(original.record)) == external)
        let recreated = try fixture.store()
        let reopened = try await recreated.load(attachmentID: original.record.id)
        let recovery = try #require(reopened.recoveryCandidates.first)
        #expect(try await recreated.recoveryData(recovery) == candidate)
        #expect(recovery.expectedFingerprint == original.revision.fingerprint)
        let export = fixture.root.appendingPathComponent("Recovered.pdf")
        try SharedPDFStore.export(candidate: try await recreated.recoveryData(recovery), to: export)
        #expect(try Data(contentsOf: export) == candidate)
        #expect(try await recreated.load(attachmentID: original.record.id).data == external)
    }

    @Test("A conflict present before save and a missing copy both retain exact annotation candidates across relaunch")
    func preflightConflictRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        try Self.pdf("Preflight source").write(to: fixture.source)
        let original = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        let candidate = try Self.annotated(original.data, comment: "Preflight unsaved annotations")
        let external = try Self.annotated(original.data, comment: "Earlier external write")
        let file = try fixture.file(original.record)
        try external.write(to: file, options: .atomic)
        await #expect(throws: PDFReaderError.changed) { try await store.save(candidate: candidate, expected: original) }
        let recreated = try fixture.store()
        let pending = try await recreated.recoveries(attachmentID: original.record.id)
        #expect(pending.count == 1)
        #expect(try await recreated.recoveryData(try #require(pending.first)) == candidate)
        #expect(try Data(contentsOf: file) == external)
        try FileManager.default.removeItem(at: file)
        let nextCandidate = try Self.annotated(original.data, comment: "Copy disappeared before save")
        await #expect(throws: PDFReaderError.missing) { try await recreated.save(candidate: nextCandidate, expected: original) }
        let anotherLaunch = try fixture.store()
        let recoveries = try await anotherLaunch.recoveries(attachmentID: original.record.id)
        #expect(recoveries.count == 2)
        #expect(try await anotherLaunch.recoveryData(try #require(recoveries.last)) == nextCandidate)
    }

    @Test("An interrupted committed save reconciles exact candidate bytes on relaunch without another PDF write")
    func committedSaveRecoveryReconciliation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let originalBytes = Self.pdf("Committed source")
        try originalBytes.write(to: fixture.source)
        let original = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        let candidate = try Self.annotated(original.data, comment: "Committed before interruption")
        await store.setAfterCommitForTesting { _ in throw POSIXError(.EIO) }
        await #expect(throws: PDFReaderError.self) { try await store.save(candidate: candidate, expected: original) }
        let file = try fixture.file(original.record)
        let beforeRelaunch = try PDFReaderFileAccess.read(at: file)
        #expect(beforeRelaunch.data == candidate)
        #expect(try await store.recoveries(attachmentID: original.record.id).count == 1)
        let relaunched = try fixture.store()
        let opened = try await relaunched.load(attachmentID: original.record.id)
        #expect(opened.data == candidate)
        #expect(opened.recoveryCandidates.isEmpty)
        #expect(opened.revision == beforeRelaunch.revision)
        #expect(try Data(contentsOf: fixture.source) == originalBytes)
    }

    @Test("Zotero provenance deduplicates across source moves and imports changed originals only as explicit new versions")
    func zoteroProvenance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let source = try Self.zoteroSource()
        let bytes = Self.pdf("Original Zotero copy")
        try bytes.write(to: fixture.source)
        let original = try await store.importPDF(at: fixture.source, zoteroSource: source, allowNewVersion: false).snapshot
        let candidate = try Self.annotated(original.data, comment: "Kept annotation")
        _ = try await store.save(candidate: candidate, expected: original)
        let moved = fixture.root.appendingPathComponent("Moved original.pdf")
        try FileManager.default.moveItem(at: fixture.source, to: moved)
        let reused = try await store.importPDF(at: moved, zoteroSource: source, allowNewVersion: false)
        #expect(!reused.wasNew && reused.snapshot.record.id == original.record.id)
        #expect(reused.snapshot.data == candidate)
        #expect(reused.snapshot.record.zoteroSource?.pdfReference.url == source.pdfReference.url)
        let changed = Self.pdf("New Zotero version")
        try changed.write(to: moved)
        await #expect(throws: PDFReaderError.sourceChanged) { try await store.importPDF(at: moved, zoteroSource: source, allowNewVersion: false) }
        let version = try await store.importPDF(at: moved, zoteroSource: source, allowNewVersion: true)
        #expect(version.wasNew && version.snapshot.record.id != original.record.id)
        #expect(try await store.load(attachmentID: original.record.id).data == candidate)
        #expect(try Data(contentsOf: moved) == changed)
    }

    @Test("Explicit new-copy import repairs a missing copy without replacing its catalog entry")
    func explicitCopyForMissingManagedPDF() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Original to reattach")
        try original.write(to: fixture.source)
        let imported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        try FileManager.default.removeItem(at: fixture.file(imported.record))
        await #expect(throws: PDFReaderError.missing) { try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) }
        let replacement = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: true)
        #expect(replacement.wasNew && replacement.snapshot.record.id != imported.record.id)
        #expect(replacement.snapshot.data == original)
        let another = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: true)
        #expect(another.wasNew && another.snapshot.record.id != replacement.snapshot.record.id)
        #expect(try await store.load(attachmentID: replacement.snapshot.record.id).data == original)
        let records = try await store.records()
        #expect(records.count == 3)
        #expect(records.contains(imported.record))
        #expect(try Data(contentsOf: fixture.source) == original)
    }

    @Test("Source revalidation failure creates no shared copy or catalog relationship")
    func sourceValidationBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Source")
        try original.write(to: fixture.source)
        await #expect(throws: ZoteroPDFImportError.sourceChanged) {
            try await store.importPDF(at: fixture.source, zoteroSource: Self.zoteroSource(), allowNewVersion: false) {
                throw ZoteroPDFImportError.sourceChanged
            }
        }
        #expect(try await store.records().isEmpty)
        #expect(try Data(contentsOf: fixture.source) == original)
        await #expect(throws: PDFReaderError.sourceChanged) {
            try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false) {
                try Self.pdf("External replacement").write(to: fixture.source, options: .atomic)
            }
        }
        #expect(try await store.records().isEmpty)
    }

    @Test("Missing, unreadable, corrupt, locked, and linked copies fail without overwriting other files")
    func unavailableAndUnsafeFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Source")
        try original.write(to: fixture.source)
        let imported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        let file = try fixture.file(imported.record)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        await #expect(throws: PDFReaderError.unreadable) { try await store.load(attachmentID: imported.record.id) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data("not PDF".utf8).write(to: file)
        await #expect(throws: PDFReaderError.malformed) { try await store.load(attachmentID: imported.record.id) }
        try FileManager.default.removeItem(at: file)
        await #expect(throws: PDFReaderError.missing) { try await store.load(attachmentID: imported.record.id) }
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: fixture.source)
        await #expect(throws: PDFReaderError.unsafePath) { try await store.load(attachmentID: imported.record.id) }
        #expect(try Data(contentsOf: fixture.source) == original)
        let document = try #require(PDFDocument(data: original))
        let locked = try #require(
            document.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner", PDFDocumentWriteOption.userPasswordOption: "reader"]))
        let lockedURL = fixture.root.appendingPathComponent("Locked.pdf")
        try locked.write(to: lockedURL)
        await #expect(throws: PDFReaderError.locked) { try await store.importPDF(at: lockedURL, zoteroSource: nil, allowNewVersion: false) }
    }

    @Test("Export never replaces an existing file; closing releases the storage capability")
    func exportAndShutdown() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let original = Self.pdf("Source")
        try original.write(to: fixture.source)
        let imported = try await store.importPDF(at: fixture.source, zoteroSource: nil, allowNewVersion: false).snapshot
        #expect(throws: PDFReaderError.destinationExists) { try SharedPDFStore.export(candidate: original, to: fixture.source) }
        #expect(try Data(contentsOf: fixture.source) == original)
        await store.close()
        await #expect(throws: PDFReaderError.unreadable) { try await store.load(attachmentID: imported.record.id) }
        await #expect(throws: PDFReaderError.unreadable) {
            try await store.save(candidate: try Self.annotated(original, comment: "Closed"), expected: imported)
        }
    }

    private static func annotated(_ data: Data, comment: String) throws -> Data {
        let document = try #require(PDFDocument(data: data))
        let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 24, height: 24), forType: .text, withProperties: nil)
        annotation.contents = comment
        try #require(document.page(at: 0)).addAnnotation(annotation)
        return try #require(document.dataRepresentation())
    }

    private actor ImportGate {
        private var entered = false
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var entryWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            entered = true
            for waiter in entryWaiters { waiter.resume() }
            entryWaiters.removeAll()
            if !released { await withCheckedContinuation { waiting = $0 } }
        }

        func reached() async {
            if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
        }

        func release() {
            released = true
            waiting?.resume()
            waiting = nil
        }
    }

    private static func zoteroSource() throws -> ZoteroPDFSource {
        try ZoteroPDFSource(
            library: ZoteroLibraryMetadata(identity: .group(17), name: "Synthetic Library"),
            item: ZoteroItemMetadata(key: "PARENT01", title: "Synthetic Bibliography"),
            attachmentKey: "ATTACH01", attachmentVersion: 4, title: "Synthetic PDF", filename: "Source.pdf", linkMode: .importedFile,
            serverID: "test-database", attachmentMetadataFingerprint: DocumentFingerprint(data: Data("metadata".utf8)))
    }

    private static func pdf(_ text: String) -> Data {
        let stream = "BT /F1 12 Tf 20 150 Td (\(text)) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream",
        ]
        var result = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(result.utf8.count)
            result += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = result.utf8.count
        result += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { result += String(format: "%010d 00000 n \n", offset) }
        result += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(result.utf8)
    }

    private struct Fixture: Sendable {
        let root: URL
        let support: URL
        let controlURL: URL
        let source: URL
        let triptychID = UUID()

        init() throws {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            root = repository.appendingPathComponent(".build/pdf-reader-fixtures/\(UUID().uuidString)")
            support = root.appendingPathComponent("State")
            controlURL = root.appendingPathComponent(".scholium")
            source = root.appendingPathComponent("Source.pdf")
            for folder in [support, controlURL, root.appendingPathComponent("Works")] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        }

        func store() throws -> SharedPDFStore {
            let control = TriptychControlStore(worksVaultURL: root.appendingPathComponent("Works"))
            return try SharedPDFStore(controlURL: controlURL, controlStore: control, applicationSupportURL: support, triptychID: triptychID)
        }

        func file(_ record: PortableAttachmentRecord) throws -> URL {
            guard case .triptychRelative(let path) = record.location else { throw PDFReaderError.unsafePath }
            return controlURL.appendingPathComponent(path.rawValue)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
