import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded related-content lexical row memo")
struct RelatedContentBackgroundMemoTests {
    private let triptychID = UUID()

    @Test("A partial row budget preserves resident hits across repeated sequential full scans")
    func partialPoolDoesNotThrash() throws {
        let payload = try Payload("orchard geology magnetic compass")
        let generation = generation()
        var probe = RelatedContentBackgroundPreparation()
        _ = try load(&probe, rowID: 0, generation: generation, payload: payload)
        let rowCost = probe.estimatedByteCount
        #expect(probe.maximumByteCount == 16 * 1_024 * 1_024)
        #expect(rowCost > payload.projection.estimatedByteCount)
        var memo = RelatedContentBackgroundPreparation(maximumByteCount: rowCost * 2)
        let rows = Set(0..<5)
        let coldProtection = memo.scanProtection(generation: generation, rowIDs: rows)
        for rowID in 0..<5 {
            let result = try load(&memo, rowID: rowID, generation: generation, payload: payload, protection: coldProtection)
            #expect(result.scoringDocument.hasSameContents(as: payload.projection.scoringDocument))
        }
        #expect(memo.entryCount == 2 && memo.estimatedByteCount == rowCost * 2)
        #expect(memo.statistics.misses == 5 && memo.statistics.evictions == 3)
        #expect(memo.scoringStorage(rowID: 3, fingerprint: payload.fingerprint) != nil)
        #expect(memo.scoringStorage(rowID: 4, fingerprint: payload.fingerprint) != nil)
        let warmProtection = memo.scanProtection(generation: generation, rowIDs: rows)
        for rowID in 0..<5 {
            let result = try load(&memo, rowID: rowID, generation: generation, payload: payload, protection: warmProtection)
            #expect(result.scoringDocument.hasSameContents(as: payload.projection.scoringDocument))
        }
        #expect(memo.statistics.hits == 2 && memo.statistics.misses == 8)
        #expect(memo.statistics.protectedAdmissionSkips == 3)
        #expect(memo.statistics.evictions == 3)
        #expect(memo.entryCount == 2 && memo.estimatedByteCount == rowCost * 2)

        var undersized = RelatedContentBackgroundPreparation(maximumByteCount: rowCost - 1)
        let uncached = try load(&undersized, rowID: 0, generation: generation, payload: payload)
        #expect(uncached.scoringDocument.hasSameContents(as: payload.projection.scoringDocument))
        #expect(undersized.entryCount == 0 && undersized.estimatedByteCount == 0)
        #expect(undersized.statistics.oversizeSkips == 1)
    }

    @Test("Generation and exact row revisions invalidate independently of seed or scope")
    func generationAndRevision() throws {
        let a = try Payload("orchard geology é")
        let b = try Payload("orchard geology e\u{301}")
        #expect(a.fingerprint != b.fingerprint)
        var memo = RelatedContentBackgroundPreparation()
        let first = generation()
        _ = try load(&memo, rowID: 11, generation: first, payload: a)
        _ = try load(&memo, rowID: 11, generation: first, payload: a)
        #expect(memo.statistics.hits == 1 && memo.statistics.misses == 1)
        _ = try load(&memo, rowID: 11, generation: first, payload: b)
        #expect(memo.entryCount == 1 && memo.statistics.misses == 2)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: a.fingerprint) == nil)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: b.fingerprint) != nil)
        memo.retain(generation: first)
        #expect(memo.entryCount == 1)
        let second = generation(2)
        memo.retain(generation: second)
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
        _ = try load(&memo, rowID: 11, generation: second, payload: b)
        #expect(memo.statistics.hits == 1 && memo.statistics.misses == 3)
    }

