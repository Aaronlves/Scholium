import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

@MainActor
extension AgentChatController {
    var materialInputIssue: String? {
        if selected?.localMaterials.contains(where: { $0.issue != nil }) == true {
            return String(localized: "Replace or remove the unavailable material before sending.")
        }
        if selected?.localMaterials.contains(where: \.requiresImageInput) == true,
            selectedModel?.inputModalities.contains("image") != true
        {
            return String(localized: "Choose a model with image input or remove the image.")
        }
        return nil
    }

    func addLocalFiles(_ urls: [URL], to conversationID: UUID, replacing materialID: UUID? = nil) async {
        _ = await performMaterialPreparation(in: conversationID) { [self] in
            for url in urls {
                let material = try await materialStore.stage(url)
                try await installPreparedMaterial(material, replacing: materialID, in: conversationID)
            }
        }
    }

    func addTransferredMaterials(
        _ materials: [AgentChatTransferredMaterial],
        origin: AgentChatLocalMaterial.CaptureOrigin, to conversationID: UUID,
        addNote: @escaping @MainActor (SidebarNoteDragItem) async throws -> Void
    ) async {
        _ = await performMaterialPreparation(in: conversationID) { [self] in
            for value in materials {
                let material: AgentChatLocalMaterial
                switch value {
                case .note(let note):
                    try await addNote(note)
                    continue
                case .file(let url): material = try await materialStore.stage(url)
                case .image(let data): material = try await materialStore.stageImageCapture(data, origin: origin)
                }
                try await installPreparedMaterial(material, replacing: nil, in: conversationID)
            }
        }
    }

    func pdfPageCount(for material: AgentChatLocalMaterial) async throws -> Int {
        try await materialStore.pdfPageCount(for: material)
    }

    func usePDFPages(_ selection: String, from material: AgentChatLocalMaterial, in conversationID: UUID) async -> Bool {
        await performMaterialPreparation(in: conversationID) { [self] in
            guard conversation(conversationID)?.localMaterials.contains(where: { $0.id == material.id }) == true else {
                throw AgentChatPDFPageSelectionFailure.unavailable
            }
            let prepared = try await materialStore.renderPDFPages(selection, from: material)
            try await installPreparedMaterial(prepared, replacing: material.id, in: conversationID)
        }
    }

    private func installPreparedMaterial(_ material: AgentChatLocalMaterial, replacing materialID: UUID?, in conversationID: UUID) async throws {
        guard !Task.isCancelled, let current = conversation(conversationID), current.isAvailable == true,
            materialID == nil || current.localMaterials.contains(where: { $0.id == materialID })
        else {
            try? await materialStore.discard(material)
            throw CancellationError()
        }
        let replaced = current.localMaterials.first { $0.id == materialID }
        update(in: conversationID) {
            if let materialID, let index = $0.localMaterials.firstIndex(where: { $0.id == materialID }) {
                $0.localMaterials[index] = material
            } else {
                $0.localMaterials.append(material)
            }
        }
        try await saveNow()
        if let replaced { try await releaseMaterialIfUnreferenced(replaced) }
        presentContext(in: conversationID)
    }

    func performMaterialPreparation(in conversationID: UUID, work: @escaping @MainActor () async throws -> Void) async -> Bool {
        guard isLoaded, !preparingMaterials.contains(conversationID),
            conversations.contains(where: { $0.id == conversationID && $0.isAvailable == true })
        else { return false }
        preparingMaterials.insert(conversationID)
        materialErrors[conversationID] = nil
        defer {
            preparingMaterials.remove(conversationID)
            materialTasks[conversationID] = nil
        }
        let operation = Task { @MainActor [weak self] in
            guard let self else { return false }
            do {
                try await work()
                return !Task.isCancelled
            } catch is CancellationError { return false } catch {
                materialErrors[conversationID] = AgentChatLocalMaterialLabels.error(error)
                return false
            }
        }
        materialTasks[conversationID] = operation
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    func presentContext(in conversationID: UUID) {
        if selectedID == conversationID { contextPresentationID = UUID() }
    }

    func cancelMaterialPreparation(in conversationID: UUID) { materialTasks[conversationID]?.cancel() }
    func reportMaterialError(_ message: String?, in conversationID: UUID) { materialErrors[conversationID] = message }

    func removeLocalMaterial(_ id: UUID, from conversationID: UUID) {
        guard !preparingMaterials.contains(conversationID), executions[conversationID]?.isSending != true,
            let material = conversation(conversationID)?.localMaterials.first(where: { $0.id == id })
        else { return }
        update(in: conversationID) { $0.localMaterials.removeAll { $0.id == id } }
        materialErrors[conversationID] = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await saveNow()
                try await releaseMaterialIfUnreferenced(material)
            } catch { materialErrors[conversationID] = error.localizedDescription }
        }
    }

    func releaseMaterialIfUnreferenced(_ material: AgentChatLocalMaterial) async throws {
        guard
            !conversations.contains(where: { conversation in
                conversation.localMaterials.contains { $0.id == material.id }
                    || conversation.queuedMessages.contains { $0.localMaterials.contains { $0.id == material.id } }
                    || conversation.messages.contains { $0.localMaterials.contains { $0.id == material.id } }
            })
        else { return }
        try await materialStore.discard(material)
    }

    func previewLocalMaterial(_ material: AgentChatLocalMaterial) async throws -> URL {
        try await materialStore.validatedURL(for: material)
    }
}
