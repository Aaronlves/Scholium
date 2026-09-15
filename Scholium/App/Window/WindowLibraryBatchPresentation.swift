import AppKit
import ScholiumContracts

extension WindowModel {
    /// nil means the File menu belongs to the document; an empty array means
    /// the focused Library selection is not a valid group of writable Notes.
    var focusedLibraryMutationTargets: [NoteMutationTarget]? {
        guard shellState.libraryVisible, shellState.sidebarContent == .triptych,
            let outline = NSApp.keyWindow?.firstResponder as? SidebarOutlineView,
            !outline.isHiddenOrHasHiddenAncestor,
            outline.window?.identifier?.rawValue == "scholium-main-\(nativeWindowID.uuidString)"
        else { return nil }
        guard let vault = currentRegisteredVault else { return [] }
        let scope = LibraryDisclosureScope(vaultID: vault.id, sourceScope: noteSourceScope)
        let ids = discoveryController.librarySelection(in: scope)
        let targets = filteredNotes.filter { ids.contains($0.relativePath) }.compactMap(NoteMutationTarget.init)
        return targets.count == ids.count ? targets : []
    }

    var fileCommandSingleNoteTarget: NoteMutationTarget? {
        guard !libraryMutationController.isBatchWorking else { return nil }
        if let targets = focusedLibraryMutationTargets { return targets.count == 1 ? targets.first : nil }
        guard currentDocumentCapabilities.allows(.move), let currentNote else { return nil }
        return NoteMutationTarget(currentNote)
    }

    var canPerformFileSelectionMutation: Bool {
        guard !libraryMutationController.isBatchWorking, presentationRouter.sheet == nil else { return false }
        if let targets = focusedLibraryMutationTargets { return !targets.isEmpty }
        return currentDocumentCapabilities.allows(.move)
    }

    private var canPrepareLibraryBatch: Bool {
        guard !libraryMutationController.isBatchWorking else { return false }
        guard let sheet = presentationRouter.sheet else { return true }
        if case .libraryNoteBatch(let request) = sheet {
            return libraryMutationController.lastBatchOutcome?.id == request.id
        }
        return false
    }

    func requestLibraryBatchMove(_ targets: [NoteMutationTarget]) {
        guard canPrepareLibraryBatch else { return }
        let routeID = presentationRouter.sheet?.id
        Task { @MainActor in
            do {
                let request = try await libraryMutationController.prepareNoteBatch(targets)
                guard presentationRouter.sheet?.id == routeID else { return }
                presentationRouter.present(.libraryNoteBatch(request))
            } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
        }
    }

    func requestLibraryBatchTrash(_ targets: [NoteMutationTarget]) {
        guard canPrepareLibraryBatch else { return }
        let routeID = presentationRouter.sheet?.id
        Task { @MainActor in
            do {
                let request = try await libraryMutationController.prepareNoteBatch(targets)
                let preview = try await libraryMutationController.prepareNotesSystemTrash(request)
                guard presentationRouter.sheet?.id == routeID else { return }
                presentationRouter.present(.libraryBatchTrash(preview))
            } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
        }
    }

    func moveLibraryBatchByDrop(_ targets: [NoteMutationTarget], into folder: String?) {
        guard presentationRouter.sheet == nil else { return }
        Task { @MainActor in
            do {
                let request = try await libraryMutationController.prepareNoteBatch(targets)
                presentationRouter.present(.libraryNoteBatch(request))
                let outcome = await libraryMutationController.moveNotes(request, toFolder: folder ?? "")
                presentLibraryBatchOutcome(outcome)
            } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
        }
    }

    func executeLibraryBatchMove(_ request: LibraryNoteBatchRequest, toFolder folder: String) {
        Task { @MainActor in
            let outcome = await libraryMutationController.moveNotes(request, toFolder: folder)
            presentLibraryBatchOutcome(outcome)
        }
    }

    func presentLibraryBatchOutcome(_ outcome: LibraryNoteBatchOutcome) {
        if outcome.isComplete && outcome.warnings.isEmpty {
            presentationRouter.dismissSheet()
        } else {
            presentationRouter.present(.libraryNoteBatch(outcome.request))
        }
    }

    func showLastLibraryBatchOutcome() {
        guard let outcome = libraryMutationController.lastBatchOutcome else { return }
        presentationRouter.present(.libraryNoteBatch(outcome.request))
    }

    func retryLastLibraryBatch() {
        guard let outcome = libraryMutationController.lastBatchOutcome, !outcome.retryTargets.isEmpty else { return }
        switch outcome.operation {
        case .move: requestLibraryBatchMove(outcome.retryTargets)
        case .systemTrash: requestLibraryBatchTrash(outcome.retryTargets)
        }
    }
}
