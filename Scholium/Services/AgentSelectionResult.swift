import Combine
import Foundation

typealias AgentSelectionValidation = @MainActor () async -> Bool
typealias AgentSelectionInquiryHandler = @MainActor (AgentChatSelectionInquiry, @escaping AgentSelectionValidation) async throws -> AgentSelectionResult?

/// Window-owned, disposable writing assistance. Closing its presentation does not discard a result.
@MainActor
final class AgentSelectionResult: ObservableObject {
    let title: String
    let original: String
    let adopt: ((String) async throws -> Void)?
    let openReference: (URL) -> Bool
    @Published private(set) var versions: [String] = []
    @Published private(set) var selectedVersionIndex = 0
    @Published private(set) var isGenerating = false
    @Published private(set) var error: String?
    @Published private(set) var isStopped = false
    @Published private(set) var isAdopted = false
    @Published private(set) var isAdopting = false
    @Published private(set) var adoptionError: String?
    private let generate: @MainActor () async throws -> String
    private let handoff: @MainActor (String?) -> Void
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private var adoptionTask: Task<Void, Never>?

    init(
        title: String, original: String, adopt: ((String) async throws -> Void)?,
        openReference: @escaping (URL) -> Bool,
        generate: @escaping @MainActor () async throws -> String,
        continueInChat: @escaping @MainActor (String?) -> Void
    ) {
        self.title = title
        self.original = original
        self.adopt = adopt
        self.openReference = openReference
        self.generate = generate
        self.handoff = continueInChat
    }

    deinit { task?.cancel() }

    var finalReply: String? {
        versions.indices.contains(selectedVersionIndex) ? versions[selectedVersionIndex] : nil
    }
    var canRegenerate: Bool { !isGenerating && !isAdopting && !isAdopted }
    var canAdopt: Bool { adopt != nil && finalReply != nil && !isGenerating && !isAdopting && !isAdopted }
    var canContinueInChat: Bool { !isGenerating && !isAdopting }

    func regenerate() {
        guard canRegenerate else { return }
        let identity = UUID()
        generation = identity
        error = nil
        isStopped = false
        adoptionError = nil
        isGenerating = true
        let generate = generate
        task = Task { @MainActor [weak self] in
            do {
                let reply = try await generate()
                try Task.checkCancellation()
                guard let self, self.generation == identity else { return }
                self.versions.append(reply)
                self.selectedVersionIndex = self.versions.count - 1
            } catch is CancellationError {
                guard let self, self.generation == identity else { return }
                self.isStopped = true
            } catch {
                guard let self, self.generation == identity else { return }
                self.error = ScholiumL10n.dynamicString(error.localizedDescription)
            }
            guard let self, self.generation == identity else { return }
            self.isGenerating = false
            self.task = nil
            self.generation = nil
        }
    }

    func stop() { task?.cancel() }
    func stopAndWait() async {
        let pending = task
        pending?.cancel()
        await pending?.value
    }
    func previousVersion() {
        guard !isAdopting && !isAdopted else { return }
        selectedVersionIndex = max(0, selectedVersionIndex - 1)
    }
    func nextVersion() {
        guard !isAdopting && !isAdopted else { return }
        selectedVersionIndex = min(max(0, versions.count - 1), selectedVersionIndex + 1)
    }

    func adoptSelectedVersion() {
        guard canAdopt, let adopt, let reply = finalReply else { return }
        isAdopting = true
        isStopped = false
        error = nil
        adoptionError = nil
        // An admitted editor replacement survives presentation dismissal. Keep
        // this owner alive through its outcome; no view-owned task can duplicate it.
        adoptionTask = Task { @MainActor [self] in
            defer {
                isAdopting = false
                adoptionTask = nil
            }
            do {
                try await adopt(reply)
                isAdopted = true
            } catch {
                adoptionError = ScholiumL10n.dynamicString(error.localizedDescription)
            }
        }
    }

    func continueInChat() {
        guard canContinueInChat else { return }
        handoff(finalReply)
    }
}
