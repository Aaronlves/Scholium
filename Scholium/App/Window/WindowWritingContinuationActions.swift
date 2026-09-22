import Foundation
import ScholiumApplication
import ScholiumContracts

extension WindowModel {
    @MainActor
    func continueWriting(
        at caret: Int,
        status: EditorWritingContinuationStatusHandler
    ) async -> EditorWritingContinuationResult {
        let preferences = WritingAssistancePreferences.shared
        guard preferences.continuationEnabled else { return .unavailable(.disabled) }
        guard canEditCurrentNote, presentedDocumentMode != .read,
            let descriptor = currentDocumentDescriptor
        else { return .unavailable(.invalidContext) }
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            let chat = chatController
        else { return .unavailable(.notConnected) }
        let model = preferences.model
        guard chat.connectionState == .ready, chat.account != nil else {
            return .unavailable(.notConnected)
        }
        guard !chat.isRenewingSettings, !chat.capabilities.isChanging else {
            return .unavailable(.notReady)
        }
        guard chat.models.contains(where: { $0.model == model && CodexWritingAssistance.supports($0) }) else {
            return .unavailable(.modelUnavailable)
        }
        guard chat.canRequestWritingAssistance(model: model) else {
            return .unavailable(.notReady)
        }
        guard chat.writingAssistanceExecution == nil else { return .unavailable(.busy) }
        let session = documentController.session(for: descriptor)
        let editor = session.editorSession
        guard session.conflict == nil, editor.hasWritingFocus, !editor.isComposing else {
            return .unavailable(.invalidContext)
        }
        do {
            let captured = try await editor.writingContextSnapshot(paragraph: true)
            guard let point = captured.point,
                EditorSourceOffsetMap(source: captured.snapshot.source)
                    .sourceUTF16Offset(forEditorUTF16Offset: point.selection.head) == caret,
                let context = WritingContinuationContext(snapshot: captured.snapshot, caret: caret)
            else { return .unavailable(.invalidContext) }
            func remainsCurrent() -> Bool {
                !Task.isCancelled && preferences.continuationEnabled && preferences.model == model
                    && canEditCurrentNote
                    && currentDocumentDescriptor == descriptor
                    && windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
                    && chatController === chat && editor.acceptsInsertionPoint(point)
                    && editor.hasWritingFocus && session.conflict == nil && presentedDocumentMode != .read
            }
            guard remainsCurrent() else { return .unavailable(.cancelled) }
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
                    status(.retrieving)
                    let request = RelatedContentRequest(
                        seed: .init(
                            noteID: key.note, source: captured.snapshot.source,
                            focuses: [.init(kind: .selectedPassage, text: context.focus)]),
                        identityLimit: 1, lexicalLimit: 3)
                    do {
                        let response = try await capabilities.discovery.relatedContent(request)
                        guard remainsCurrent() else { return .unavailable(.cancelled) }
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
            guard remainsCurrent() else { return .unavailable(.cancelled) }
            status(.generating)
            let suffix = try await chat.writingAssistance(
                .init(before: context.before, after: context.after, background: background, model: model))
            guard remainsCurrent() else { return .unavailable(.cancelled) }
            if !background.isEmpty, let backgroundResponse {
                guard WritingContinuationContext.background(backgroundResponse, catalog: workspaceCatalog?.notes ?? []) == background
                else { return .unavailable(.cancelled) }
            }
            return suffix.isEmpty ? .unavailable(.noSuggestion) : .suggestion(suffix)
        } catch is CancellationError {
            return .unavailable(.cancelled)
        } catch let error as CodexWritingAssistanceError {
            return .unavailable(Self.editorUnavailableReason(for: error))
        } catch let error as CodexConnectionError {
            return .unavailable(Self.editorUnavailableReason(for: error))
        } catch {
            guard !Task.isCancelled, preferences.continuationEnabled, preferences.model == model,
                currentDocumentDescriptor == descriptor
            else { return .unavailable(.cancelled) }
            return .unavailable(.serviceError)
        }
    }

    private static func editorUnavailableReason(
        for error: CodexWritingAssistanceError
    ) -> EditorWritingContinuationUnavailableReason {
        switch error {
        case .unavailable: .connectionError
        case .busy: .busy
        case .invalidContext: .invalidContext
        case .invalidOutput: .noSuggestion
        case .unsafeRuntime: .serviceError
        case .timedOut: .timedOut
        }
    }

    private static func editorUnavailableReason(
        for error: CodexConnectionError
    ) -> EditorWritingContinuationUnavailableReason {
        switch error {
        case .disconnected, .server: .connectionError
        case .timedOut: .timedOut
        case .invalidMessage: .serviceError
        }
    }
}
