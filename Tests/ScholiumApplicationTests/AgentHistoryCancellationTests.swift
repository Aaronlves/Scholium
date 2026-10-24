import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Public history cancellation must preserve source and receipt integrity.
@Suite("Agent history capability cancellation", .serialized)
struct AgentHistoryCancellationTests {
    @Test(
        "A canceled history capability read preserves evidence; a later active read still validates it",
        arguments: [false, true])
    func canceledHistoryRead(damaged: Bool) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    assignments: [fixture.assignment], defaultWorkspaceID: fixture.assignment.id)))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let snapshot = try await handle.snapshot()
            let note = try #require(snapshot.document(id: fixture.analysisNoteID))
            let noteID = try #require(note.stableIdentity.resolvedID)
            let sourceURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
            let originalSource = try Data(contentsOf: sourceURL)
            let after = Data((String(decoding: originalSource, as: UTF8.self) + "\nHistorical synthetic edit.\n").utf8)
            let services = await handle.services
            let receipt = try await services.agentChangeStore.prepare(
                operation: .update, noteID: noteID, role: .sourceCorpus,
                originalRelativePath: fixture.analysisNoteID.relativePath,
                finalRelativePath: fixture.analysisNoteID.relativePath,
                beforeData: originalSource, afterData: after)
            _ = try await services.agentChangeStore.confirm(
                id: receipt.id, observedAfterFingerprint: .init(data: after))
            let receiptURL = fixture.applicationSupportURL
                .appendingPathComponent("Triptychs/\(fixture.assignment.id.uuidString)/agent-changes-v1")
                .appendingPathComponent(receipt.id.uuidString.lowercased() + ".json")
            if damaged {
                var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
                object["unsupported_future_authority"] = true
                try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: receiptURL)
            }
            let originalReceipt = try Data(contentsOf: receiptURL)
            let operations = handle.agentCollaboration
            let canceled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await operations.agentChanges()
            }
            await #expect(throws: CancellationError.self) { _ = try await canceled.value }
            #expect(try Data(contentsOf: receiptURL) == originalReceipt)
            #expect(try Data(contentsOf: sourceURL) == originalSource)

            if damaged {
                do {
                    _ = try await operations.agentChanges()
                    Issue.record("An active history read accepted an unsupported persisted receipt")
                } catch let error as AgentChangeError {
                    guard case .invalid = error else {
                        Issue.record("Expected receipt-integrity refusal, received \(error)")
                        await runtime.shutdown()
                        return
                    }
                }
            } else {
                let history = try await operations.agentChanges()
                #expect(history.count == 1 && history.first?.id == receipt.id)
                #expect(history.first?.state == .confirmed)
            }
            #expect(try Data(contentsOf: receiptURL) == originalReceipt)
            #expect(try Data(contentsOf: sourceURL) == originalSource)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
