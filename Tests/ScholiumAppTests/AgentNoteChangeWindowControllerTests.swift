import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
@Suite("Agent Note Change exact-window lifecycle")
struct AgentNoteChangeWindowControllerTests {
    @MainActor
    private final class ResolutionLatch {
        var continuation: CheckedContinuation<Void, Never>?

        var isWaiting: Bool { continuation != nil }

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @Test("Closing one claimed window clears its state and transfers exactly once")
    func closeTransfersExactWindowOwnership() async throws {
        let claims = AgentNoteChangeClaimCoordinator()
        let triptychID = UUID()
        let backgroundID = UUID()
        let keyID = UUID()
        let backgroundRouter = WindowPresentationRouter()
        let keyRouter = WindowPresentationRouter()
        let dependencies = dependencies()
        let background = AgentNoteChangeWindowController(
            windowID: backgroundID,
            presentationRouter: backgroundRouter,
            claimCoordinator: claims,
            dependencies: dependencies,
            reportError: { _ in }
        )
        let key = AgentNoteChangeWindowController(
            windowID: keyID,
            presentationRouter: keyRouter,
            claimCoordinator: claims,
            dependencies: dependencies,
            reportError: { _ in }
        )
        background.registerWindowEndpoint(
            activeTriptychID: { triptychID },
            isKeyWindow: { false },
            canPresent: { backgroundRouter.sheet == nil },
            willPresent: {},
            focus: {}
        )
        key.registerWindowEndpoint(
            activeTriptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { keyRouter.sheet == nil },
            willPresent: {},
            focus: {}
        )
        let record = try AgentNoteChangeTestFixtures.record(triptychID: triptychID)

        claims.receive(record, intent: .submit)
        try await waitUntil("key window presentation identity") {
            key.identity != nil
        }

        #expect(key.record?.id == record.id)
        #expect(background.record == nil)
        #expect(keyRouter.sheet?.id == agentRouteID(record.id))
        #expect(claims.claimedWindowID(for: record.id) == keyID)

        key.unregisterWindow()
        try await waitUntil("background transfer identity") {
            background.identity != nil
        }

        #expect(key.record == nil)
        #expect(keyRouter.sheet == nil)
        #expect(background.record?.id == record.id)
        #expect(backgroundRouter.sheet?.id == agentRouteID(record.id))
        #expect(claims.claimedWindowID(for: record.id) == backgroundID)

        background.unregisterWindow()
    }

    @Test("A terminal decision dismisses only its current window presentation")
    func terminalDecisionOwnsCurrentIdentity() async throws {
        let claims = AgentNoteChangeClaimCoordinator()
        let triptychID = UUID()
        let windowID = UUID()
        let router = WindowPresentationRouter()
        let source = try AgentNoteChangeTestFixtures.record(triptychID: triptychID)
        var reportedErrors: [String] = []
        let controller = AgentNoteChangeWindowController(
            windowID: windowID,
            presentationRouter: router,
            claimCoordinator: claims,
            dependencies: dependencies(resolve: { state, allowedNoteIDs in
                let resolved = try source.resolving(
                    state: state,
                    allowedNoteIDs: allowedNoteIDs,
                    at: source.receivedAt.addingTimeInterval(1)
                )
                claims.receive(resolved, intent: .decision)
                return resolved
            }),
            reportError: { reportedErrors.append($0) }
        )
        controller.registerWindowEndpoint(
            activeTriptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { router.sheet == nil },
            willPresent: {},
            focus: {}
        )
        claims.receive(source, intent: .submit)
        try await waitUntil("request presentation") {
            controller.identity != nil
        }

        controller.resolve(state: .continueWithoutChanges, allowedNoteIDs: [])
        try await waitUntil("terminal request dismissal") {
            router.sheet == nil && controller.record?.isUnresolved == false
        }

        controller.finishDismissal()

        #expect(controller.record == nil)
        #expect(controller.identity == nil)
        #expect(!controller.isResolving)
        #expect(claims.claimedWindowID(for: source.id) == nil)
        #expect(reportedErrors.isEmpty)
    }

    @Test("A closing window rejects a cancellation-insensitive late decision failure")
    func closeRejectsLateDecisionFailure() async throws {
        let claims = AgentNoteChangeClaimCoordinator()
        let triptychID = UUID()
        let router = WindowPresentationRouter()
        let source = try AgentNoteChangeTestFixtures.record(triptychID: triptychID)
        let latch = ResolutionLatch()
        var reportedErrors: [String] = []
        let controller = AgentNoteChangeWindowController(
            windowID: UUID(),
            presentationRouter: router,
            claimCoordinator: claims,
            dependencies: dependencies(resolve: { _, _ in
                await latch.wait()
                throw TestFailure.unexpectedResolution
            }),
            reportError: { reportedErrors.append($0) }
        )
        controller.registerWindowEndpoint(
            activeTriptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { router.sheet == nil },
            willPresent: {},
            focus: {}
        )
        claims.receive(source, intent: .submit)
        try await waitUntil("request presentation") {
            controller.identity != nil
        }

        controller.resolve(state: .continueWithoutChanges, allowedNoteIDs: [])
        try await waitUntil("decision suspension") { latch.isWaiting }
        controller.unregisterWindow()
        latch.resume()
        for _ in 0..<10 { await Task.yield() }

        #expect(controller.record == nil)
        #expect(router.sheet == nil)
        #expect(!controller.isResolving)
        #expect(reportedErrors.isEmpty)
    }

    private func dependencies(
        resolve: @escaping @MainActor (
            AgentNoteChangeDecisionState,
            [UUID]
        ) async throws -> AgentNoteChangeRequestRecord = { _, _ in
            throw TestFailure.unexpectedResolution
        }
    ) -> AgentNoteChangeWindowController.Dependencies {
        .init(
            presentationIdentity: { _ in
                AgentNoteChangePresentationIdentity(
                    actionName: "Synthesize",
                    skillName: "Synthesis Method"
                )
            },
            refresh: { _, _ in },
            resolve: { _, _, state, noteIDs in
                try await resolve(state, noteIDs)
            },
            snapshot: { _ in nil }
        )
    }

    private func agentRouteID(_ requestID: UUID) -> String {
        "agent-note-change:\(requestID.uuidString.lowercased())"
    }

    private func waitUntil(
        _ description: String,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(description).")
    }

    private enum TestFailure: Error {
        case unexpectedResolution
    }
}
