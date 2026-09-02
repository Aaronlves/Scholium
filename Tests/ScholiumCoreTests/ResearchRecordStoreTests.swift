import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Research Record store", .serialized)
struct ResearchRecordStoreTests {
    @Test("Create, append, correction, and restart preserve exact history")
    func lifecycleAndRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let submitter = try ResearchRecordSubmitter(displayName: "Codex")
        let firstTime = Date(timeIntervalSince1970: 1_700_000_000)
        let secondTime = Date(timeIntervalSince1970: 1_700_000_100)
        let correctionTime = Date(timeIntervalSince1970: 1_700_000_200)

        let created = try await store.create(
            question: "Can emotions ground reasons?",
            submittedBy: submitter,
            bodyMarkdown: "The first answer distinguishes motivation from normativity.",
            recordedAt: firstTime
        )
        #expect(created.kind == .created)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL(created.revision.id).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyRecordURL.path))

        let appended = try await store.append(
            recordID: created.revision.id,
            expectedFingerprint: created.revision.fingerprint,
            submittedBy: submitter,
            bodyMarkdown: "A later objection changes the qualified answer.",
            revisesStepIDs: [created.stepID],
            replacementQuestion: "Can affective presentation ground normative reasons?",
            recordedAt: secondTime
        )
        #expect(appended.kind == .appended)
        #expect(appended.revision.record.steps.count == 2)

        let corrected = try await store.correct(
            recordID: appended.revision.id,
            stepID: appended.stepID,
            expectedFingerprint: appended.revision.fingerprint,
            submittedBy: submitter,
            bodyMarkdown: "A later objection changes the qualified answer.",
            revisesStepIDs: [created.stepID],
            noteReferences: [],
            correctedAt: correctionTime
        )
        #expect(corrected.record.steps[1].corrections.count == 1)
        #expect(corrected.record.lastSubstantiveAt == secondTime)

        let reopened = try fixture.store()
        let listing = try await reopened.listing()
        #expect(listing.issues.isEmpty)
        #expect(listing.records == [corrected])
    }

    @Test("Stale append changes no bytes")
    func staleAppendFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let submitter = try ResearchRecordSubmitter(displayName: "Codex")
        let created = try await store.create(
            question: "Which distinction matters?",
            submittedBy: submitter,
            bodyMarkdown: "The first distinction has a reason."
        )
        let appended = try await store.append(
            recordID: created.revision.id,
            expectedFingerprint: created.revision.fingerprint,
            submittedBy: submitter,
            bodyMarkdown: "The next judgment changes the answer."
        )
        let exact = try Data(contentsOf: fixture.recordURL(created.revision.id))

        do {
            _ = try await store.append(
                recordID: created.revision.id,
                expectedFingerprint: created.revision.fingerprint,
                submittedBy: submitter,
                bodyMarkdown: "This stale write must fail."
            )
            Issue.record("Expected stale Record rejection.")
        } catch let error as ResearchRecordStoreError {
            guard case .staleRevision(_, let expected, let current) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(expected == created.revision.fingerprint)
            #expect(current == appended.revision.fingerprint)
        }
        #expect(try Data(contentsOf: fixture.recordURL(created.revision.id)) == exact)
    }

    @Test("One damaged file is isolated and never rewritten")
    func damagedNeighborIsolated() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let submitter = try ResearchRecordSubmitter(displayName: "Codex")
        let valid = try await store.create(
            question: "What remains valid?",
            submittedBy: submitter,
            bodyMarkdown: "This valid Record remains readable."
        )
        let damagedID = UUID()
        let damagedURL = fixture.recordURL(damagedID)
        try Data("{\"schema_version\":999}".utf8).write(to: damagedURL)
        let exactDamaged = try Data(contentsOf: damagedURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [valid.revision.id])
        #expect(listing.issues.map(\.fileName) == [
            "\(damagedID.uuidString.lowercased()).json"
        ])
        #expect(try Data(contentsOf: damagedURL) == exactDamaged)
    }

    private struct Fixture {
        let root: URL
        let controlURL: URL
        let supportURL: URL
        let triptychID = UUID()

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/research-record-store-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            controlURL = root.appendingPathComponent(".scholium", isDirectory: true)
            supportURL = root.appendingPathComponent("support", isDirectory: true)
            try FileManager.default.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: supportURL,
                withIntermediateDirectories: true
            )
        }

        func store() throws -> ResearchRecordStore {
            try ResearchRecordStore(
                controlURL: controlURL,
                applicationSupportURL: supportURL,
                triptychID: triptychID
            )
        }

        func recordURL(_ id: UUID) -> URL {
            controlURL
                .appendingPathComponent("inquiry-records/v1")
                .appendingPathComponent("\(id.uuidString.lowercased()).json")
        }

        var legacyRecordURL: URL {
            controlURL.appendingPathComponent("research-records/v1/records")
        }

        func dispose() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
