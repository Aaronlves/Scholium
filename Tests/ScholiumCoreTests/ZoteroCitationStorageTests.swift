import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Portable citation authority and paired saves")
struct ZoteroCitationStorageTests {
    @Test("Metadata-only CAS preserves Markdown and rejects a stale companion")
    func metadataOnlyCAS() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("\u{FEFF}Research\r\n")
        let first = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "style-one"))
        )
        let firstSnapshot = try #require(first.document.citationSnapshot)
        let second = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: firstSnapshot.revision, data: .init(documentData: "style-two"))
        )
        #expect(first.document.fingerprint == second.document.fingerprint)
        #expect(firstSnapshot.revision != second.document.citationSnapshot?.revision)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: firstSnapshot.revision, data: .init(documentData: "stale"))
            )
        }
        #expect(try await fixture.repository.load(relativePath: "Note.md").rawContent == before.rawContent)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
    }

    @Test("A missing declared companion is unresolved even without citation markers")
    func missingEssentialMetadata() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research without citations\n")
        _ = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "document-only-style"))
        )
        try FileManager.default.removeItem(at: fixture.companionURL)
        let snapshot = try await fixture.control.citationSnapshot(
            noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: before.fingerprint
        )
        #expect(snapshot.status == .unresolved)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: nil, data: .init())
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
    }

    @Test("Unknown members and linked companion directories remain nonauthorizing")
    func unknownAndLinkedCompanions() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        _ = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init())
        )
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.companionURL)) as? [String: Any])
        object["futureAuthority"] = "preserve"
        let unknown = try JSONSerialization.data(withJSONObject: object)
        try unknown.write(to: fixture.companionURL)
        #expect(try await fixture.control.citationSnapshot(noteID: fixture.noteID, vaultID: fixture.vaultID).status == .unsupported)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: DocumentFingerprint(data: unknown), data: .init())
            )
        }
        #expect(try Data(contentsOf: fixture.companionURL) == unknown)
        let directory = fixture.companionURL.deletingLastPathComponent()
        let saved = fixture.root.appendingPathComponent("saved-companions", isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: saved)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: saved)
        await #expect(throws: (any Error).self) {
            try await fixture.control.citationSnapshot(noteID: fixture.noteID, vaultID: fixture.vaultID)
        }
        #expect(try Data(contentsOf: saved.appendingPathComponent(fixture.companionURL.lastPathComponent)) == unknown)
    }

    @Test("Interrupted source-first save retains exact pair and resumes metadata only")
    func interruptedPair() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\r\n")
        let failing = fixture.coordinator(afterSource: { throw Injected.failure })
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await failing.save(
                target: fixture.target(before), source: "After\r\n",
                edit: .init(expectedRevision: nil, data: .init(documentData: "style"))
            )
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        let evidence = try await fixture.recovery.citationSaveEvidence(record)
        #expect(evidence.sourceBefore == Data(before.rawContent.utf8))
        #expect(evidence.sourceAfter == Data("After\r\n".utf8))
        #expect(evidence.companionBefore == nil)
        #expect(evidence.companionAfter != nil)
        let diagnostic = try #require(try await fixture.recovery.pending().first)
        await #expect(throws: ZoteroCitationSaveError.self) { try await fixture.recovery.resolve(diagnostic) }
        let current = try await fixture.repository.load(relativePath: "Note.md")
        let reopened = try TriptychMutationRecoveryStore(storageURL: fixture.recoveryURL)
        let coordinator = ZoteroCitationSaveCoordinator(
            triptychID: fixture.triptychID, repositories: [fixture.vaultID: fixture.repository],
            controlStore: fixture.control, recoveryStore: reopened
        )
        #expect(try await coordinator.reconcile(record, target: fixture.target(current)) == .sourceCommitted)
        let result = try await coordinator.resume(record, target: fixture.target(current))
        #expect(result.document.rawContent == "After\r\n")
        #expect(result.document.citationSnapshot?.status == .available)
        #expect(try await reopened.pendingCitationSaves().isEmpty)
    }

    @Test("External source after companion commit is preserved and blocks recovery")
    func externalSourceAfterCompanion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\n")
        let coordinator = fixture.coordinator(afterCompanion: {
            try Data("External\n".utf8).write(to: fixture.noteURL)
        })
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await coordinator.save(target: fixture.target(before), source: "After\n", edit: .init(expectedRevision: nil, data: .init()))
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        let current = try await fixture.repository.load(relativePath: "Note.md")
        #expect(current.rawContent == "External\n")
        #expect(try await fixture.coordinator().reconcile(record, target: fixture.target(current)) == .conflicted)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().resume(record, target: fixture.target(current))
        }
        #expect(try Data(contentsOf: fixture.noteURL) == Data("External\n".utf8))
        #expect(try await fixture.recovery.pendingCitationSaves().count == 1)
    }

    @Test("A journaled creation with checked absence can be completed without inventing an identity")
    func unstartedCreationRecovery() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let source = Data("New\n".utf8)
        let companion = try TriptychControlStore.citationCompanionEncoding(
            .init(
                noteID: fixture.noteID, vaultID: fixture.vaultID,
                sourceFingerprint: DocumentFingerprint(data: source), data: .init()
            ))
        let record = try await fixture.recovery.prepareCitationSave(
            noteID: fixture.noteID, vaultID: fixture.vaultID, relativePath: "Note.md",
            sourceBefore: nil, sourceAfter: source, companionBefore: nil, companionAfter: companion,
            companionRequiredBefore: false
        )
        let target = fixture.target(NoteDocument(relativePath: "Note.md", rawContent: "New\n"))
        #expect(try await fixture.coordinator().reconcile(record, target: target) == .unchanged)
        try await fixture.coordinator().complete(record, target: target)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        #expect(try await fixture.control.identityRecord(id: fixture.noteID) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.noteURL.path))
    }

    @Test("Explicit paired absence clears the declaration and preserves the exact restored source")
    func explicitAbsenceRestoration() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("\u{FEFF}Original\r\n")
        let saved = try await fixture.coordinator().save(
            target: fixture.target(before), source: "Managed\r\n",
            edit: .init(expectedRevision: nil, data: .init(documentData: "style"))
        )
        let restored = try await fixture.coordinator().save(
            target: fixture.target(saved.document), source: before.rawContent,
            edit: .init(expectedRevision: saved.document.citationSnapshot?.revision, data: nil)
        )
        #expect(restored.document.rawContent == before.rawContent)
        #expect(restored.document.citationSnapshot?.status == .absent)
        #expect(try await fixture.control.identityRecord(id: fixture.noteID)?.citationCompanionRequired != true)
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
    }

    @Test("Malformed compact source is rejected before any journal or source write")
    func malformedSourceAdmission() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        await #expect(throws: ZoteroCitationError.self) {
            try await fixture.coordinator().save(
                target: fixture.target(before), source: "[Missing](cite:cMissing)\n",
                edit: .init(expectedRevision: nil, data: .init())
            )
        }
        #expect(try await fixture.repository.load(relativePath: "Note.md").rawContent == before.rawContent)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
    }

    @Test("A concurrent companion writer is preserved after the source commits")
    func concurrentCompanionAfterSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\n")
        let baseline = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "baseline"))
        )
        let external = try TriptychControlStore.citationCompanionEncoding(
            .init(
                noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: DocumentFingerprint(content: "After\n"),
                data: .init(documentData: "external")
            ))
        let coordinator = fixture.coordinator(afterSource: { try external.write(to: fixture.companionURL) })
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await coordinator.save(
                target: fixture.target(before), source: "After\n",
                edit: .init(expectedRevision: baseline.document.citationSnapshot?.revision, data: .init(documentData: "ours"))
            )
        }
        #expect(try Data(contentsOf: fixture.companionURL) == external)
        #expect(try await fixture.repository.load(relativePath: "Note.md").rawContent == "After\n")
        #expect(try await fixture.recovery.pendingCitationSaves().count == 1)
    }

    @Test("Interrupted deliberate companion removal resumes only its missing declaration update")
    func interruptedAbsenceRestoration() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Original\n")
        let saved = try await fixture.coordinator().save(
            target: fixture.target(before), source: "Managed\n",
            edit: .init(expectedRevision: nil, data: .init(documentData: "style"))
        )
        let failing = fixture.coordinator(afterSource: {
            try FileManager.default.removeItem(at: fixture.companionURL)
            throw Injected.failure
        })
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await failing.save(
                target: fixture.target(saved.document), source: before.rawContent,
                edit: .init(expectedRevision: saved.document.citationSnapshot?.revision, data: nil)
            )
        }
        #expect(try await fixture.control.citationSnapshot(noteID: fixture.noteID, vaultID: fixture.vaultID).status == .unresolved)
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        #expect(record.companionAfter == nil)
        let restored = try await fixture.coordinator().resume(record, target: fixture.target(before))
        #expect(restored.document.citationSnapshot?.status == .absent)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
    }

    @Test("Managed creation retains its reserved identity through partial companion failure")
    func createdPairRecovery() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator(afterSource: { throw Injected.failure }).create(
                id: .init(vaultID: fixture.vaultID, relativePath: "Note.md"), noteID: fixture.noteID,
                source: "Created\n", data: .init(documentData: "style")
            )
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        #expect(record.sourceBefore == nil)
        let identity = try #require(try await fixture.control.identityRecord(id: fixture.noteID))
        #expect(identity.vaultID == fixture.vaultID)
        #expect(identity.relativePath == "Note.md")
        #expect(identity.fingerprint == record.sourceAfter)
        let target = try await fixture.coordinator().recoverCreationIdentity(record)
        #expect(target.stableNoteID == fixture.noteID)
        let result = try await fixture.coordinator().resume(record, target: target)
        #expect(result.document.rawContent == "Created\n")
        #expect(result.document.citationSnapshot?.noteID == fixture.noteID)
    }

    @Test("Displaced companion completion requires a coherent pair and retains every revision")
    func displacedCompanionRemainsBound() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        let baseline = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "baseline"))
        )
        let external = try TriptychControlStore.citationCompanionEncoding(
            .init(
                noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: before.fingerprint,
                data: .init(documentData: "late-external")
            ))
        let controlled = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { url in
                if url == fixture.companionURL { try external.write(to: url) }
            },
            controlPostSwapHook: { url in
                if url == fixture.companionURL { throw Injected.failure }
            }
        )
        let coordinator = ZoteroCitationSaveCoordinator(
            triptychID: fixture.triptychID, repositories: [fixture.vaultID: fixture.repository],
            controlStore: controlled, recoveryStore: fixture.recovery
        )
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await coordinator.save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: baseline.document.citationSnapshot?.revision, data: .init(documentData: "attempted"))
            )
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        #expect(DocumentFingerprint(data: try Data(contentsOf: fixture.companionURL)) == record.companionAfter)
        #expect(try await fixture.recovery.citationSaveEvidence(record).companionDisplaced == external)
        #expect(try await fixture.coordinator().reconcile(record, target: fixture.target(before)) == .conflicted)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().resume(record, target: fixture.target(before))
        }
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().complete(record, target: fixture.target(before))
        }
        let attempted = try Data(contentsOf: fixture.companionURL)
        try external.write(to: fixture.companionURL)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        #expect(try Data(contentsOf: fixture.companionURL) == external)
        #expect(try await fixture.recovery.pendingCitationSaves().count == 1)
        try attempted.write(to: fixture.companionURL)
        try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        #expect(try Data(contentsOf: fixture.companionURL) == attempted)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(before.rawContent.utf8))
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        #expect(try await fixture.recovery.pending().isEmpty)
        let reopened = try TriptychMutationRecoveryStore(storageURL: fixture.recoveryURL)
        #expect(try await reopened.retainedCitationSaves() == [record])
        let retained = try await reopened.citationSaveEvidence(record)
        #expect(retained.sourceBefore == Data(before.rawContent.utf8))
        #expect(retained.sourceAfter == Data(before.rawContent.utf8))
        #expect(retained.companionBefore != nil)
        #expect(retained.companionAfter == attempted)
        #expect(retained.companionDisplaced == external)
        // Completion is idempotent, but no future receipt member can silently
        // suppress pending evidence or authorize deleting the retained bytes.
        try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        let receipt = fixture.recoveryURL.appendingPathComponent("citation-pairs-v1/\(record.id.uuidString.lowercased())-completed.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any])
        object["futureDisposition"] = true
        let altered = try JSONSerialization.data(withJSONObject: object)
        try altered.write(to: receipt)
        await #expect(throws: (any Error).self) { try await reopened.pendingCitationSaves() }
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        #expect(try Data(contentsOf: receipt) == altered)
        #expect(try await reopened.citationSaveEvidence(record).companionDisplaced == external)
    }

    @Test("Explicit completion can retain displaced evidence for the exact original pair")
    func retainedOriginalPairCompletion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\n")
        let after = Data("After\n".utf8)
        let companion = try TriptychControlStore.citationCompanionEncoding(
            .init(noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: .init(data: after), data: .init(documentData: "candidate")))
        let record = try await fixture.recovery.prepareCitationSave(
            noteID: fixture.noteID, vaultID: fixture.vaultID, relativePath: "Note.md",
            sourceBefore: Data(before.rawContent.utf8), sourceAfter: after,
            companionBefore: nil, companionAfter: companion, companionRequiredBefore: false
        )
        let displaced = Data("displaced opaque external authority".utf8)
        try await fixture.recovery.retainDisplacedCitationCompanion(record, bytes: displaced)
        for source in ["After\n", "Newer external source\n"] {
            try Data(source.utf8).write(to: fixture.noteURL)
            let current = try await fixture.repository.load(relativePath: "Note.md")
            await #expect(throws: ZoteroCitationSaveError.self) {
                try await fixture.coordinator().complete(record, target: fixture.target(current), explicitlyCompletingRetainedEvidence: true)
            }
            #expect(try Data(contentsOf: fixture.noteURL) == Data(source.utf8))
            #expect(try await fixture.recovery.pendingCitationSaves() == [record])
        }
        try Data(before.rawContent.utf8).write(to: fixture.noteURL)
        try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        #expect(try await fixture.recovery.retainedCitationSaves() == [record])
        #expect(try await fixture.recovery.citationSaveEvidence(record).companionDisplaced == displaced)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(before.rawContent.utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
    }

    @Test("Restart after a retained receipt preserves newer remainders and permits the next removal")
    func retainedDeletionRemainderCompletion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        let baseline = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "style")))
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator(afterSource: { throw Injected.failure }).save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: baseline.document.citationSnapshot?.revision, data: nil))
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        let deleting = fixture.companionURL.deletingLastPathComponent().appendingPathComponent(
            ".scholium-deleting-\(fixture.noteID.uuidString.lowercased()).json")
        let displaced = Data("external interrupted deletion".utf8)
        try displaced.write(to: deleting)
        #expect(try await fixture.coordinator().reconcile(record, target: fixture.target(before)) == .conflicted)
        let newer = Data("newer external remainder".utf8)
        try newer.write(to: deleting)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        #expect(try Data(contentsOf: deleting) == newer)
        #expect(try await fixture.recovery.citationSaveEvidence(record).companionDisplaced == displaced)
        #expect(try await fixture.recovery.pendingCitationSaves() == [record])
        try displaced.write(to: deleting)
        await #expect(throws: Injected.self) {
            try await fixture.coordinator(afterRetainedCompletion: { throw Injected.failure }).complete(
                record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        #expect(try Data(contentsOf: deleting) == displaced)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        #expect(try await fixture.recovery.retainedCitationSaves() == [record])
        #expect(try await fixture.recovery.citationSaveEvidence(record).companionDisplaced == displaced)
        // A later coherent source/companion pair is not the historical before
        // or after pair. Receipt-backed cleanup must not attempt to restore it.
        let laterSource = "Later valid source\n"
        let laterCompanion = try TriptychControlStore.citationCompanionEncoding(
            .init(
                noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: .init(content: laterSource),
                data: .init(documentData: "later style")))
        try Data(laterSource.utf8).write(to: fixture.noteURL)
        try laterCompanion.write(to: fixture.companionURL)
        let reopened = try TriptychMutationRecoveryStore(storageURL: fixture.recoveryURL)
        let reopenedControl = try TriptychControlStore(worksVaultURL: fixture.works, coordinationURL: fixture.recoveryURL.deletingLastPathComponent())
        let restarted = ZoteroCitationSaveCoordinator(
            triptychID: fixture.triptychID, repositories: [fixture.vaultID: fixture.repository], controlStore: reopenedControl, recoveryStore: reopened)
        let later = try await fixture.repository.load(relativePath: "Note.md")
        try newer.write(to: deleting)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await restarted.save(
                target: fixture.target(later), source: laterSource,
                edit: .init(expectedRevision: .init(data: laterCompanion), data: nil))
        }
        #expect(try Data(contentsOf: deleting) == newer)
        #expect(try Data(contentsOf: fixture.companionURL) == laterCompanion)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(laterSource.utf8))
        try displaced.write(to: deleting)
        let removed = try await restarted.save(
            target: fixture.target(later), source: laterSource,
            edit: .init(expectedRevision: .init(data: laterCompanion), data: nil))
        #expect(removed.document.citationSnapshot?.status == .absent)
        #expect(!FileManager.default.fileExists(atPath: deleting.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
        #expect(try Data(contentsOf: fixture.noteURL) == Data(laterSource.utf8))
        #expect(try await reopened.pendingCitationSaves().isEmpty)
        #expect(try await reopened.retainedCitationSaveEvidence(record).companionDisplaced == displaced)
    }

    @Test("Unsupported or changed Triptych scope cannot authorize citation save or creation")
    func invalidScopeMutationAdmission() async throws {
        for invalidScope in InvalidScope.allCases {
            let fixture = try await Fixture()
            defer { fixture.remove() }
            let before = try await fixture.note("Before\n")
            let identities = try Data(contentsOf: fixture.identityURL)
            let manifest = try fixture.invalidateScope(invalidScope)
            await #expect(throws: (any Error).self) {
                try await fixture.coordinator().save(
                    target: fixture.target(before), source: "After\n", edit: .init(expectedRevision: nil, data: .init()))
            }
            await #expect(throws: (any Error).self) {
                try await fixture.coordinator().create(
                    id: .init(vaultID: fixture.vaultID, relativePath: "Created.md"), noteID: UUID(), source: "Created\n", data: .init())
            }
            #expect(try Data(contentsOf: fixture.noteURL) == Data(before.rawContent.utf8))
            #expect(try Data(contentsOf: fixture.identityURL) == identities)
            #expect(try Data(contentsOf: fixture.manifestURL) == manifest)
            #expect(!FileManager.default.fileExists(atPath: fixture.works.appendingPathComponent("Created.md").path))
            #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
            #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        }
    }

    @Test("Shared deletion cleanup matches all retained receipts without borrowing transaction staging authority")
    func multipleRetainedReceiptCleanup() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        let baseline = try await fixture.coordinator().save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: nil, data: .init(documentData: "style")))
        let source = Data(before.rawContent.utf8)
        let companion = try Data(contentsOf: fixture.companionURL)
        for index in 0..<2 {
            let record = try await fixture.recovery.prepareCitationSave(
                noteID: fixture.noteID, vaultID: fixture.vaultID, relativePath: "Note.md",
                sourceBefore: source, sourceAfter: source, companionBefore: companion, companionAfter: nil,
                companionRequiredBefore: true)
            try await fixture.recovery.retainDisplacedCitationCompanion(record, bytes: Data("external revision \(index)".utf8))
            try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        let records = try await fixture.recovery.retainedCitationSaves()
        #expect(records.count == 2)
        let first = try #require(records.first)
        let last = try #require(records.last)
        let firstDisplaced = try #require(try await fixture.recovery.retainedCitationSaveEvidence(first).companionDisplaced)
        let lastDisplaced = try #require(try await fixture.recovery.retainedCitationSaveEvidence(last).companionDisplaced)
        #expect(firstDisplaced != lastDisplaced)
        let deleting = fixture.companionURL.deletingLastPathComponent().appendingPathComponent(
            ".scholium-deleting-\(fixture.noteID.uuidString.lowercased()).json")
        // Choose the last enumerated receipt deliberately: the first receipt
        // must not reject this shared name before the matching one is checked.
        try lastDisplaced.write(to: deleting)
        await #expect(throws: Injected.self) {
            try await fixture.coordinator(afterRetainedCompletion: { throw Injected.failure }).complete(
                last, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        }
        let reopened = try TriptychMutationRecoveryStore(storageURL: fixture.recoveryURL)
        let restarted = ZoteroCitationSaveCoordinator(
            triptychID: fixture.triptychID, repositories: [fixture.vaultID: fixture.repository], controlStore: fixture.control, recoveryStore: reopened)
        let staging = fixture.companionURL.deletingLastPathComponent().appendingPathComponent(
            ExactFileReplacement.transactionStagingName(fileName: fixture.companionURL.lastPathComponent, transactionID: first.id))
        try lastDisplaced.write(to: staging)
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await restarted.save(
                target: fixture.target(before), source: before.rawContent,
                edit: .init(expectedRevision: baseline.document.citationSnapshot?.revision, data: nil))
        }
        #expect(try Data(contentsOf: staging) == lastDisplaced)
        #expect(try Data(contentsOf: deleting) == lastDisplaced)
        #expect(try Data(contentsOf: fixture.companionURL) == companion)
        try FileManager.default.removeItem(at: staging)
        let removed = try await restarted.save(
            target: fixture.target(before), source: before.rawContent,
            edit: .init(expectedRevision: baseline.document.citationSnapshot?.revision, data: nil))
        #expect(removed.document.citationSnapshot?.status == .absent)
        #expect(!FileManager.default.fileExists(atPath: deleting.path))
        #expect(try await reopened.retainedCitationSaves() == records)
        #expect(try await reopened.retainedCitationSaveEvidence(first).companionDisplaced == firstDisplaced)
        #expect(try await reopened.retainedCitationSaveEvidence(last).companionDisplaced == lastDisplaced)
        #expect(try await reopened.pendingCitationSaves().isEmpty)
    }

    @Test("Metadata-only recovery can explicitly keep the proven original pair")
    func retainedMetadataOnlyOriginalPair() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Research\n")
        let bytes = Data(before.rawContent.utf8)
        let companion = try TriptychControlStore.citationCompanionEncoding(
            .init(noteID: fixture.noteID, vaultID: fixture.vaultID, sourceFingerprint: before.fingerprint, data: .init(documentData: "candidate")))
        let record = try await fixture.recovery.prepareCitationSave(
            noteID: fixture.noteID, vaultID: fixture.vaultID, relativePath: "Note.md",
            sourceBefore: bytes, sourceAfter: bytes, companionBefore: nil, companionAfter: companion, companionRequiredBefore: false)
        let displaced = Data("external metadata".utf8)
        try await fixture.recovery.retainDisplacedCitationCompanion(record, bytes: displaced)
        try await fixture.coordinator().complete(record, target: fixture.target(before), explicitlyCompletingRetainedEvidence: true)
        #expect(try await fixture.recovery.pendingCitationSaves().isEmpty)
        #expect(try await fixture.recovery.retainedCitationSaves() == [record])
        #expect(try await fixture.recovery.citationSaveEvidence(record).companionDisplaced == displaced)
        #expect(try Data(contentsOf: fixture.noteURL) == bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
    }

    @Test("Every recovery entry rereads supported complete Triptych scope")
    func invalidScopeRecoveryAdmission() async throws {
        for invalidScope in InvalidScope.allCases {
            let fixture = try await Fixture()
            defer { fixture.remove() }
            let coordinator = fixture.coordinator(afterSource: { throw Injected.failure })
            await #expect(throws: ZoteroCitationSaveError.self) {
                try await coordinator.create(
                    id: .init(vaultID: fixture.vaultID, relativePath: "Note.md"), noteID: fixture.noteID, source: "Created\n", data: .init())
            }
            let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
            let current = try await fixture.repository.load(relativePath: "Note.md")
            let target = fixture.target(current)
            let identities = try Data(contentsOf: fixture.identityURL)
            let manifest = try fixture.invalidateScope(invalidScope)
            await #expect(throws: (any Error).self) { try await coordinator.reconcile(record, target: target) }
            await #expect(throws: (any Error).self) { try await coordinator.recoverCreationIdentity(record) }
            await #expect(throws: (any Error).self) { try await coordinator.resume(record, target: target) }
            await #expect(throws: (any Error).self) { try await coordinator.complete(record, target: target) }
            await #expect(throws: (any Error).self) {
                try await coordinator.complete(record, target: target, explicitlyCompletingRetainedEvidence: true)
            }
            #expect(try Data(contentsOf: fixture.noteURL) == Data(current.rawContent.utf8))
            #expect(try Data(contentsOf: fixture.identityURL) == identities)
            #expect(try Data(contentsOf: fixture.manifestURL) == manifest)
            #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
            #expect(try await fixture.recovery.pendingCitationSaves() == [record])
            #expect(try await fixture.recovery.retainedCitationSaves().isEmpty)
        }
    }

    @Test("Scope replacement between source and companion retains the partial pair")
    func scopeChangesAfterSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\n")
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator(afterSource: { _ = try fixture.invalidateScope(.future) }).save(
                target: fixture.target(before), source: "After\n", edit: .init(expectedRevision: nil, data: .init()))
        }
        #expect(try Data(contentsOf: fixture.noteURL) == Data("After\n".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.companionURL.path))
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        let evidence = try await fixture.recovery.citationSaveEvidence(record)
        #expect(evidence.sourceBefore == Data(before.rawContent.utf8))
        #expect(evidence.sourceAfter == Data("After\n".utf8))
        #expect(evidence.companionAfter != nil)
    }

    @Test("Unknown recovery authority cannot resume or be discarded")
    func unknownRecoveryRecord() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let before = try await fixture.note("Before\n")
        await #expect(throws: ZoteroCitationSaveError.self) {
            try await fixture.coordinator(afterSource: { throw Injected.failure }).save(
                target: fixture.target(before), source: "After\n", edit: .init(expectedRevision: nil, data: .init())
            )
        }
        let record = try #require(try await fixture.recovery.pendingCitationSaves().first)
        let manifest = fixture.recoveryURL.appendingPathComponent("citation-pairs-v1/\(record.id.uuidString.lowercased())-pair.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        object["futureAuthority"] = true
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: manifest)
        let after = try await fixture.repository.load(relativePath: "Note.md")
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator().resume(record, target: fixture.target(after))
        }
        #expect(try Data(contentsOf: manifest) == bytes)
        #expect(try Data(contentsOf: fixture.noteURL) == Data("After\n".utf8))
    }

    private enum Injected: Error { case failure }
    private enum InvalidScope: CaseIterable, Sendable {
        case future, incomplete, duplicateVault, foreignTriptych, foreignVault, malformed
    }

    private struct Fixture: Sendable {
        let root: URL
        let works: URL
        let triptychID = UUID()
        let vaultID = UUID()
        let noteID = UUID()
        let control: TriptychControlStore
        let repository: VaultRepository
        let recovery: TriptychMutationRecoveryStore
        let recoveryURL: URL
        var noteURL: URL { works.appendingPathComponent("Note.md") }
        var companionURL: URL { root.appendingPathComponent(".scholium/citations/v1/\(noteID.uuidString.lowercased()).json") }
        var identityURL: URL { root.appendingPathComponent(".scholium/identities.json") }
        var manifestURL: URL { root.appendingPathComponent(".scholium/manifest.json") }

        init() async throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Scholium-Citation-\(UUID().uuidString)", isDirectory: true)
            works = root.appendingPathComponent("Works", isDirectory: true)
            try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
            let local = root.appendingPathComponent("local", isDirectory: true)
            let triptychStorage = local.appendingPathComponent("Triptychs/\(triptychID.uuidString)", isDirectory: true)
            control = try TriptychControlStore(worksVaultURL: works, coordinationURL: triptychStorage)
            _ = try await control.bootstrap(vaultIDs: [.paperAnalysis: UUID(), .topicKnowledge: UUID(), .output: vaultID], preferredTriptychID: triptychID)
            repository = try VaultRepository(
                vaultURL: works, identity: .init(id: vaultID, canonicalPath: works.path, bookmarkData: nil), applicationSupportURL: local)
            recoveryURL = triptychStorage.appendingPathComponent("transactions", isDirectory: true)
            recovery = try TriptychMutationRecoveryStore(storageURL: recoveryURL)
        }

        func note(_ source: String) async throws -> NoteDocument {
            let document = try await repository.create(relativePath: "Note.md", content: source)
            _ = try await control.identity(forVaultID: vaultID, relativePath: "Note.md", fingerprint: document.fingerprint, preferredID: noteID)
            return document
        }

        func target(_ document: NoteDocument) -> NoteMutationTarget {
            .init(documentID: .init(vaultID: vaultID, relativePath: "Note.md"), stableNoteID: noteID, revision: document.fingerprint)
        }

        func invalidateScope(_ change: InvalidScope) throws -> Data {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let original = try decoder.decode(TriptychManifest.self, from: Data(contentsOf: manifestURL))
            var vaultIDs = original.vaultIDs
            var id = original.id
            switch change {
            case .incomplete: vaultIDs.removeValue(forKey: .topicKnowledge)
            case .duplicateVault: vaultIDs[.topicKnowledge] = vaultIDs[.output]
            case .foreignTriptych: id = UUID()
            case .foreignVault: vaultIDs[.output] = UUID()
            case .future, .malformed: break
            }
            let manifest = TriptychManifest(id: id, vaultIDs: vaultIDs, createdAt: original.createdAt, updatedAt: original.updatedAt)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(manifest)) as? [String: Any])
            switch change {
            case .future: object["schemaVersion"] = 999
            case .malformed: object["schemaVersion"] = "unsupported"
            default: break
            }
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: manifestURL)
            return bytes
        }

        func coordinator(
            afterSource: (@Sendable () async throws -> Void)? = nil,
            afterCompanion: (@Sendable () async throws -> Void)? = nil,
            afterRetainedCompletion: (@Sendable () async throws -> Void)? = nil
        ) -> ZoteroCitationSaveCoordinator {
            ZoteroCitationSaveCoordinator(
                triptychID: triptychID, repositories: [vaultID: repository], controlStore: control, recoveryStore: recovery, afterSource: afterSource,
                afterCompanion: afterCompanion, afterRetainedCompletion: afterRetainedCompletion)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
