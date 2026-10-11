import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window-owned Markdown import lifecycle", .serialized)
@MainActor
struct WindowLibraryImportLifecycleTests {
    @Test("Late cancelled import cannot erase its replacement or publish an obsolete alert", arguments: [false, true])
    func replacementKeepsAdmissionAndCancellation(oldCommitFinishes: Bool) async throws {
        let fixture = ImportFixture()
        let first = ImportGate()
        let second = ImportGate()
        fixture.operations.gates = ["First.md": first, "Second.md": second]
        fixture.operations.commitsDespiteCancellation = oldCommitFinishes ? ["First.md"] : []
        defer {
            fixture.controller.unbind()
            fixture.operations.releaseAll()
        }
        do {
            fixture.controller.requestMarkdownImport([fixture.url("First.md")])
            try await fixture.wait { first.isWaiting }
            fixture.context = .init(assignmentID: UUID(), vault: fixture.vault, sourceScope: .library)
            fixture.controller.bind(to: fixture.operations)
            fixture.controller.requestMarkdownImport([fixture.url("Second.md")])
            try await fixture.wait { second.isWaiting }
            first.release()
            try await fixture.wait { fixture.operations.returned.contains("First.md") }
            // Allow the resumed wrapper to settle after the fake operation returns.
            for _ in 0..<3 { await Task.yield() }

            #expect(fixture.controller.hasActiveLibraryMutation)
            #expect(fixture.outcomes.isEmpty && fixture.errors.isEmpty)
            #expect((fixture.operations.committed["First.md"] != nil) == oldCommitFinishes)
            fixture.controller.requestMarkdownImport([fixture.url("Third.md")])
            #expect(fixture.information.count == 1)
            fixture.controller.unbind()
            second.release()
            try await fixture.wait { fixture.operations.returned.contains("Second.md") }
            for _ in 0..<3 { await Task.yield() }
            #expect(fixture.operations.cancelled["Second.md"] == true)
            #expect(fixture.operations.entered == ["First.md", "Second.md"])
            #expect(fixture.outcomes.isEmpty && fixture.errors.isEmpty)
            #expect(!fixture.controller.hasActiveLibraryMutation)
        } catch {
            fixture.controller.unbind()
            fixture.operations.releaseAll()
            try? await fixture.wait { fixture.operations.active == 0 && !fixture.controller.hasActiveLibraryMutation }
            throw error
        }
    }

