import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Bounded writing projection reuse")
struct WritingCompletionMemoTests {
    @Test("Revision changes and removed membership revoke reusable prose; LRU capacity never changes query results")
    func revisionMembershipAndEviction() throws {
        let vault = UUID()
        let first = VaultQualifiedNoteID(vaultID: vault, relativePath: "First.md")
        let second = VaultQualifiedNoteID(vaultID: vault, relativePath: "Second.md")
        let a = NoteDocument(relativePath: first.relativePath, rawContent: "Responsibility concerns reasons.")
        let b = NoteDocument(relativePath: second.relativePath, rawContent: "Responsiveness concerns examples.")
        var memo = WritingCompletionProjectionMemo(maximumEntries: 1)
        #expect(try !memo.vocabulary(for: first, document: a).reused)
        let hit = try memo.vocabulary(for: first, document: a)
        #expect(hit.reused)
        #expect(try hit.value.terms(matching: "Responsib").contains("Responsibility"))
        #expect(try !memo.vocabulary(for: second, document: b).reused)
        #expect(memo.entryCount == 1)
        #expect(try !memo.vocabulary(for: first, document: a).reused)
        let revised = NoteDocument(relativePath: first.relativePath, rawContent: "Replacement concerns reasons.")
        let changed = try memo.vocabulary(for: first, document: revised)
        #expect(!changed.reused)
        #expect(try changed.value.terms(matching: "Responsib").isEmpty)
        #expect(try changed.value.terms(matching: "Replac").contains("Replacement"))
        memo.retain([first: a.fingerprint])
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
        _ = try memo.vocabulary(for: second, document: b)
        memo.retain([:])
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
    }

    @Test("Accounting budget, oversize bypass and zero capacity preserve derived results without retained growth")
    func accountingAndOversize() throws {
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Synthetic.md")
        let document = NoteDocument(relativePath: note.relativePath, rawContent: "Responsibility concerns reasons.")
        let prepared = try WritingCompletionVocabulary(document: document)
        let cost = prepared.estimatedByteCount
        #expect(cost > 0)
        var memo = WritingCompletionProjectionMemo(maximumEstimatedBytes: cost)
        let accepted = try memo.vocabulary(for: note, document: document)
        #expect(!accepted.reused && memo.estimatedByteCount == cost)
        #expect(try memo.vocabulary(for: note, document: document).reused)
        let bigger = NoteDocument(relativePath: note.relativePath, rawContent: String(repeating: "Responsibility concerns reasons.\n\n", count: 50))
        let skipped = try memo.vocabulary(for: note, document: bigger)
        #expect(!skipped.reused && memo.entryCount == 0 && memo.estimatedByteCount == 0)
        #expect(try skipped.value.terms(matching: "Responsib").contains("Responsibility"))
        var disabled = WritingCompletionProjectionMemo(maximumEntries: 0)
        #expect(try disabled.vocabulary(for: note, document: document).value.terms(matching: "Responsib") == prepared.terms(matching: "Responsib"))
        #expect(disabled.entryCount == 0 && disabled.estimatedByteCount == 0)
        memo.clear()
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
    }
    @Test("A lookup suspended after source reading cannot repopulate a shut-down runtime")
    func suspendedReadShutdown() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/writing-completion-shutdown-tests/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let noteURL = topics.appendingPathComponent("Synthetic.md")
        let bytes = Data("Responsibility concerns reasons.".utf8)
        try bytes.write(to: noteURL)
        let support = root.appendingPathComponent("state")
        let registration = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        let assignment: TriptychAssignment
        do {
            assignment = try await registration.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Synthetic shutdown fixture"
            ).assignment
        } catch {
            await registration.shutdown()
            throw error
        }
        await registration.shutdown()
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: assignment.id)
            let gate = WritingMemoReadGate()
            await handle.setWritingCompletionPostSourceReadBarrierForTesting { await gate.hold() }
            let pending = Task {
                do {
                    let value = try await handle.discovery.writingCompletions(matching: "Responsib")
                    await gate.finished()
                    return value
                } catch {
                    await gate.finished()
                    throw error
                }
            }
            do {
                try await gate.waitForRead()
                await handle.shutdown()
                await gate.release()
                await #expect(throws: (any Error).self) { try await pending.value }
                #expect(await handle.writingCompletionMemo.entryCount == 0)
                #expect(await handle.writingCompletionMemo.estimatedByteCount == 0)
                #expect(await handle.lastWritingCompletionMeasurement == nil)
                #expect(try Data(contentsOf: noteURL) == bytes)
            } catch {
                await gate.release()
                _ = try? await pending.value
                throw error
            }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }

}

private actor WritingMemoReadGate {
    private var entered = false
    private var released = false
    private var ended = false
    private var arrival: CheckedContinuation<Void, Error>?
    private var held: CheckedContinuation<Void, Never>?
    func hold() async {
        entered = true
        arrival?.resume()
        arrival = nil
        if !released { await withCheckedContinuation { held = $0 } }
    }
    func waitForRead() async throws {
        if entered { return }
        if ended { throw CocoaError(.fileReadUnknown) }
        try await withCheckedThrowingContinuation { arrival = $0 }
    }
    func release() {
        released = true
        held?.resume()
        held = nil
    }
    func finished() {
        ended = true
        if !entered {
            arrival?.resume(throwing: CocoaError(.fileReadUnknown))
            arrival = nil
        }
    }
}
