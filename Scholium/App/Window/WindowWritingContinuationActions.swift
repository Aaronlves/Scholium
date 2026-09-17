import Foundation
import ScholiumContracts

extension WindowModel {
    @MainActor
    func continueWriting(at caret: Int) async -> EditorWritingContinuationResult {
        let preferences = WritingContinuationPreferences.shared
        guard preferences.enabled, canEditCurrentNote, presentedDocumentMode != .read,
            let descriptor = currentDocumentDescriptor,
            let capabilities = windowWorkspaceController.activeCapabilities,
            let chat = chatController
        else { return .unavailable(nil) }
        let model = preferences.model
        guard chat.canRequestWritingContinuation(model: model) else { return .unavailable(nil) }
        let session = documentController.session(for: descriptor)
        let editor = session.editorSession
        guard session.conflict == nil, editor.hasWritingFocus, !editor.isComposing else { return .unavailable(nil) }
        do {
            let captured = try await editor.writingContextSnapshot(paragraph: true)
            guard let point = captured.point,
                EditorSourceOffsetMap(source: captured.snapshot.source)
                    .sourceUTF16Offset(forEditorUTF16Offset: point.selection.head) == caret,
                let context = WritingContinuationContext(snapshot: captured.snapshot, caret: caret)
            else { return .unavailable(nil) }
            func remainsCurrent() -> Bool {
                !Task.isCancelled && preferences.enabled && preferences.model == model
                    && canEditCurrentNote
                    && currentDocumentDescriptor == descriptor
                    && windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
                    && chatController === chat && editor.acceptsInsertionPoint(point)
                    && editor.hasWritingFocus && session.conflict == nil && presentedDocumentMode != .read
            }
            guard remainsCurrent() else { return .unavailable(nil) }
            var background: [String] = []
            var backgroundResponse: RelatedContentResponse?
            if let generation = workspaceProjectionController.searchGeneration {
                let key = WritingContinuationContextCache.Key(
                    runtime: capabilities.runtimeIdentity,
                    note: .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath),
                    generation: generation, seedFingerprint: .init(content: captured.snapshot.source), focus: context.focus)
                if let cached = writingContinuationContextCache.value(for: key) {
                    backgroundResponse = cached
                    background = WritingContinuationContext.background(cached, catalog: workspaceCatalog?.notes ?? [])
                } else if captured.snapshot.source.utf16.count <= RelatedContentContract.maximumSeedUTF16Count {
                    let request = RelatedContentRequest(
                        seed: .init(
                            noteID: key.note, source: captured.snapshot.source,
                            focuses: [.init(kind: .selectedPassage, text: context.focus)]),
                        identityLimit: 1, lexicalLimit: 3)
                    do {
                        let response = try await capabilities.discovery.relatedContent(request)
                        guard remainsCurrent() else { return .unavailable(nil) }
                        if response.requestID == request.id, response.seedFingerprint == request.seed.fingerprint,
                            response.freshnessToken == .triptych(generation),
                            workspaceProjectionController.searchGeneration == generation
                        {
                            backgroundResponse = response
                            background = WritingContinuationContext.background(response, catalog: workspaceCatalog?.notes ?? [])
                            if response.state == .current || response.state == .empty {
                                writingContinuationContextCache.replace(key: key, response: response)
                            }
                        }
                    } catch is CancellationError { throw CancellationError() } catch {
                        // Search unavailability is not generation failure. Never
                        // resend or broaden access; continue with writing only.
                    }
                }
            }
            guard remainsCurrent() else { return .unavailable(nil) }
            let suffix = try await chat.writingContinuation(
                .init(before: context.before, after: context.after, background: background, model: model))
            guard remainsCurrent() else { return .unavailable(nil) }
            if !background.isEmpty, let backgroundResponse {
                guard WritingContinuationContext.background(backgroundResponse, catalog: workspaceCatalog?.notes ?? []) == background
                else { return .unavailable(nil) }
            }
            return suffix.isEmpty ? .unavailable(nil) : .suggestion(suffix)
        } catch is CancellationError {
            return .unavailable(nil)
        } catch {
            guard !Task.isCancelled, preferences.enabled, preferences.model == model,
                currentDocumentDescriptor == descriptor
            else { return .unavailable(nil) }
            // The shared preview supplies localized fallback feedback; raw
            // transport diagnostics are not writing suggestions.
            return .unavailable(nil)
        }
    }
}