    @Test("The current import retains exact committed source and all warning classes")
    func currentImportRetainsCommittedWarnings() async throws {
        let fixture = ImportFixture()
        fixture.refreshFails = true
        defer {
            fixture.controller.unbind()
            fixture.operations.releaseAll()
        }
        fixture.controller.requestMarkdownImport([fixture.url("Current.md")])
        try await fixture.wait { !fixture.outcomes.isEmpty }
        let outcome = try #require(fixture.outcomes.first)
        #expect(outcome.documents.first?.sourceBytes == Data(ImportOperations.source.utf8))
        #expect(outcome.derivedRefreshWarnings == ["Derived refresh warning"])
        #expect(outcome.identityRecoveryWarnings == ["Identity recovery warning"])
        #expect(outcome.presentationWarning == ImportFixture.Failure.refresh.localizedDescription)
        #expect(outcome.failures.isEmpty && fixture.errors.isEmpty)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("Cancellation after the final authoritative commit retains a truthful batch outcome")
    func cancelledFinalCommitRetainsTruthfulOutcome() async throws {
        let fixture = ImportFixture()
        let gate = ImportGate()
        fixture.operations.gates["Committed.md"] = gate
        fixture.operations.commitsDespiteCancellation = ["Committed.md"]
        let task = Task { try await fixture.controller.importMarkdownFiles([fixture.url("Committed.md")]) }
        defer {
            task.cancel()
            gate.release()
            fixture.controller.unbind()
        }
        do {
            try await fixture.wait { gate.isWaiting }
            task.cancel()
            gate.release()
            let outcome = try await task.value
            #expect(outcome.documents.first?.sourceBytes == Data(ImportOperations.source.utf8))
            #expect(outcome.derivedRefreshWarnings == ["Derived refresh warning"])
            #expect(outcome.identityRecoveryWarnings == ["Identity recovery warning"])
            #expect(fixture.operations.cancelled["Committed.md"] == true)
            #expect(fixture.operations.committed["Committed.md"] != nil)
        } catch {
            task.cancel()
            gate.release()
            _ = try? await task.value
            throw error
        }
    }
}

@MainActor
private final class ImportGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class ImportFixture {
    enum Failure: LocalizedError {
        case refresh
        var errorDescription: String? { "Fixture presentation refresh failure" }
    }
    let vault = RegisteredVault(name: "In-memory import", role: .topicKnowledge, canonicalPath: "/unused/import-fixture")
    let operations = ImportOperations()
    var context: WindowLibraryMutationContext?
    var outcomes: [WindowMarkdownImportBatchOutcome] = []
    var errors: [String] = []
    var information: [String] = []
    var refreshFails = false
    lazy var controller: WindowLibraryMutationController = {
        let controller = WindowLibraryMutationController(
            dependencies: .init(
                context: { [unowned self] in context }, enqueueDocumentTransition: { _, _, _ in },
                flushEditors: { _ in }, flushActiveTarget: { _ in }, expectedRevision: { $0.revision }, captureBatchTargets: { $0 },
                committedNoteCreated: { _, _ in }, committedFolderCreated: { _ in }, committedFolderMoved: { _ in },
                committedNoteDuplicated: { _, _, _ in }, committedNoteMoved: { _, _ in }, committedSystemTrash: { _, _ in },
                importedDocumentsCommitted: { [unowned self] _ in if refreshFails { throw Failure.refresh } },
                presentImportOutcome: { [unowned self] in outcomes.append($0) }, presentSystemTrash: { _ in }, clearPresentedAlert: {},
                reportError: { [unowned self] in errors.append($0) }, reportInformation: { [unowned self] in information.append($0) },
                refreshTransactionRecovery: {}))
        controller.bind(to: operations)
        return controller
    }()

    init() { context = .init(assignmentID: UUID(), vault: vault, sourceScope: .library) }
    func url(_ name: String) -> URL { URL(fileURLWithPath: "/unused/import-fixture/" + name) }
    func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "In-memory import did not reach its owned gate or completion")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class ImportOperations: LibraryMutationUseCases {
    static let source = "\u{FEFF}Exact imported 中文 😀 e\u{301}\r\n"
    var gates: [String: ImportGate] = [:]
    var commitsDespiteCancellation: Set<String> = []
    var entered: [String] = []
    var returned: Set<String> = []
    var cancelled: [String: Bool] = [:]
    var committed: [String: NoteDocument] = [:]
    var active = 0
    func releaseAll() { gates.values.forEach { $0.release() } }

    func importMarkdown(at sourceURL: URL, intoVault vaultID: UUID) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let name = sourceURL.lastPathComponent
        entered.append(name)
        active += 1
        defer {
            active -= 1
            returned.insert(name)
        }
        await gates[name]?.waitForRelease()
        cancelled[name] = Task.isCancelled
        if !commitsDespiteCancellation.contains(name) { try Task.checkCancellation() }
        let document = NoteDocument(relativePath: name, rawContent: Self.source)
        committed[name] = document
        return .init(committedValue: document, derivedRefreshWarning: "Derived refresh warning", identityRecoveryWarning: "Identity recovery warning")
    }

    func createManagedNote(_ request: ManagedNoteCreationRequest) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func createUntitledFolder(inVault vaultID: UUID, parentRelativePath: String?) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
        throw CocoaError(.featureUnsupported)
    }
    func prepareFolderSystemTrash(inVault vaultID: UUID, relativePath: String) async throws -> SystemTrashDeletionPreview {
        throw CocoaError(.featureUnsupported)
    }
    func duplicate(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        throw CocoaError(.featureUnsupported)
    }
    func move(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func moveFolder(inVault vaultID: UUID, from sourceRelativePath: String, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<
        FolderMoveCommit
    > {
        throw CocoaError(.featureUnsupported)
    }
    func prepareSystemTrash(_ target: NoteMutationTarget) async throws -> SystemTrashDeletionPreview { throw CocoaError(.featureUnsupported) }
    func moveToSystemTrash(_ preview: SystemTrashDeletionPreview) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func recoverInterruptedTransactions() async throws -> [String] { [] }
}
