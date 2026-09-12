import Combine
import Foundation
import ScholiumContracts

struct RelatedMaterialsSeed: Sendable {
    let request: RelatedContentRequest
    let attachment: AgentChatAttachment
    var insertionPoint: MarkdownEditorInsertionPoint? = nil
    var usesParagraph = false
}

struct RelatedMaterialCard: Identifiable, Equatable, Sendable {
    let passage: RelatedContentPassage
    let reference: VaultNoteReference
    var linkTarget: String? = nil
    var candidate: RelatedContentCandidate { passage.candidate }
    var text: String { passage.source }
    var line: Int { passage.range.line }
    var id: String { passage.id }

    var attachment: AgentChatAttachment? {
        guard let stableID = reference.stableNoteID.flatMap(UUID.init(uuidString:)) else { return nil }
        return AgentChatAttachment(
            noteID: stableID, vaultID: reference.vaultID,
            relativePath: reference.relativePath, text: passage.source,
            fingerprint: candidate.fingerprint, sourceLine: line, sourceRange: passage.range,
            source: .savedSource, vaultRole: reference.vaultRole)
    }
}

enum RelatedMaterialsError: LocalizedError, Equatable {
    case changedSource, insertionChanged, selectionRequired, unavailable, chatUnavailable, staleIndex, invalidSeed
    var errorDescription: String? {
        switch self {
        case .insertionChanged: String(localized: "Confirm the current cursor before inserting a link.", bundle: .module)
        case .staleIndex: String(localized: "Search needs refreshing before it can find current material.", bundle: .module)
        case .invalidSeed: String(localized: "This passage has no searchable wording. Try another selection.", bundle: .module)
        case .changedSource: String(localized: "A source has changed. Find related material again to use its current passage.", bundle: .module)
        case .selectionRequired: String(localized: "Select a passage in Edit or Source to find related material.", bundle: .module)
        case .chatUnavailable: String(localized: "Open an available conversation before adding this material to Chat.", bundle: .module)
        case .unavailable: String(localized: "Related material is unavailable. Wait for the Triptych to finish opening, then try again.", bundle: .module)
        }
    }
}

/// Window-local discovery. Visible selection events are debounced; opening a
/// result keeps the captured context until another nonempty selection arrives.
@MainActor final class RelatedMaterialsSession: ObservableObject {
    @Published private(set) var seed: RelatedMaterialsSeed?
    @Published private(set) var cards: [RelatedMaterialCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didSearch = false
    @Published private(set) var issue: String?
    @Published private(set) var omittedCount = 0
    @Published private(set) var needsRefresh = false
    @Published private(set) var insertionPoint: MarkdownEditorInsertionPoint?
    @Published private(set) var contextChanged = false

    struct NoteGroup: Identifiable {
        let id: VaultQualifiedNoteID
        var passages: [RelatedMaterialCard]
    }

    var noteGroups: [NoteGroup] {
        var groups: [NoteGroup] = []
        for card in cards {
            if let index = groups.firstIndex(where: { $0.id == card.candidate.note }) {
                groups[index].passages.append(card)
            } else {
                groups.append(.init(id: card.candidate.note, passages: [card]))
            }
        }
        return groups
    }

    enum Presentation: Equatable {
        case waiting, loading, empty, results
        case problem(String)
    }

    /// One derived presentation state; cards stay readable during replacement and failure.
    var presentation: Presentation {
        if isLoading { return cards.isEmpty ? .loading : .results }
        if let issue { return .problem(issue) }
        if omittedCount > 0 {
            return .problem(String(localized: "Some sources changed or could not be opened. Find again to refresh the results.", bundle: .module))
        }
        if !cards.isEmpty { return .results }
        return didSearch && !contextChanged ? .empty : .waiting
    }

    func invalidateWritingContext() {
        if isLoading { stopAutomaticSearch() }
        guard seed != nil else { return }
        insertionPoint = nil
        contextChanged = true
    }

    private var scheduledSearch: Task<Void, Never>?
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
        seed = nil
        insertionPoint = nil
        contextChanged = false
        cards = []
        didSearch = false
        omittedCount = 0
        issue = nil
        needsRefresh = false
    }

