import Foundation

@MainActor
protocol WorkspaceEditorFlushRegistry: AnyObject {
    func registerEditorFlush(
        token: UUID,
        triptychID: UUID,
        windowID: UUID,
        relativePath: String,
        flush: @escaping @MainActor () async throws -> Void
    )

    func unregisterEditorFlush(token: UUID)

    func flushEditors(in triptychID: UUID) async throws
}

enum WindowEditorFlushError: LocalizedError {
    case staleEditorRegistration(expected: String, registered: String)

    var errorDescription: String? {
        switch self {
        case .staleEditorRegistration(let expected, let registered):
            String(
                localized: "Scholium kept the document open because the active editor changed from \(registered) to \(expected) before it could be saved.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

/// Owns the exact window's current-editor and aggregate editor-flush
/// registrations. The app-wide registry remains the cross-window coordinator;
/// this value owns only one window's registration identity and teardown.
@MainActor
final class WindowEditorFlushCoordinator {
    private struct CurrentRegistration {
        let token: UUID
        let relativePath: String
        let flush: @MainActor () async throws -> Void
        let captureForReconstruction: @MainActor () async throws -> Void
        var registeredTriptychID: UUID?
    }

    private let registry: any WorkspaceEditorFlushRegistry
    private let aggregateToken = UUID()
    private var windowID: UUID
    private var currentRegistration: CurrentRegistration?
    private var aggregateTriptychID: UUID?
    private var aggregateFlush: (@MainActor () async throws -> Void)?

    init(
        windowID: UUID,
        registry: any WorkspaceEditorFlushRegistry
    ) {
        self.windowID = windowID
        self.registry = registry
    }

    func updateWindowID(_ id: UUID) {
        guard id != windowID else { return }
        unregisterInstalledCapabilities()
        windowID = id
        reinstallCapabilities()
    }

    func registerCurrentEditor(
        relativePath: String,
        token: UUID,
        triptychID: UUID?,
        flush: @escaping @MainActor () async throws -> Void,
        captureForReconstruction: @escaping @MainActor () async throws -> Void
    ) {
        if let previous = currentRegistration {
            registry.unregisterEditorFlush(token: previous.token)
        }
        currentRegistration = CurrentRegistration(
            token: token,
            relativePath: relativePath,
            flush: flush,
            captureForReconstruction: captureForReconstruction,
            registeredTriptychID: nil
        )
        registerCurrentEditorIfPossible(triptychID: triptychID)
    }

    func unregisterCurrentEditor(
        token: UUID,
        selectedDocumentPath: String?
    ) {
        guard let registration = currentRegistration,
              registration.token == token else {
            registry.unregisterEditorFlush(token: token)
            return
        }
        // SwiftUI may detach and reattach the editor host while the same
        // retained document remains selected. That transient disappearance is
        // not the end of the window's flush ownership.
        guard selectedDocumentPath != registration.relativePath else { return }
        clearCurrentEditor()
    }

    func clearCurrentEditor() {
        guard let registration = currentRegistration else { return }
        registry.unregisterEditorFlush(token: registration.token)
        currentRegistration = nil
    }

    func activateTriptych(
        _ triptychID: UUID,
        flushOwnedSessions: @escaping @MainActor () async throws -> Void
    ) {
        if aggregateTriptychID != triptychID {
            if aggregateTriptychID != nil {
                registry.unregisterEditorFlush(token: aggregateToken)
            }
            aggregateTriptychID = triptychID
        }
        aggregateFlush = flushOwnedSessions
        registry.registerEditorFlush(
            token: aggregateToken,
            triptychID: triptychID,
            windowID: windowID,
            relativePath: "",
            flush: flushOwnedSessions
        )

        guard currentRegistration?.registeredTriptychID != triptychID else { return }
        if let token = currentRegistration?.token {
            registry.unregisterEditorFlush(token: token)
        }
        registerCurrentEditorIfPossible(triptychID: triptychID)
    }

    func flushCurrentEditor(
        selectedDocumentPath: String?,
        capturingEditorState: Bool,
        fallback: @MainActor (_ capturingEditorState: Bool) async throws -> Void
    ) async throws {
        if let registration = currentRegistration {
            try validate(registration, selectedDocumentPath: selectedDocumentPath)
            try await registration.flush()
            if capturingEditorState {
                try await registration.captureForReconstruction()
            }
            return
        }
        try await fallback(capturingEditorState)
    }

    func flushCurrentEditorForResearchAction(
        selectedDocumentPath: String?,
        fallback: @MainActor () async throws -> Void
    ) async throws {
        if let registration = currentRegistration {
            try validate(registration, selectedDocumentPath: selectedDocumentPath)
            try await registration.flush()
            return
        }
        try await fallback()
    }

    func flushAllEditors(in triptychID: UUID) async throws {
        try await registry.flushEditors(in: triptychID)
    }

    func shutdown() {
        clearCurrentEditor()
        if aggregateTriptychID != nil {
            registry.unregisterEditorFlush(token: aggregateToken)
        }
        aggregateTriptychID = nil
        aggregateFlush = nil
    }

    private func validate(
        _ registration: CurrentRegistration,
        selectedDocumentPath: String?
    ) throws {
        if let selectedDocumentPath,
           selectedDocumentPath != registration.relativePath {
            throw WindowEditorFlushError.staleEditorRegistration(
                expected: selectedDocumentPath,
                registered: registration.relativePath
            )
        }
    }

    private func registerCurrentEditorIfPossible(triptychID: UUID?) {
        guard var registration = currentRegistration,
              let triptychID else { return }
        registry.registerEditorFlush(
            token: registration.token,
            triptychID: triptychID,
            windowID: windowID,
            relativePath: registration.relativePath,
            flush: registration.flush
        )
        registration.registeredTriptychID = triptychID
        currentRegistration = registration
    }

    private func unregisterInstalledCapabilities() {
        if let registration = currentRegistration,
           registration.registeredTriptychID != nil {
            registry.unregisterEditorFlush(token: registration.token)
        }
        if aggregateTriptychID != nil {
            registry.unregisterEditorFlush(token: aggregateToken)
        }
    }

    private func reinstallCapabilities() {
        if let triptychID = aggregateTriptychID,
           let aggregateFlush {
            registry.registerEditorFlush(
                token: aggregateToken,
                triptychID: triptychID,
                windowID: windowID,
                relativePath: "",
                flush: aggregateFlush
            )
        }
        registerCurrentEditorIfPossible(
            triptychID: currentRegistration?.registeredTriptychID
        )
    }
}
