import Foundation
import ScholiumContracts
import SwiftUI

/// Serial, latest-pending projection. Parsing never runs on the UI actor.
/// An append may publish its completed prefix while the next snapshot renders;
/// a replacement or cancelled lifetime cannot publish an obsolete snapshot.
@MainActor final class AgentChatReplyProjection: ObservableObject {
    struct Snapshot: Sendable {
        let document: NoteDocument
        let html: String
        nonisolated init(_ source: String) {
            document = NoteDocument(relativePath: "Reply.md", rawContent: source)
            html = SafeMarkdownRenderer.render(document).htmlBody
        }
    }
    @Published private(set) var snapshot: Snapshot?
    private var pending: String?
    private var requested: String?
    private var worker: Task<Void, Never>?
    private var generation = 0
    private let render: @Sendable (String) async -> Snapshot

    init(render: @escaping @Sendable (String) async -> Snapshot = { source in
        await Task.detached(priority: .userInitiated) { Snapshot(source) }.value
    }) { self.render = render }

    func submit(_ source: String) {
        guard requested != source || worker == nil && snapshot?.document.rawContent != source else { return }
        requested = source
        pending = source
        guard worker == nil else { return }
        let generation = generation
        let render = render
        worker = Task { [weak self] in
            while !Task.isCancelled, let source = self?.pending {
                self?.pending = nil
                let result = await render(source)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if let requested = self.requested, requested == source || requested.hasPrefix(source) {
                    self.snapshot = result
                }
            }
            guard let self, self.generation == generation else { return }
            self.worker = nil
        }
    }
    func cancel() {
        generation += 1
        worker?.cancel()
        worker = nil
        requested = nil
        pending = nil
    }
}
