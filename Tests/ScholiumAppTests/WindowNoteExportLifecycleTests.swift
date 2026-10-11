import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window-owned Note export lifecycle", .serialized)
@MainActor
struct WindowNoteExportLifecycleTests {
    @Test("Committed close suppresses noncooperative late success and failure", arguments: [false, true])
    func committedCloseSuppressesLateCompletion(fails: Bool) async throws {
        let fixture = ExportFixture()
        let gate = ExportGate()
        try await fixture.run(gate) {
            #expect(fixture.start(gate))
            try await fixture.wait { gate.isWaiting }
            fixture.lifecycle.close()
            #expect(!fixture.lifecycle.isPreparing)
            #expect(fixture.lifecycle.phase == .closed)
            #expect(!fixture.start(ExportGate()))
            gate.complete(fails ? .failure(ExportFixture.Failure.acquire) : .success(fixture.payload("Late")))
            try await fixture.wait { gate.didReturn }
            #expect(gate.wasCancelledOnReturn)
            #expect(fixture.payloads.isEmpty && fixture.presentations.isEmpty && fixture.errors.isEmpty)
            #expect(fixture.lifecycle.presentation == nil)
            #expect(fixture.lifecycle.phase == .closed)
        }
    }

    @Test("A cancelled request cannot clear or publish over its replacement", arguments: [false, true])
    func cancelledPreparationCannotDisplaceReplacement(fails: Bool) async throws {
        let fixture = ExportFixture()
        let first = ExportGate()
        let second = ExportGate()
        try await fixture.run(first, second) {
            #expect(fixture.start(first))
            try await fixture.wait { first.isWaiting }
            fixture.lifecycle.cancel()
            #expect(fixture.start(second))
            try await fixture.wait { second.isWaiting }
            let replacementPhase = fixture.lifecycle.phase
            first.complete(fails ? .failure(ExportFixture.Failure.acquire) : .success(fixture.payload("Old")))
            try await fixture.wait { first.didReturn }
            #expect(first.wasCancelledOnReturn)
            #expect(fixture.lifecycle.phase == replacementPhase && fixture.lifecycle.isPreparing)
            #expect(fixture.payloads.isEmpty && fixture.errors.isEmpty)
            second.complete(.success(fixture.payload("Current")))
            try await fixture.wait { !fixture.presentations.isEmpty }
            #expect(fixture.payloads.map(\.title) == ["Current"])
            #expect(!second.wasCancelledOnReturn)
            #expect(!fixture.lifecycle.isPreparing)
        }
    }

    @Test("Current publication retains exact payload and matching auxiliary close ownership")
    func currentSuccessPreservesPayloadAndCloseIdentity() async throws {
        let fixture = ExportFixture()
        let first = ExportGate()
        let second = ExportGate()
        try await fixture.run(first, second) {
            let payload = fixture.payload("First")
            #expect(fixture.start(first))
            try await fixture.wait { first.isWaiting }
            #expect(!fixture.start(ExportGate()))
            first.complete(.success(payload))
            try await fixture.wait { fixture.presentations.count == 1 }
            let published = try #require(fixture.payloads.first)
            #expect(published.document.sourceBytes == Data(ExportFixture.source.utf8))
            #expect(published.document.relativePath == payload.document.relativePath)
            #expect(published.document.fingerprint == payload.document.fingerprint)
            #expect(published.title == payload.title && published.embeddedImages == payload.embeddedImages)
            #expect(published.excludedRoots == payload.excludedRoots)
            #expect(published.appearance == payload.appearance && published.colorScheme == payload.colorScheme)
            let firstPresentation = fixture.presentations[0]
            #expect(fixture.lifecycle.presentation === firstPresentation)
            #expect(!fixture.start(ExportGate()))
            firstPresentation.close()
            #expect(fixture.lifecycle.phase == .idle && fixture.lifecycle.presentation == nil)
            #expect(fixture.start(second))
            try await fixture.wait { second.isWaiting }
            second.complete(.success(fixture.payload("Second")))
            try await fixture.wait { fixture.presentations.count == 2 }
            let secondPresentation = fixture.presentations[1]
            firstPresentation.replayCloseNotification()
            #expect(fixture.lifecycle.presentation === secondPresentation)
            fixture.lifecycle.close()
            fixture.lifecycle.close()
            #expect(firstPresentation.closeCount == 1 && secondPresentation.closeCount == 1)
            #expect(fixture.lifecycle.phase == .closed && fixture.lifecycle.presentation == nil)
            #expect(fixture.errors.isEmpty)
        }
    }

    @Test("Current errors permit retry while cancellation stays quiet", arguments: [false, true])
    func currentFailureSupportsRetry(isCancellation: Bool) async throws {
        let fixture = ExportFixture()
        let first = ExportGate()
        let retry = ExportGate()
        try await fixture.run(first, retry) {
            #expect(fixture.start(first))
            try await fixture.wait { first.isWaiting }
            first.complete(.failure(isCancellation ? CancellationError() : ExportFixture.Failure.acquire))
            try await fixture.wait { first.didReturn }
            #expect(fixture.lifecycle.phase == .idle && !fixture.lifecycle.isPreparing)
            #expect(fixture.errors == (isCancellation ? [] : [ExportFixture.Failure.acquire.localizedDescription]))
            #expect(fixture.start(retry))
            try await fixture.wait { retry.isWaiting }
            retry.complete(.success(fixture.payload("Retry")))
            try await fixture.wait { !fixture.presentations.isEmpty }
            #expect(fixture.payloads.map(\.title) == ["Retry"])
        }
    }

