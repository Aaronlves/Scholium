import Combine
import Foundation
import ScholiumContracts

struct RelatedMaterialsSeed: Sendable {
    let request: RelatedContentRequest
    let attachment: AgentChatAttachment
}

struct RelatedMaterialCard: Identifiable, Sendable {
    let passage: RelatedContentPassage
    let reference: VaultNoteReference
    var candidate: RelatedContentCandidate { passage.candidate }
    var text: String { passage.source }
    var line: Int { passage.range.line }
    var id: String { passage.id }

    var attachment: AgentChatAttachment? {
        guard let stableID = reference.stableNoteID.flatMap(UUID.init(uuidString:)) else { return nil }
        return AgentChatAttachment(noteID: stableID, vaultID: reference.vaultID,
            relativePath: reference.relativePath, text: passage.source,
            fingerprint: candidate.fingerprint, sourceLine: line, sourceRange: passage.range)
    }
}

enum RelatedMaterialsError: LocalizedError, Equatable {
    case changedSource, selectionRequired, unavailable, chatUnavailable, staleIndex, invalidSeed
    var errorDescription: String? {
        switch self {
        case .staleIndex: String(localized: "Search needs refreshing before it can find current material.", bundle: .module)
        case .invalidSeed: String(localized: "This passage has no searchable wording. Try another selection.", bundle: .module)
        case .changedSource: String(localized: "A source has changed. Find related material again to use its current passage.", bundle: .module)
        case .selectionRequired: String(localized: "Select a passage in Edit or Source to find related material.", bundle: .module)
        case .chatUnavailable: String(localized: "Open an available conversation before adding this material to Chat.", bundle: .module)
        case .unavailable: String(localized: "Related material is unavailable. Wait for the Triptych to finish opening, then try again.", bundle: .module)
        }
    }
}

/// Window-local, disposable discovery state. A selection is frozen until the
/// next explicit request; neither caret motion nor opening a source reruns it.
@MainActor final class RelatedMaterialsSession: ObservableObject {
    @Published private(set) var seed: RelatedMaterialsSeed?
    @Published private(set) var cards: [RelatedMaterialCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didSearch = false
    @Published private(set) var issue: String?
    @Published private(set) var omittedCount = 0
    @Published private(set) var needsRefresh = false
    private var generation = UUID()
    private var task: Task<Void, Never>?

    func report(_ error: Error) {
        issue = error.localizedDescription
        if let error = error as? RelatedMaterialsError {
            needsRefresh = [.staleIndex, .changedSource, .unavailable].contains(error) && seed != nil
        }
    }

    func reset() {
        cancel()
        seed = nil; cards = []; didSearch = false; omittedCount = 0; issue = nil; needsRefresh = false
    }

    func cancel() {
        if isLoading { issue = String(localized: "Search cancelled. You can find material again when ready.", bundle: .module) }
        generation = UUID()
        task?.cancel(); task = nil; isLoading = false
    }

    @discardableResult
    func find(
        capture: @escaping @MainActor () async throws -> RelatedMaterialsSeed,
        retrieve: @escaping @Sendable (RelatedContentRequest) async throws -> RelatedContentResponse,
        references: [VaultNoteReference]
    ) -> Task<Void, Never> {
        cancel()
        let ticket = generation
        isLoading = true; issue = nil; needsRefresh = false
        let operation = Task { [weak self] in
            guard let self else { return }
            do {
                let seed = try await capture()
                try Task.checkCancellation()
                guard ticket == generation else { return }
                self.seed = seed; cards = []; didSearch = false; omittedCount = 0
                let response = try await retrieve(seed.request)
                try Task.checkCancellation()
                guard ticket == generation else { return }
                guard response.requestID == seed.request.id,
                      response.seedFingerprint == seed.request.seed.fingerprint else { throw RelatedMaterialsError.unavailable }
                switch response.state {
                case .current, .empty: break
                case .partial: issue = String(localized: "Some related material is temporarily unavailable.", bundle: .module)
                case .stale: throw RelatedMaterialsError.staleIndex
                case .invalidSeed: throw RelatedMaterialsError.invalidSeed
                case .unavailable: throw RelatedMaterialsError.unavailable
                }
                var loaded: [RelatedMaterialCard] = []
                var omitted = response.omittedSourceCount
                for passage in response.passages {
                    let candidate = passage.candidate
                    guard let reference = references.first(where: {
                        $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath
                    }) else { omitted += 1; continue }
                    loaded.append(.init(passage: passage, reference: reference))
                }
                try Task.checkCancellation()
                guard ticket == generation else { return }
                cards = loaded; omittedCount = omitted; didSearch = true; isLoading = false
            } catch {
                guard ticket == generation else { return }
                isLoading = false
                if !(error is CancellationError) { report(error) }
            }
        }
        task = operation
        return operation
    }
}
