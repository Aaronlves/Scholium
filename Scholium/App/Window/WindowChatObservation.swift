import AppKit
import Combine
import ScholiumContracts

/// A request-local revocation edge. Combine's synchronous willSet delivery
/// records departure even when a window leaves and returns before the await ends.
/// It stores no observation, source, subscription or cross-request authority.
final class AgentChatObservationDeparture: @unchecked Sendable {
    private let lock = NSLock()
    private var departed = false
    var isCurrent: Bool { lock.withLock { !departed } }
    func invalidate() { lock.withLock { departed = true } }

    nonisolated func observing<P: Publisher>(_ publisher: P) -> AnyCancellable where P.Output: Equatable, P.Failure == Never {
        publisher.removeDuplicates().dropFirst().sink { [self] _ in invalidate() }
    }

    nonisolated func observingNotification(_ name: Notification.Name) -> AnyCancellable {
        NotificationCenter.default.publisher(for: name).sink { [self] _ in invalidate() }
    }
}

private func observationTriptychID(_ state: WindowWorkspaceSessionState) -> UUID? { state.assignment?.id }
private func observationRuntimeID(_ state: WindowWorkspaceSessionState) -> UUID? { state.activeServicesID }
private func observationPresentedMode(_ chrome: DocumentChromeProjection) -> NotePresentationMode { chrome.mode }

extension WindowModel {
    func observeChatDocument(admitted: @escaping @MainActor () -> Bool) async throws -> AgentChatDocumentObservation {
        let departure = AgentChatObservationDeparture()
        let closeAttempt = windowCloseCoordinator.closeAttemptSequence
        let lifecycleRegistry = nativeWindowCoordinator?.registry
        let terminationAttempt = lifecycleRegistry?.terminationAttemptSequence
        var observations = [
            departure.observing(chatSidebarPreferences.$isEnabled),
            departure.observing($transferInProgress),
            departure.observing(shellState.$libraryVisible),
            departure.observing(shellState.$sidebarContent),
            departure.observing(shellState.$selectedWorkspace),
            departure.observing(windowWorkspaceController.$state.map(observationTriptychID)),
            departure.observing(windowWorkspaceController.$state.map(observationRuntimeID)),
            departure.observing(documentController.$selectedDocument),
            departure.observing(documentController.$currentPresentationMode),
            departure.observing(documentController.$chromeProjection.map(observationPresentedMode)),
            departure.observingNotification(NSWindow.didResignKeyNotification),
            departure.observingNotification(NSWindow.willBeginSheetNotification),
        ]
        if let lifecycleRegistry {
            observations.append(departure.observing(lifecycleRegistry.$terminationAttemptSequence))
        }
        defer { observations.forEach { $0.cancel() } }
        func current() -> Bool {
            !Task.isCancelled && admitted() && departure.isCurrent && isChatSidebarEnabled
                && nativeWindowCoordinator?.registry === lifecycleRegistry
                && lifecycleRegistry?.isTerminationAttemptInProgress != true
                && terminationAttempt != UInt64.max && lifecycleRegistry?.terminationAttemptSequence == terminationAttempt
                && shellState.libraryVisible && shellState.sidebarContent == .chat
                && !transferInProgress
                && !windowCloseCoordinator.isPreparingOrFinalized && windowCloseCoordinator.closeAttemptSequence == closeAttempt
        }
        guard current() else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
        guard let descriptor = currentDocumentDescriptor else {
            return .init(surface: documentController.selectedDocument == nil ? .none : .unavailable)
        }
        guard let assignment = workspaceAssignment,
            assignment.vaults.values.contains(where: { $0.id == descriptor.reference.vaultID }),
            descriptor.reference.vaultRole != .other,
            descriptor.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == descriptor.sessionKey.noteID,
            descriptor.reference.relativePath.unicodeScalars.count <= 4_096,
            !descriptor.reference.relativePath.hasPrefix("/"),
            !descriptor.reference.relativePath.split(separator: "/").contains("..")
        else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
        let session = documentController.retainedSession(for: descriptor.sessionKey)
        let mode = presentedDocumentMode
        let revision: AgentChatDocumentObservation.Revision
        let selection: AgentChatDocumentObservation.Selection
        if let session, mode != .read {
            do { (revision, selection) = try await session.editorSession.currentChatMetadata() } catch {
                guard current() else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
                throw error
            }
        } else if let session, let note = currentNote?.hydratedSnapshot {
            // A dirty retained editor cannot lend its revision to a rendered selection.
            if session.hasUnsavedChanges {
                revision = .unavailable(.sourceSnapshotUnavailable)
                selection = .unavailable(.staleRenderer)
            } else {
                revision = .savedSource(note.document.fingerprint)
                if session.renderedReadFingerprint != note.document.fingerprint.sha256 {
                    selection = .unavailable(.staleRenderer)
                } else if let readSelection = session.readSelection {
                    if let exact = MarkdownReviewSourceSelection.review(readSelection, source: note.document.rawContent) {
                        selection = .exactSourceRange(exact.sourceRange.utf16LowerBound..<exact.sourceRange.utf16UpperBound, in: note.document.rawContent)
                    } else {
                        selection = .unavailable(.sourceMappingUnavailable)
                    }
                } else {
                    selection = .none
                }
            }
        } else {
            revision = .unavailable(.loading)
            selection = .unavailable(.loading)
        }
        guard current() else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
        return .init(
            surface: .triptychNote,
            activeNote: .init(
                vaultID: descriptor.reference.vaultID, noteID: descriptor.sessionKey.noteID,
                role: descriptor.reference.vaultRole, relativePath: descriptor.reference.relativePath, mode: mode,
                revision: revision, dirty: session?.hasUnsavedChanges ?? false,
                saving: session?.isSavingEdit ?? false, conflict: session?.conflict != nil, selection: selection),
            hasSaveError: session?.editError != nil)
    }
}