    @Test("Expired originating lifetime suppresses completion even without cooperative cancellation", arguments: [false, true])
    func expiredLifetimeSuppressesLateCompletion(fails: Bool) async throws {
        let fixture = ExportFixture()
        let gate = ExportGate()
        let retry = ExportGate()
        try await fixture.run(gate, retry) {
            #expect(fixture.start(gate))
            try await fixture.wait { gate.isWaiting }
            fixture.isCurrent = false
            gate.complete(fails ? .failure(ExportFixture.Failure.acquire) : .success(fixture.payload("Expired")))
            try await fixture.wait { gate.didReturn }
            #expect(!gate.wasCancelledOnReturn)
            #expect(fixture.lifecycle.phase == .idle && !fixture.lifecycle.isPreparing)
            #expect(fixture.payloads.isEmpty && fixture.errors.isEmpty)
            #expect(!fixture.start(ExportGate()))
            fixture.isCurrent = true
            #expect(fixture.start(retry))
            try await fixture.wait { retry.isWaiting }
            retry.complete(.success(fixture.payload("Retry after cancelled close")))
            try await fixture.wait { !fixture.presentations.isEmpty }
            #expect(fixture.payloads.map(\.title) == ["Retry after cancelled close"])
        }
    }

    @Test("A close committed during publication closes the returned auxiliary exactly once")
    func closeDuringPublicationClosesReturnedPresentation() async throws {
        let fixture = ExportFixture()
        let gate = ExportGate()
        try await fixture.run(gate) {
            fixture.duringPublish = { [lifecycle = fixture.lifecycle] in lifecycle.close() }
            #expect(fixture.start(gate))
            try await fixture.wait { gate.isWaiting }
            gate.complete(.success(fixture.payload("Closing")))
            try await fixture.wait { !fixture.presentations.isEmpty }
            #expect(fixture.presentations[0].closeCount == 1)
            #expect(fixture.lifecycle.phase == .closed && fixture.lifecycle.presentation == nil)
            #expect(!fixture.lifecycle.isPreparing && fixture.errors.isEmpty)
        }
    }
}

@MainActor
private final class ExportFixture {
    enum Failure: LocalizedError {
        case acquire
        var errorDescription: String? { "Synthetic export acquisition failure." }
    }

    static let source = "\u{FEFF}---\r\nunknown: 'retained'\r\n---\r\n# Synthetic 中文 😀 e\u{301}\r\n"
    let lifecycle = WindowNoteExportLifecycle()
    var isCurrent = true
    var payloads: [WindowNoteExportPayload] = []
    var presentations: [ExportPresentation] = []
    var errors: [String] = []
    var duringPublish: (@MainActor () -> Void)?

    func payload(_ title: String) -> WindowNoteExportPayload {
        // Header-only synthetic image bytes never reach a decoder or renderer.
        let image = try! RenderedMarkdownImage(data: Data("GIF89a".utf8), mimeType: "image/gif")
        return WindowNoteExportPayload(
            document: NoteDocument(relativePath: "Synthetic.md", rawContent: Self.source),
            title: title, embeddedImages: ["synthetic.gif": image],
            excludedRoots: [URL(fileURLWithPath: "/unused/export-fixture", isDirectory: true)],
            appearance: .defaultSettings, colorScheme: .dark
        )
    }

    func start(_ gate: ExportGate) -> Bool {
        lifecycle.prepare(
            acquire: { try await gate.read() },
            isCurrent: { [weak self] in self?.isCurrent ?? false },
            publish: { [weak self] payload, onClose in
                let presentation = ExportPresentation(onClose: onClose)
                self?.payloads.append(payload)
                self?.presentations.append(presentation)
                self?.duringPublish?()
                return presentation
            },
            onFailure: { [weak self] in self?.errors.append($0.localizedDescription) }
        )
    }

    func run(_ gates: ExportGate..., operation: @MainActor () async throws -> Void) async throws {
        do {
            try await operation()
        } catch {
            try? await closeReleaseAndDrain(gates)
            throw error
        }
        try await closeReleaseAndDrain(gates)
    }

    private func closeReleaseAndDrain(_ gates: [ExportGate]) async throws {
        lifecycle.close()
        gates.forEach { $0.complete(.failure(CancellationError())) }
        try await wait { gates.allSatisfy { !$0.didStart || $0.didReturn } }
    }

    func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "In-memory export did not reach its owned gate or completion")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class ExportGate {
    private var continuation: CheckedContinuation<WindowNoteExportPayload, any Error>?
    private var resolution: Result<WindowNoteExportPayload, any Error>?
    var isWaiting: Bool { continuation != nil }
    private(set) var didStart = false
    private(set) var didReturn = false
    private(set) var wasCancelledOnReturn = false

    /// Deliberately ignores cancellation so stale success/error reaches the owner.
    func read() async throws -> WindowNoteExportPayload {
        didStart = true
        defer {
            wasCancelledOnReturn = Task.isCancelled
            didReturn = true
        }
        if let resolution { return try resolution.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func complete(_ result: Result<WindowNoteExportPayload, any Error>) {
        guard resolution == nil else { return }
        resolution = result
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

@MainActor
private final class ExportPresentation: WindowNoteExportPresentation {
    private let onClose: @MainActor () -> Void
    private(set) var closeCount = 0

    init(onClose: @escaping @MainActor () -> Void) { self.onClose = onClose }

    func close() {
        closeCount += 1
        onClose()
    }

    func replayCloseNotification() { onClose() }
}
