import Foundation
import ScholiumContracts
import SwiftUI

/// Serial, latest-pending projection. Parsing never runs on the UI actor.
/// An append may publish its completed prefix while the next snapshot renders;
/// a replacement or cancelled lifetime cannot publish an obsolete snapshot.
@MainActor final class AgentChatReplyProjection: ObservableObject {
    struct Request: Equatable, Sendable {
        let identity: ScholiumExactUTF8.SourceIdentity
        let isStreaming: Bool
        var source: String { identity.source }
        init(_ source: String, isStreaming: Bool = false) {
            identity = .init(source)
            self.isStreaming = isStreaming
        }
    }
    struct Snapshot: Sendable {
        let request: Request
        let document: NoteDocument
        let html: String
        let previewText: String
        let presentationRevision: String
        let objects: [String: RenderedMarkdownObject]
        nonisolated init(_ request: Request, displaySource: String? = nil) {
            self.request = request
            document = NoteDocument(relativePath: "Reply.md", rawContent: request.source)
            let display = displaySource ?? request.source
            let projected = NoteDocument(relativePath: "Reply.md", rawContent: display)
            let rendered = SafeMarkdownRenderer.render(projected)
            // An incomplete destination is an inert label. Its decorative slot
            // matches a completed link, but it grants neither navigation nor a
            // source locator. The synthetic destination never leaves projection.
            let exactDisplay = ScholiumExactUTF8.equal(display, request.source)
            let projectedHTML =
                exactDisplay
                ? rendered.htmlBody
                : rendered.htmlBody.replacingOccurrences(
                    of: #" data-source-(?:line|end-line|utf16-start|utf16-end|utf8-start|utf8-end)="[0-9]+""#,
                    with: "", options: .regularExpression)
            html =
                exactDisplay
                ? projectedHTML
                : projectedHTML.replacingOccurrences(
                    of: "href=\"scholium-note:streamdown%3Aincomplete-link\"",
                    with: "data-scholium-pending-link=\"\" aria-disabled=\"true\"")
            previewText = MarkdownVisibleText.render(display)
            presentationRevision =
                document.fingerprint.sha256 + (request.isStreaming ? ":stream:" : ":settled:")
                + DocumentFingerprint(content: html).sha256
            // Only objects independently parsed from exact received bytes may
            // provide Copy/Expand payloads. Speculative syntax is never source.
            let exactObjects =
                exactDisplay
                ? rendered.objects : rendered.objects.isEmpty ? [] : SafeMarkdownRenderer.render(document).objects
            objects = Dictionary(uniqueKeysWithValues: exactObjects.map { ($0.id, $0) })
        }
    }
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var failure: String?
    private var pending: Request?
    private var requested: Request?
    private var worker: Task<Void, Never>?
    private var generation = 0
    private let render: @Sendable (Request) async throws -> Snapshot

    init(
        render: @escaping @Sendable (Request) async throws -> Snapshot = { request in
            let display = request.isStreaming ? try await AgentChatStreamingMarkdown.shared.complete(request.source) : request.source
            return await Task.detached(priority: .userInitiated) { Snapshot(request, displaySource: display) }.value
        }
    ) { self.render = render }

    func submit(_ source: String, isStreaming: Bool = false) {
        let request = Request(source, isStreaming: isStreaming)
        let isRequested = requested == request
        let isRendered = snapshot?.request == request
        guard !isRequested || worker == nil && !isRendered else { return }
        requested = request
        pending = request
        failure = nil
        guard worker == nil else { return }
        let generation = generation
        let render = render
        worker = Task { [weak self] in
            while !Task.isCancelled, let request = self?.pending {
                self?.pending = nil
                do {
                    let result = try await render(request)
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    if let requested = self.requested, requested.isStreaming == request.isStreaming,
                        ScholiumExactUTF8.hasPrefix(requested.source, request.source)
                    {
                        self.snapshot = result
                    }
                } catch {
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    if self.requested == request { self.failure = error.localizedDescription }
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
        failure = nil
    }
}