    @Test("An oversized replacement releases the old row without changing computed results")
    func oversizedRevision() throws {
        let small = try Payload("orchard geology")
        let large = try Payload(String(repeating: "geology magnetic calibration instrument ", count: 100))
        let generation = generation()
        var probe = RelatedContentBackgroundPreparation()
        _ = try load(&probe, rowID: 11, generation: generation, payload: small)
        var memo = RelatedContentBackgroundPreparation(maximumByteCount: probe.estimatedByteCount)
        _ = try load(&memo, rowID: 11, generation: generation, payload: small)
        let result = try load(&memo, rowID: 11, generation: generation, payload: large)
        #expect(result.scoringDocument.hasSameContents(as: large.projection.scoringDocument))
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0 && memo.statistics.oversizeSkips == 1)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: small.fingerprint) == nil)
    }

    enum Damage: CaseIterable, Sendable { case missingData, missingChecksum, changedBytes, changedChecksum, invalidJSON }
    @Test("A resident row cannot conceal missing or damaged current payload", arguments: Damage.allCases)
    func currentPayloadValidation(_ damage: Damage) throws {
        let payload = try Payload("orchard geology")
        let generation = generation()
        var memo = RelatedContentBackgroundPreparation()
        _ = try load(&memo, rowID: 11, generation: generation, payload: payload)
        var data: Data? = payload.data
        var checksum: String? = payload.checksum
        switch damage {
        case .missingData: data = nil
        case .missingChecksum: checksum = nil
        case .changedBytes: data = Data([0])
        case .changedChecksum: checksum = "incorrect"
        case .invalidJSON:
            data = Data([0])
            checksum = RelatedContentSourceProjection.checksum(Data([0]))
        }
        let protection = memo.scanProtection(generation: generation, rowIDs: [11])
        do {
            _ = try memo.projection(
                rowID: 11, generation: generation, fingerprint: payload.fingerprint,
                data: data, checksum: checksum, protection: protection)
            Issue.record("Cached decoded values must not hide current storage damage")
        } catch SearchIndexError.corruptDatabase {}
        #expect(memo.statistics.hits == 0 && memo.statistics.misses == 2)
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
    }

    @Test("A valid changed current payload is decoded even when the source fingerprint is unchanged")
    func replacedPayload() throws {
        let a = try Payload("orchard geology")
        let b = try Payload("magnetic compass")
        let generation = generation()
        var memo = RelatedContentBackgroundPreparation()
        _ = try load(&memo, rowID: 11, generation: generation, payload: a)
        let protection = memo.scanProtection(generation: generation, rowIDs: [11])
        let result = try memo.projection(
            rowID: 11, generation: generation, fingerprint: a.fingerprint,
            data: b.data, checksum: b.checksum, protection: protection)
        #expect(result.scoringDocument.hasSameContents(as: b.projection.scoringDocument))
        #expect(!result.scoringDocument.hasSameContents(as: a.projection.scoringDocument))
        #expect(memo.statistics.hits == 0 && memo.statistics.misses == 2)
    }

    private func generation(_ sequence: Int = 1) -> SearchGenerationID {
        .init(triptychID: triptychID, sequence: sequence, sourceManifestHash: "manifest-\(sequence)")
    }
    private func load(
        _ memo: inout RelatedContentBackgroundPreparation, rowID: Int, generation: SearchGenerationID,
        payload: Payload, protection: RelatedContentBackgroundPreparation.ScanProtection? = nil
    ) throws -> RelatedContentLexicalProjection {
        let protection = protection ?? memo.scanProtection(generation: generation, rowIDs: [])
        return try memo.projection(
            rowID: rowID, generation: generation, fingerprint: payload.fingerprint,
            data: payload.data, checksum: payload.checksum, protection: protection)
    }
    private struct Payload {
        let fingerprint: DocumentFingerprint
        let projection: RelatedContentLexicalProjection
        let data: Data
        let checksum: String
        init(_ source: String) throws {
            let note = NoteDocument(relativePath: "Material.md", rawContent: source)
            let search = SearchDocumentProjection(document: note)
            fingerprint = note.fingerprint
            projection = .init(projection: search, scoringDocument: .init(segments: search.segments))
            data = try projection.encoded()
            checksum = RelatedContentSourceProjection.checksum(data)
        }
    }
}
