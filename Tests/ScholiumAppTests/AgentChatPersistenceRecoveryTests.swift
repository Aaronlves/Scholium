import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat local persistence recovery", .serialized)
@MainActor
struct AgentChatPersistenceRecoveryTests {
    @Test("A failed draft autosave exposes local recovery whether connected or disconnected", arguments: [false, true])
    func autosaveFailureIsVisible(connected: Bool) async throws {
        try await withController { controller, writer in
            controller.connectionState = connected ? .ready : .disconnected
            controller.account = connected ? "synthetic-account" : nil
            writer.nextFailure = CocoaError(.fileWriteOutOfSpace)
            controller.editDraft("Retain this unsent question. 保留草稿。")
            await controller.scheduledPersistenceTask?.value
            await controller.persistenceTask?.value

            #expect(controller.historySaveError == saveError(.fileWriteOutOfSpace))
            #expect(controller.connectionError == nil)
            #expect(controller.selected?.draft == "Retain this unsent question. 保留草稿。")
            #expect(controller.selected?.messages.isEmpty == true)
            let statuses = status(controller).statuses
            #expect(statuses.first?.id == "historySave")
            #expect(statuses.first?.actions == [.retryHistorySave])
            #expect(statuses.first?.error == controller.historySaveError)
            #expect(statuses.first?.isProgress == false)
            if connected {
                #expect(!statuses.contains { $0.id == "connection" })
            } else {
                #expect(statuses.first(where: { $0.id == "connection" })?.actions == [.connect])
            }

            // The failure belongs to the Triptych's shared archive, not to the
            // selected conversation or the transport's current diagnosis.
            controller.newConversation()
            controller.scheduledPersistenceTask?.cancel()
            controller.scheduledPersistenceTask = nil
            controller.connectionState = connected ? .disconnected : .ready
            controller.account = connected ? nil : "synthetic-account"
            controller.connectionError = "Independent connection failure"
            #expect(status(controller).statuses.contains { $0.id == "historySave" })
            controller.connectionError = nil
            #expect(controller.historySaveError == saveError(.fileWriteOutOfSpace))
        }
    }

    @Test("Retry saves the current snapshot once without resending uncertain or queued input")
    func retrySavesLatestRetainedInput() async throws {
        try await withController { controller, writer in
            let owner = try #require(controller.selectedID)
            controller.editDraft("Earlier unsaved draft")
            writer.nextFailure = CocoaError(.fileWriteOutOfSpace)
            await #expect(throws: CocoaError.self) { try await controller.flushPersistence() }
            let uncertain = AgentChatMessage(id: "uncertain-input", role: .user, text: "Already attempted input")
            let queued = AgentChatMessage(id: "queued-input", role: .user, text: "Wait for explicit delivery")
            let attachment = AgentChatAttachment(
                noteID: UUID(), vaultID: UUID(), relativePath: "Synthetic.md", text: "Exact source passage",
                fingerprint: .init(content: "Exact source passage"))
            controller.editDraft("Latest retained question 中文")
            controller.update(in: owner) {
                $0.attachments = [attachment]
                $0.messages = [uncertain]
                $0.pendingMessageID = uncertain.id
                $0.queuedMessages = [queued]
            }
            let retained = controller.conversations
            let savesBeforeRetry = writer.snapshots.count
            writer.pauseNextSave = true
            controller.retryHistorySave()
            controller.retryHistorySave()
            try await wait { writer.isWaiting }
            #expect(controller.isRetryingHistorySave)
            #expect(status(controller).statuses.first { $0.id == "historySave" }?.isProgress == true)
            #expect(writer.snapshots.count == savesBeforeRetry + 1)
            #expect(writer.snapshots.last == retained)

            controller.retryHistorySave()
            writer.finish()
            try await wait { !controller.isRetryingHistorySave }
            await controller.persistenceTask?.value
            #expect(writer.snapshots.count == savesBeforeRetry + 1)
            #expect(writer.saved == retained && controller.conversations == retained)
            #expect(controller.historySaveError == nil && controller.connectionError == nil)
            #expect(!status(controller).statuses.contains { $0.id == "historySave" })
            controller.retryHistorySave()
            #expect(!controller.isRetryingHistorySave && writer.snapshots.count == savesBeforeRetry + 1)
            #expect(controller.runtime == nil && controller.connectionState == .disconnected)
            #expect(controller.executions[owner]?.isSending == false)
        }
    }

