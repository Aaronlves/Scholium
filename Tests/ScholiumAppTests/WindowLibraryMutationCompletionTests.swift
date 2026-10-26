import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Single Library mutation completion", .timeLimit(.minutes(1)))
@MainActor
struct WindowLibraryMutationCompletionTests {
    @Test(
        "A completed Trash result survives cancellation during window publication",
        arguments: CancellationSource.allCases)
    func completedTrashRetainsSuccess(cancellation: CancellationSource) async throws {
        let fixture = CompletionFixture()
        let publication = CompletionGate()
        fixture.publish = { await publication.hold() }
        let task = Task {
            defer { publication.finish() }
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        defer {
            task.cancel()
            publication.release()
            fixture.controller.unbind()
        }
        await publication.waitUntilEntered()
        try #require(publication.didEnter)
        #expect(fixture.operations.committedPlans == [fixture.preview.id])
        cancellation.apply(to: task, controller: fixture.controller)
        publication.release()

        do { try await task.value } catch {
            Issue.record("A proved commit was reported as failure: \(error)")
        }
        #expect(fixture.completedPlans == [fixture.preview.id])
        #expect(fixture.rejectedPublications == 0)
        #expect(fixture.recoveryRefreshes == 0)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("A genuine Trash refusal remains a failure without a completed receipt")
    func genuineFailureRemainsFailure() async throws {
        let fixture = CompletionFixture()
        fixture.operations.shouldFail = true
        defer { fixture.controller.unbind() }

        await #expect(throws: CocoaError(.fileWriteNoPermission)) {
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        #expect(fixture.operations.committedPlans.isEmpty)
        #expect(fixture.completedPlans.isEmpty)
        #expect(fixture.rejectedPublications == 1)
        #expect(fixture.recoveryRefreshes == 1)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("Cancellation before the authoritative commit still prevents the mutation")
    func cancellationBeforeCommitRemainsCancellation() async throws {
        let fixture = CompletionFixture()
        let admission = CompletionGate()
        fixture.operations.beforeCommit = { await admission.hold() }
        let task = Task {
            defer { admission.finish() }
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        defer {
            task.cancel()
            admission.release()
            fixture.controller.unbind()
        }
        await admission.waitUntilEntered()
        try #require(admission.didEnter)
        task.cancel()
        admission.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.operations.committedPlans.isEmpty)
        #expect(fixture.completedPlans.isEmpty)
        #expect(fixture.rejectedPublications == 1)
        #expect(fixture.recoveryRefreshes == 1)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("A cancelled queued mutation never reaches its operation or erases its predecessor")
    func queuedCancellationPreservesCompletedPredecessor() async throws {
        let fixture = CompletionFixture()
        let publication = CompletionGate()
        fixture.publish = { await publication.hold() }
        let first = Task {
            defer { publication.finish() }
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        let queued = CompletionGate()
        var second: Task<Void, Error>?
        defer {
            first.cancel()
            second?.cancel()
            queued.release()
            publication.release()
            fixture.controller.unbind()
        }
        await publication.waitUntilEntered()
        try #require(publication.didEnter)
        second = Task {
            queued.signalEntry()
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        await queued.waitUntilEntered()
        let pending = try #require(second)
        pending.cancel()
        publication.release()

        try await first.value
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(fixture.operations.enteredPlans == [fixture.preview.id])
        #expect(fixture.operations.committedPlans == [fixture.preview.id])
        #expect(fixture.completedPlans == [fixture.preview.id])
        #expect(fixture.rejectedPublications == 0)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("Rebinding during the editor flush never enters replacement mutation capabilities")
    func rebindDuringFlushStopsAdmission() async throws {
        let fixture = CompletionFixture()
        let gate = CompletionGate()
        fixture.beforeFlush = { await gate.hold() }
        let admitted = fixture.operations
        let replacement = CompletionOperations()
        let task = Task {
            defer { gate.finish() }
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        defer {
            task.cancel()
            gate.release()
            fixture.controller.unbind()
        }
        await gate.waitUntilEntered()
        try #require(gate.didEnter)
        fixture.controller.bind(to: replacement)
        gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(admitted.enteredPlans.isEmpty)
        #expect(replacement.enteredPlans.isEmpty, "An old preview entered a newly bound operation owner")
        #expect(fixture.completedPlans.isEmpty)
    }

    @Test("Library browsing during flush preserves the admitted Trash target")
    func libraryBrowseKeepsAdmission() async throws {
        let fixture = CompletionFixture()
        let gate = CompletionGate()
        fixture.beforeFlush = { await gate.hold() }
        let task = Task {
            defer { gate.finish() }
            try await fixture.controller.executeSystemTrash(fixture.preview)
        }
        defer {
            task.cancel()
            gate.release()
            fixture.controller.unbind()
        }
        await gate.waitUntilEntered()
        try #require(gate.didEnter)
        fixture.browsedVault = RegisteredVault(name: "Other role", role: .draftProject, canonicalPath: "/unused/other-role")
        gate.release()
        try await task.value
        #expect(fixture.operations.enteredPlans == [fixture.preview.id])
        #expect(fixture.operations.committedPlans == [fixture.preview.id])
        #expect(fixture.completedPlans == [fixture.preview.id])
    }

    @Test("A departed batch returns proved completion without overwriting the new binding's retained result")
    func departedBatchRetainsOnlyItsReturnedOutcome() async throws {
        let fixture = CompletionFixture()
        let gate = CompletionGate()
        fixture.publish = { await gate.hold() }
        let task = Task {
            defer { gate.finish() }
            return await fixture.controller.executeNotesSystemTrash(fixture.preview)
        }
        defer {
            task.cancel()
            gate.release()
            fixture.controller.unbind()
        }
        await gate.waitUntilEntered()
        try #require(gate.didEnter)
        fixture.controller.bind(to: CompletionOperations())
        #expect(fixture.controller.lastBatchOutcome == nil)
        gate.release()
        let outcome = await task.value
        #expect(outcome.succeededCount == 1 && outcome.retryTargets.isEmpty)
        #expect(fixture.controller.lastBatchOutcome == nil, "Old completion replaced the new binding's last result")
    }

    @Test("Completed batch Trash preserves cleanup warnings without offering another move")
    func completedTrashCleanupIsNotRetried() async throws {
        let fixture = CompletionFixture()
        defer { fixture.controller.unbind() }
        let preview = fixture.preview
        let plan = SystemTrashDeletionPlan(
            preview: preview,
            sourceReceipts: preview.sources.map {
                .init(targetID: $0.id, progress: .movedToSystemTrash, resultingTrashPath: "/synthetic/Trash/Note.md")
            })
        fixture.operations.pendingCleanupRecovery = .init(
            id: preview.id, triptychID: preview.triptychID, createdAt: Date(),
            failure: "Synthetic cleanup failure", files: [], systemTrashDeletionPlan: plan)
        fixture.operations.derivedRefreshWarning = "Synthetic derived refresh failure"
        let outcome = await fixture.controller.executeNotesSystemTrash(preview)
        #expect(outcome.succeededCount == preview.affectedNoteIDs.count)
        #expect(outcome.items.allSatisfy { $0.status == .succeeded })
        #expect(outcome.recoveryRequired && !outcome.isComplete && outcome.retryTargets.isEmpty)
        #expect(outcome.warnings == [ScholiumL10n.dynamicString(SystemTrashCleanupPendingError.message), "Synthetic derived refresh failure"])
        #expect(fixture.completedPlans == [preview.id] && fixture.rejectedPublications == 0)
    }

    @Test(
        "A completed move batch cannot publish into replacement capabilities with the same assignment and vault",
        arguments: [false, true])
    func completedMoveBatchRejectsReplacementBinding(unbindFirst: Bool) async throws {
        let fixture = CompletionFixture()
        let committed = CompletionGate()
        fixture.operations.afterMoveCommit = { await committed.hold() }
        let target = NoteMutationTarget(
            documentID: .init(vaultID: fixture.vault.id, relativePath: "Note.md"),
            stableNoteID: UUID(), revision: DocumentFingerprint(content: "Exact source\n"))
        let request = LibraryNoteBatchRequest(
            assignmentID: fixture.assignmentID, vaultID: fixture.vault.id, targets: [target])
        let task = Task {
            defer { committed.finish() }
            return await fixture.controller.moveNotes(request, toFolder: "Moved")
        }
        defer {
            task.cancel()
            committed.release()
            fixture.controller.unbind()
        }
        await committed.waitUntilEntered()
        try #require(committed.didEnter)
        #expect(fixture.operations.committedMoveTargets == [target.documentID])
        let previousBinding = fixture.controller.bindingID
        let replacement = CompletionOperations()
        if unbindFirst { fixture.controller.unbind() }
        fixture.controller.bind(to: replacement)
        #expect(fixture.controller.bindingID != previousBinding)
        committed.release()

        let outcome = await task.value
        #expect(outcome.items.map(\.status) == [.succeeded])
        #expect(outcome.retryTargets.isEmpty)
        #expect(replacement.committedMoveTargets.isEmpty)
        #expect(fixture.movePublications == 0, "An old durable result was presented through replacement window capabilities")
        #expect(fixture.controller.lastBatchOutcome == nil)
    }

    @Test("A departed move failure retains its result without refreshing replacement recovery state")
    func departedMoveFailureDoesNotRefreshReplacementRecovery() async throws {
        let fixture = CompletionFixture()
        let gate = CompletionGate()
        fixture.operations.shouldFailMove = true
        fixture.operations.beforeMoveFailure = { await gate.hold() }
        let target = NoteMutationTarget(
            documentID: .init(vaultID: fixture.vault.id, relativePath: "Note.md"),
            stableNoteID: UUID(), revision: DocumentFingerprint(content: "Exact source\n"))
        let request = LibraryNoteBatchRequest(
            assignmentID: fixture.assignmentID, vaultID: fixture.vault.id, targets: [target])
        let task = Task {
            defer { gate.finish() }
            return await fixture.controller.moveNotes(request, toFolder: "Moved")
        }
        defer {
            task.cancel()
            gate.release()
            fixture.controller.unbind()
        }
        await gate.waitUntilEntered()
        try #require(gate.didEnter)
        let replacement = CompletionOperations()
        fixture.controller.bind(to: replacement)
        gate.release()
        let outcome = await task.value
        let item = try #require(outcome.items.first)
        if case .failed(let message) = item.status {
            #expect(message == CocoaError(.fileWriteNoPermission).localizedDescription)
        } else {
            Issue.record("The admitted operation's actual failure was discarded")
        }
        #expect(fixture.operations.committedMoveTargets.isEmpty)
        #expect(replacement.committedMoveTargets.isEmpty)
        #expect(fixture.movePublications == 0 && fixture.recoveryRefreshes == 0)
        #expect(fixture.controller.lastBatchOutcome == nil)
    }

    enum CancellationSource: CaseIterable, Sendable {
        case none, caller, controller

        @MainActor
        func apply(to task: Task<Void, Error>, controller: WindowLibraryMutationController) {
            switch self {
            case .none: break
            case .caller: task.cancel()
            case .controller: controller.cancelAll()
            }
        }
    }
}

@MainActor
private final class CompletionGate {
    private let arrival = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var didEnter = false

    func signalEntry() {
        didEnter = true
        arrival.continuation.yield(())
    }

    func hold() async {
        guard !released else { return }
        await withCheckedContinuation {
            continuation = $0
            signalEntry()
        }
    }

    func waitUntilEntered() async {
        for await _ in arrival.stream { break }
    }

    func finish() { arrival.continuation.finish() }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
        finish()
    }
}

@MainActor
private final class CompletionFixture {
    let assignmentID = UUID()
    let vault = RegisteredVault(
        name: "Disposable", role: .topicKnowledge, canonicalPath: "/unused/completion-fixture")
    let operations = CompletionOperations()
    var completedPlans: [UUID] = []
    var rejectedPublications = 0
    var recoveryRefreshes = 0
    var movePublications = 0
    var publish: @MainActor () async -> Void = {}
    var beforeFlush: @MainActor () async -> Void = {}
    var browsedVault: RegisteredVault?

    lazy var preview = SystemTrashDeletionPreview(
        triptychID: assignmentID,
        sources: [
            .init(
                vaultID: vault.id, relativePath: "Note.md", kind: .note,
                notes: [
                    .init(
                        noteID: UUID(), relativePath: "Note.md",
                        expectedRevision: DocumentFingerprint(content: "Exact source\n"))
                ])
        ])
    lazy var controller: WindowLibraryMutationController = {
        let controller = WindowLibraryMutationController(
            dependencies: .init(
                context: { [unowned self] in
                    .init(assignmentID: assignmentID, vault: browsedVault ?? vault, sourceScope: .library)
                },
                enqueueDocumentTransition: { _, _, _ in Issue.record("Unexpected creation") },
                flushEditors: { [unowned self] _ in await beforeFlush() }, flushActiveTarget: { _ in },
                expectedRevision: { $0.revision }, captureBatchTargets: { $0 },
                committedNoteCreated: { _, _ in }, committedFolderCreated: { _ in },
                committedFolderMoved: { _ in }, committedNoteDuplicated: { _, _, _ in },
                committedNoteMoved: { [unowned self] _, _, isCurrent in
                    if isCurrent() { movePublications += 1 }
                },
                committedSystemTrash: { [unowned self] preview, outcome, isCurrent in
                    guard isCurrent() else { return }
                    if let outcome {
                        #expect(outcome.committedValue.planID == preview.id)
                        #expect(Set(outcome.committedValue.noteIDs) == preview.affectedNoteIDs)
                        completedPlans.append(outcome.committedValue.planID)
                        await publish()
                    } else {
                        rejectedPublications += 1
                    }
                },
                importedDocumentsCommitted: { _ in }, presentImportOutcome: { _ in },
                presentSystemTrash: { _ in },
                clearPresentedAlert: {}, reportError: { Issue.record(Comment(rawValue: $0)) },
                reportInformation: { _ in },
                refreshTransactionRecovery: { [unowned self] in recoveryRefreshes += 1 }))
        controller.bind(to: operations)
        return controller
    }()
}

@MainActor
final class CompletionOperations: LibraryMutationUseCases {
    var shouldFail = false
    var pendingCleanupRecovery: TriptychMutationRecoveryRecord?
    var derivedRefreshWarning: String?
    var beforeCommit: @MainActor () async -> Void = {}
    var afterTrashCommit: @MainActor () async -> Void = {}
    var enteredPlans: [UUID] = []
    var committedPlans: [UUID] = []
    var committedMoveTargets: [VaultQualifiedNoteID] = []
    var afterMoveCommit: @MainActor () async -> Void = {}
    var shouldFailMove = false
    var beforeMoveFailure: @MainActor () async -> Void = {}

    func moveToSystemTrash(_ preview: SystemTrashDeletionPreview) async throws
        -> WorkspaceMutationOutcome<SystemTrashDeletionCommit>
    {
        enteredPlans.append(preview.id)
        await beforeCommit()
        try Task.checkCancellation()
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        committedPlans.append(preview.id)
        await afterTrashCommit()
        return .init(
            committedValue: .init(
                planID: preview.id, noteIDs: Array(preview.affectedNoteIDs),
                originalRelativePaths: preview.sources.map(\.relativePath), resultingTrashPaths: [],
                pendingCleanupRecovery: pendingCleanupRecovery),
            derivedRefreshWarning: derivedRefreshWarning)
    }

    func importMarkdown(at sourceURL: URL, intoVault vaultID: UUID) async throws
        -> WorkspaceMutationOutcome<NoteDocument>
    {
        throw CocoaError(.featureUnsupported)
    }
    func createManagedNote(_ request: ManagedNoteCreationRequest) async throws
        -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit>
    {
        throw CocoaError(.featureUnsupported)
    }
    func createUntitledFolder(inVault vaultID: UUID, parentRelativePath: String?) async throws
        -> WorkspaceMutationOutcome<VaultRelativeFolderPath>
    {
        throw CocoaError(.featureUnsupported)
    }
    func moveFolder(
        inVault vaultID: UUID, from sourceRelativePath: String, to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func prepareFolderSystemTrash(inVault vaultID: UUID, relativePath: String) async throws
        -> SystemTrashDeletionPreview
    {
        throw CocoaError(.featureUnsupported)
    }
    func duplicate(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws
        -> WorkspaceMutationOutcome<NoteDocument>
    {
        throw CocoaError(.featureUnsupported)
    }
    func move(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws
        -> WorkspaceMutationOutcome<TriptychMoveCommit>
    {
        if shouldFailMove {
            await beforeMoveFailure()
            throw CocoaError(.fileWriteNoPermission)
        }
        committedMoveTargets.append(target.documentID)
        // A proved source operation may finish publication after its caller is
        // cancelled. This gate intentionally does not revoke that receipt.
        await afterMoveCommit()
        return .init(
            committedValue: .init(
                movedNote: target.documentID,
                destination: .init(vaultID: target.documentID.vaultID, relativePath: destinationRelativePath),
                previousRevision: target.revision, committedRevision: target.revision,
                graphGeneration: 1, rewrites: []))
    }
    func prepareSystemTrash(_ target: NoteMutationTarget) async throws -> SystemTrashDeletionPreview {
        throw CocoaError(.featureUnsupported)
    }
    func recoverInterruptedTransactions() async throws -> [String] { [] }
}