    func scheduleAutomaticSearch(selection: Bool, immediate: Bool = false, find: @escaping @MainActor () -> Void) {
        stopAutomaticSearch()
        scheduledSearch = Task { [weak self] in
            if !immediate {
                do { try await Task.sleep(for: .milliseconds(selection ? 250 : 1_200)) } catch { return }
            }
            guard self != nil, !Task.isCancelled else { return }
            find()
        }
    }

    func stopAutomaticSearch() {
        scheduledSearch?.cancel()
        scheduledSearch = nil
        generation = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    func cancel() {
        if isLoading {
            issue = String(localized: "Search cancelled. You can find material again when ready.", bundle: .module)
            needsRefresh = seed != nil
        }
        stopAutomaticSearch()
    }

    @discardableResult
    func find(
        capture: @escaping @MainActor () async throws -> RelatedMaterialsSeed,
        retrieve: @escaping @Sendable (RelatedContentRequest) async throws -> RelatedContentResponse,
        references: [VaultNoteReference],
        automatic: Bool = false,
        canPublish: @escaping @MainActor () -> Bool = { true },
        linkTarget: @escaping @MainActor (VaultNoteReference) async -> String? = { _ in nil }
    ) -> Task<Void, Never> {
        if !automatic {
            scheduledSearch?.cancel()
            scheduledSearch = nil
        }
        let canReuseResults = didSearch && issue == nil && !needsRefresh && omittedCount == 0
        generation = UUID()
        task?.cancel()
        let ticket = generation
        isLoading = true
        insertionPoint = nil
        issue = nil
        needsRefresh = false
        let operation = Task { [weak self] in
            guard let self else { return }
            do {
                let seed = try await capture()
                try Task.checkCancellation()
                guard ticket == generation else { return }
                guard canPublish() else {
                    isLoading = false
                    return
                }
                if automatic, self.seed?.request.seed == seed.request.seed, canReuseResults {
                    self.seed = seed
                    insertionPoint = seed.insertionPoint
                    contextChanged = false
                    isLoading = false
                    return
                }
                if cards.isEmpty { self.seed = seed }
                let response = try await retrieve(seed.request)
                try Task.checkCancellation()
                guard ticket == generation else { return }
                guard canPublish() else {
                    isLoading = false
                    return
                }
                guard response.requestID == seed.request.id,
                    response.seedFingerprint == seed.request.seed.fingerprint
                else { throw RelatedMaterialsError.unavailable }
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
                    guard
                        let reference = references.first(where: {
                            $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath
                        })
                    else {
                        omitted += 1
                        continue
                    }
                    guard !loaded.contains(where: { $0.id == passage.id }) else { continue }
                    let target = await linkTarget(reference)
                    try Task.checkCancellation()
                    loaded.append(.init(passage: passage, reference: reference, linkTarget: target))
                }
                try Task.checkCancellation()
                guard ticket == generation else { return }
                guard canPublish() else {
                    isLoading = false
                    return
                }
                self.seed = seed
                insertionPoint = seed.insertionPoint
                contextChanged = false
                if cards != loaded { cards = loaded }
                omittedCount = omitted
                didSearch = true
                isLoading = false
            } catch {
                guard ticket == generation else { return }
                guard canPublish() else {
                    isLoading = false
                    return
                }
                isLoading = false
                if !(error is CancellationError),
                    !(automatic && ((error as? RelatedMaterialsError) == .selectionRequired || (error as? RelatedMaterialsError) == .invalidSeed))
                {
                    report(error)
                }
            }
        }
        task = operation
        return operation
    }
}
