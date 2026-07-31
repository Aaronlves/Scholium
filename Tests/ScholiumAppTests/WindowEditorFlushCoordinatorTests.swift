import Foundation
import Testing
@testable import ScholiumApp

@Suite("Window editor flush coordinator")
@MainActor
struct WindowEditorFlushCoordinatorTests {
    @Test("Transient editor detachment retains the selected document registration")
    func transientDetachmentRetainsSelectedEditor() async throws {
        let registry = RecordingWorkspaceEditorFlushRegistry()
        let coordinator = WindowEditorFlushCoordinator(
            windowID: UUID(),
            registry: registry
        )
        let token = UUID()
        let triptychID = UUID()
        var flushCount = 0

        coordinator.registerCurrentEditor(
            relativePath: "Topics/Agency.md",
            token: token,
            triptychID: triptychID,
            flush: { flushCount += 1 },
            captureForReconstruction: {}
        )
        coordinator.unregisterCurrentEditor(
            token: token,
            selectedDocumentPath: "Topics/Agency.md"
        )

        #expect(registry.registrations[token]?.triptychID == triptychID)
        try await registry.registrations[token]?.flush()
        #expect(flushCount == 1)

        coordinator.unregisterCurrentEditor(
            token: token,
            selectedDocumentPath: "Topics/Other.md"
        )
        #expect(registry.registrations[token] == nil)
    }

    @Test("Current editor validation preserves flush and reconstruction ordering")
    func currentEditorValidationAndCaptureOrdering() async throws {
        let registry = RecordingWorkspaceEditorFlushRegistry()
        let coordinator = WindowEditorFlushCoordinator(
            windowID: UUID(),
            registry: registry
        )
        var operations: [String] = []
        coordinator.registerCurrentEditor(
            relativePath: "Works/Chapter.md",
            token: UUID(),
            triptychID: UUID(),
            flush: { operations.append("flush") },
            captureForReconstruction: { operations.append("capture") }
        )

        try await coordinator.flushCurrentEditor(
            selectedDocumentPath: "Works/Chapter.md",
            capturingEditorState: true,
            fallback: { _ in operations.append("fallback") }
        )
        #expect(operations == ["flush", "capture"])

        await #expect(throws: WindowEditorFlushError.self) {
            try await coordinator.flushCurrentEditor(
                selectedDocumentPath: "Works/Different.md",
                capturingEditorState: false,
                fallback: { _ in operations.append("fallback") }
            )
        }
        #expect(operations == ["flush", "capture"])

        coordinator.clearCurrentEditor()
        try await coordinator.flushCurrentEditor(
            selectedDocumentPath: nil,
            capturingEditorState: false,
            fallback: { capture in
                operations.append(capture ? "fallback-capture" : "fallback")
            }
        )
        #expect(operations == ["flush", "capture", "fallback"])
    }

    @Test("Triptych and window replacement atomically rebind both capabilities")
    func triptychAndWindowReplacementRebindCapabilities() {
        let registry = RecordingWorkspaceEditorFlushRegistry()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstTriptychID = UUID()
        let secondTriptychID = UUID()
        let currentToken = UUID()
        let coordinator = WindowEditorFlushCoordinator(
            windowID: firstWindowID,
            registry: registry
        )

        coordinator.registerCurrentEditor(
            relativePath: "Analyses/Source.md",
            token: currentToken,
            triptychID: firstTriptychID,
            flush: {},
            captureForReconstruction: {}
        )
        coordinator.activateTriptych(firstTriptychID, flushOwnedSessions: {})
        #expect(registry.registrations.count == 2)
        #expect(registry.registrations.values.allSatisfy {
            $0.triptychID == firstTriptychID && $0.windowID == firstWindowID
        })

        coordinator.updateWindowID(secondWindowID)
        #expect(registry.registrations.count == 2)
        #expect(registry.registrations.values.allSatisfy {
            $0.triptychID == firstTriptychID && $0.windowID == secondWindowID
        })

        coordinator.activateTriptych(secondTriptychID, flushOwnedSessions: {})
        #expect(registry.registrations.count == 2)
        #expect(registry.registrations.values.allSatisfy {
            $0.triptychID == secondTriptychID && $0.windowID == secondWindowID
        })

        coordinator.shutdown()
        #expect(registry.registrations.isEmpty)
    }

    @Test("Triptych-wide flush remains delegated to the app registry")
    func triptychWideFlushDelegatesToRegistry() async throws {
        let registry = RecordingWorkspaceEditorFlushRegistry()
        let coordinator = WindowEditorFlushCoordinator(
            windowID: UUID(),
            registry: registry
        )
        let triptychID = UUID()

        try await coordinator.flushAllEditors(in: triptychID)

        #expect(registry.flushedTriptychIDs == [triptychID])
    }
}

@MainActor
private final class RecordingWorkspaceEditorFlushRegistry: WorkspaceEditorFlushRegistry {
    struct Registration {
        let triptychID: UUID
        let windowID: UUID
        let relativePath: String
        let flush: @MainActor () async throws -> Void
    }

    private(set) var registrations: [UUID: Registration] = [:]
    private(set) var flushedTriptychIDs: [UUID] = []

    func registerEditorFlush(
        token: UUID,
        triptychID: UUID,
        windowID: UUID,
        relativePath: String,
        flush: @escaping @MainActor () async throws -> Void
    ) {
        registrations[token] = Registration(
            triptychID: triptychID,
            windowID: windowID,
            relativePath: relativePath,
            flush: flush
        )
    }

    func unregisterEditorFlush(token: UUID) {
        registrations[token] = nil
    }

    func flushEditors(in triptychID: UUID) async throws {
        flushedTriptychIDs.append(triptychID)
    }
}
