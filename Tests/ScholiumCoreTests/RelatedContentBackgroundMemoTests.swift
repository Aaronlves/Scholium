import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded related-content background memo")
struct RelatedContentBackgroundMemoTests {
    private let triptychID = UUID()
    private let vaultID = UUID()

    @Test("Preparation is bounded by both two Notes and estimated bytes, with LRU reuse")
    func boundsAndEviction() throws {
        let value = try preparedValue()
        let a = key("A.md")
        let b = key("B.md")
        let c = key("C.md")
        var memo = RelatedContentBackgroundPreparation()
        #expect(memo.maximumByteCount == 16 * 1_024 * 1_024)
        try memo.store(value, for: a)
        let oneCost = memo.estimatedByteCount
        #expect(oneCost > value.estimatedByteCount)
        try memo.store(value, for: b)
        #expect(memo.entryCount == 2)
        #expect(try memo.prepared(for: a)?.documents.count == value.documents.count)
        try memo.store(value, for: c)
        #expect(memo.entryCount == 2)
        #expect(memo.statistics.evictions == 1)
        #expect(try memo.prepared(for: b) == nil)
        #expect(try memo.prepared(for: a)?.documents.count == value.documents.count)
        #expect(try memo.prepared(for: c)?.documents.count == value.documents.count)
        #expect(memo.estimatedByteCount == oneCost * 2)

        var oneSlot = RelatedContentBackgroundPreparation(maximumByteCount: oneCost)
        try oneSlot.store(value, for: a)
        try oneSlot.store(value, for: b)
        #expect(oneSlot.entryCount == 1)
        #expect(oneSlot.estimatedByteCount == oneCost)
        #expect(try oneSlot.prepared(for: a) == nil)
        #expect(try oneSlot.prepared(for: b)?.documents.count == value.documents.count)

        var tooSmall = RelatedContentBackgroundPreparation(maximumByteCount: oneCost - 1)
        try tooSmall.store(value, for: a)
        #expect(tooSmall.entryCount == 0 && tooSmall.estimatedByteCount == 0)
        #expect(tooSmall.statistics.oversizeSkips == 1)
        // The complete computed pool remains available; the budget affects only retention.
        #expect(value.documents.count == 4)
        #expect(try tooSmall.prepared(for: a) == nil)
    }

    @Test("Canonical roles reuse preparation, but scope, exact bytes, path and generation do not")
    func keyInvariants() throws {
        let value = try preparedValue()
        var memo = RelatedContentBackgroundPreparation()
        let original = key("A.md", source: "é", roles: [.work, .analysis, .analysis])
        let canonical = key("A.md", source: "é", roles: [.analysis, .work])
        #expect(original == canonical)
        try memo.store(value, for: original)
        #expect(try memo.prepared(for: canonical) != nil)
        let narrow = key("A.md", source: "é", roles: [.analysis])
        #expect(try memo.prepared(for: narrow) == nil)
        #expect(memo.entryCount == 0)
        try memo.store(value, for: narrow)
        let changedBytes = key("A.md", source: "e\u{301}", roles: [.analysis])
        #expect(try memo.prepared(for: changedBytes) == nil)
        try memo.store(value, for: changedBytes)
        try memo.store(value, for: key("B.md"))
        #expect(memo.entryCount == 2)
        #expect(try memo.prepared(for: key("B.md", sequence: 2)) == nil)
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)

        let composed = key("É.md")
        let decomposed = key("E\u{301}.md")
        #expect(composed.note == decomposed.note)
        #expect(composed != decomposed)
        try memo.store(value, for: composed)
        #expect(try memo.prepared(for: decomposed) == nil)
        #expect(memo.entryCount == 0)
    }

    @Test("Oversized replacement does not leave the previous version resident")
    func oversizedRevision() throws {
        let value = try preparedValue()
        let original = key("A.md")
        var probe = RelatedContentBackgroundPreparation()
        try probe.store(value, for: original)
        var memo = RelatedContentBackgroundPreparation(maximumByteCount: probe.estimatedByteCount)
        try memo.store(value, for: original)
        var larger = value
        for rowID in 5..<40 { larger.documents[rowID] = value.documents[0] }
        try memo.store(larger, for: key("A.md", source: "new revision"))
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
        #expect(memo.statistics.oversizeSkips == 1)
        #expect(try memo.prepared(for: original) == nil)
        #expect(larger.documents.count == 39)
    }

    @Test("Decoded projection reuse requires current payload, checksum and exact fingerprint")
    func digestValidation() throws {
        let document = NoteDocument(relativePath: "A.md", rawContent: "orchard geology")
        let projection = RelatedContentLexicalProjection(projection: .init(document: document))
        let data = try projection.encoded()
        let checksum = RelatedContentSourceProjection.checksum(data)
        let prepared = RelatedContentBackgroundPreparation.LexicalDocument(
            fingerprint: document.fingerprint, checksum: checksum, projection: projection)
        #expect(prepared.matches(data, checksum: checksum, fingerprint: document.fingerprint))
        #expect(!prepared.matches(Data([0]), checksum: checksum, fingerprint: document.fingerprint))
        #expect(!prepared.matches(data, checksum: "incorrect", fingerprint: document.fingerprint))
        #expect(!prepared.matches(data, checksum: checksum, fingerprint: DocumentFingerprint(content: "changed")))
        #expect(!prepared.matches(nil, checksum: checksum, fingerprint: document.fingerprint))
        #expect(prepared.estimatedByteCount > projection.estimatedByteCount)
        #expect(projection.estimatedByteCount > projection.scoringDocument.estimatedByteCount)
    }

    private func key(
        _ path: String, source: String = "orchard", roles: [RelatedContentCandidateRole] = [.analysis, .topic, .work], sequence: Int = 1
    ) -> RelatedContentBackgroundPreparation.Key {
        .init(
            seed: .init(noteID: .init(vaultID: vaultID, relativePath: path), source: source),
            generation: .init(triptychID: triptychID, sequence: sequence, sourceManifestHash: "manifest-\(sequence)"), roles: roles)
    }

    private func preparedValue() throws -> RelatedContentBackgroundPreparation.Value {
        let document = NoteDocument(relativePath: "Material.md", rawContent: "orchard geology magnetic compass")
        let projection = RelatedContentLexicalProjection(projection: .init(document: document))
        let checksum = RelatedContentSourceProjection.checksum(try projection.encoded())
        var value = RelatedContentBackgroundPreparation.Value()
        for rowID in 0..<4 {
            value.documents[rowID] = .init(fingerprint: document.fingerprint, checksum: checksum, projection: projection)
        }
        return value
    }
}
