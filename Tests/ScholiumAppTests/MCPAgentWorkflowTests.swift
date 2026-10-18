import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

extension MCPAppBridgeRequestRouterTests {
    @Test("Revision-bound Note reads refuse stale discovery and continuation before returning source")
    func revisionBoundNoteReads() async throws {
        let source = "\u{feff}---\r\ntitle: 'Exact' # retain\r\n---\r\n原文 e\u{301} 📝\r\nSecond page.\r\n"
        try await withAgentWorkflowFixture(source: source) { fixture in
            let router = MCPAppBridgeRequestRouter(
                runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
            let scope: [String: MCPJSONValue] = [
                "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            ]
            let first = try result(await router.handle(.init(tool: .readNote, arguments: scope.merging(["line_count": .integer(4)]) { _, new in new })))
            let fingerprint = try #require(first["fingerprint"])
            var continuation = scope.merging([
                "start_line": try #require(first["next_line"]), "expected_fingerprint": fingerprint,
            ]) { _, new in new }
            let same = await router.handle(.init(tool: .readNote, arguments: continuation))
            #expect(same.error == nil)
            #expect(same.result?.objectValue?["source"] == .string("Second page.\r\n"))

            let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
            let changed = source.replacingOccurrences(of: "Second page.", with: "Concurrent revision.")
            try Data(changed.utf8).write(to: file)
            let stale = await router.handle(.init(tool: .readNote, arguments: continuation))
            #expect(stale.error?.code == .staleRevision)
            #expect(stale.result == nil)
            continuation["expected_fingerprint"] = nil
            let fresh = try result(await router.handle(.init(tool: .readNote, arguments: continuation)))
            #expect(fresh["source"] == .string("Concurrent revision.\r\n"))
            continuation["expected_fingerprint"] = fresh["fingerprint"]
            #expect(try result(await router.handle(.init(tool: .readNote, arguments: continuation))) == fresh)
            #expect(try Data(contentsOf: file) == Data(changed.utf8))
            let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
            #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        }
    }

    @Test("Malformed read fingerprints fail before workspace reconciliation")
    func malformedReadFingerprints() async throws {
        var reconciliations = 0
        let runtime = WorkspaceRuntime(configuration: .live(.init(applicationSupportURL: URL(fileURLWithPath: "/nonexistent"))))
        let router = MCPAppBridgeRequestRouter(
            runtime: runtime, flushEditors: { _ in reconciliations += 1 }, openTriptychs: { [] })
        for value: MCPJSONValue in [
            .null, .string("sha256"), .object(["sha256": .string(String(repeating: "A", count: 64)), "byte_count": .integer(1)]),
            .object(["sha256": .string(String(repeating: "a", count: 64)), "byte_count": .integer(-1)]),
            .object(["sha256": .string(String(repeating: "a", count: 64)), "byte_count": .integer(1), "extra": .bool(true)]),
        ] {
            let response = await router.handle(.init(tool: .readNote, arguments: [
                "triptych_id": .string(UUID().uuidString), "note_id": .string(UUID().uuidString), "expected_fingerprint": value,
            ]))
            #expect(response.error?.code == .invalidRequest)
            #expect(response.result == nil)
        }
        #expect(reconciliations == 0)
        await runtime.shutdown()
    }

    private func withAgentWorkflowFixture(
        source: String, _ body: @MainActor (Fixture) async throws -> Void
    ) async throws {
        let fixture = try await Fixture.make(exactAnalysis: source)
        do {
            try await body(fixture)
        } catch {
            await fixture.runtime.shutdown()
            try FileManager.default.trashItem(at: fixture.root, resultingItemURL: nil)
            throw error
        }
        await fixture.runtime.shutdown()
        try FileManager.default.trashItem(at: fixture.root, resultingItemURL: nil)
    }
}