    @Test("An earlier successful retry cannot clear a later queued save failure")
    func orderedSaveOutcomes() async throws {
        try await withController { controller, writer in
            controller.editDraft("Initial draft")
            writer.nextFailure = CocoaError(.fileWriteOutOfSpace)
            await #expect(throws: CocoaError.self) { try await controller.flushPersistence() }

            writer.pauseNextSave = true
            controller.retryHistorySave()
            try await wait { writer.isWaiting }
            controller.editDraft("Newer draft while the retry is saving")
            writer.nextFailure = CocoaError(.fileWriteNoPermission)
            // The debounce enqueues the newer snapshot behind the held write.
            await controller.scheduledPersistenceTask?.value
            let laterSave = controller.persistenceTask
            writer.finish()
            await laterSave?.value
            try await wait { !controller.isRetryingHistorySave }

            #expect(writer.saved.first?.draft == "Initial draft")
            #expect(controller.selected?.draft == "Newer draft while the retry is saving")
            #expect(controller.historySaveError == saveError(.fileWriteNoPermission))
            #expect(status(controller).statuses.first?.error == saveError(.fileWriteNoPermission))
            try await controller.flushPersistence()
            #expect(writer.saved == controller.conversations)
            #expect(controller.historySaveError == nil)
        }
    }

    @Test("Successful saving clears only its own failure and preserves cleanup and transport diagnoses")
    func recoveryKeepsIndependentFailures() async throws {
        try await withController { controller, writer in
            controller.editDraft("Retained draft")
            writer.nextFailure = CocoaError(.fileWriteOutOfSpace)
            await #expect(throws: CocoaError.self) { try await controller.flushPersistence() }
            controller.connectionError = "Independent transport failure"
            controller.materialCleanupError = "Committed deletion still has retained material"
            controller.retryHistorySave()
            try await wait { !controller.isRetryingHistorySave }

            #expect(controller.historySaveError == nil)
            #expect(controller.connectionError == "Independent transport failure")
            #expect(controller.materialCleanupError == "Committed deletion still has retained material")
            let statuses = status(controller).statuses
            #expect(!statuses.contains { $0.id == "historySave" })
            #expect(statuses.first { $0.id == "materialCleanup" }?.actions.isEmpty == true)
            #expect(statuses.first { $0.id == "materialCleanup" }?.error == controller.materialCleanupError)
            #expect(statuses.first { $0.id == "connection" }?.error == controller.connectionError)
        }
    }

    private func status(_ controller: AgentChatController) -> AgentChatConnectionStatus {
        .init(controller: controller, diagnosticsPresentation: .constant(nil))
    }

    private func saveError(_ code: CocoaError.Code) -> String {
        String(localized: "Conversation not saved: \(CocoaError(code).localizedDescription)")
    }

    private func withController(
        operation: @MainActor (AgentChatController, ChatPersistenceSaveGate) async throws -> Void
    ) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/persistence-\(UUID())")
        let suite = "scholium.qa.chat-persistence.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let writer = ChatPersistenceSaveGate()
        let controller = AgentChatController(
            triptychID: UUID(), root: root, workspaceDirectory: { root }, methodDefaults: defaults,
            saveHistory: { try await writer.save($0) },
            toolHandler: { request, _ in
                Issue.record("Saving local history must not invoke a research tool")
                return try! .init(requestID: request.requestID, result: .object([:]))
            })
        defer {
            controller.scheduledPersistenceTask?.cancel()
            writer.finish(failure: CocoaError(.userCancelled))
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try #require(await controller.waitUntilLoaded())
            try await controller.flushPersistence()
            try await operation(controller, writer)
        } catch {
            controller.scheduledPersistenceTask?.cancel()
            writer.finish(failure: CocoaError(.userCancelled))
            await controller.persistenceTask?.value
            throw error
        }
        controller.scheduledPersistenceTask?.cancel()
        await controller.persistenceTask?.value
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Local conversation persistence did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class ChatPersistenceSaveGate {
    var snapshots: [[AgentChatConversation]] = []
    var saved: [AgentChatConversation] = []
    var nextFailure: CocoaError?
    var pauseNextSave = false
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    func save(_ snapshot: [AgentChatConversation]) async throws {
        snapshots.append(snapshot)
        let failure = nextFailure
        nextFailure = nil
        if pauseNextSave {
            pauseNextSave = false
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        if let failure { throw failure }
        saved = snapshot
    }

    func finish(failure: CocoaError? = nil) {
        let waiting = continuation
        continuation = nil
        if let failure { waiting?.resume(throwing: failure) } else { waiting?.resume() }
    }
}
