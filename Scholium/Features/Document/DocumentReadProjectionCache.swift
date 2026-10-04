import Foundation
import ScholiumContracts

struct DocumentReadProjectionKey: Hashable, Sendable {
    static let rendererContractVersion = 1

    let workspaceID: UUID?
    let stableTarget: String
    let relativePath: String
    let fingerprint: DocumentFingerprint
    let rendererContractVersion: Int

    init(
        workspaceID: UUID?,
        stableTarget: String,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        rendererContractVersion: Int = Self.rendererContractVersion
    ) {
        self.workspaceID = workspaceID
        self.stableTarget = stableTarget
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.rendererContractVersion = rendererContractVersion
    }
}

/// Bounded derived HTML. Exact Markdown remains the only writable authority.
actor DocumentReadProjectionCache {
    #if DEBUG
        struct QADiagnosticStats: Sendable {
            let entryCount: Int
            let htmlUTF8ByteCount: Int
        }
    #endif

    private struct ImageRevision: Equatable, Sendable {
        let mimeType: String
        let fingerprint: DocumentFingerprint
    }

    private struct Entry: Sendable {
        let html: String
        let byteCount: Int
        let imageRevisions: [String: ImageRevision]
        var access: UInt64
    }

    private let maximumEntriesPerWorkspace: Int
    private let maximumBytesPerWorkspace: Int
    private var entries: [DocumentReadProjectionKey: Entry] = [:]
    private var nextAccess: UInt64 = 0

    init(
        maximumEntriesPerWorkspace: Int = 32,
        maximumBytesPerWorkspace: Int = 16 * 1_024 * 1_024
    ) {
        self.maximumEntriesPerWorkspace = maximumEntriesPerWorkspace
        self.maximumBytesPerWorkspace = maximumBytesPerWorkspace
    }

    func html(
        for key: DocumentReadProjectionKey,
        source: String,
        semantic: MarkdownSemanticDocument? = nil,
        embeddedImages: [String: RenderedMarkdownImage] = [:]
    ) -> String {
        guard DocumentFingerprint(content: source) == key.fingerprint else {
            return ""
        }
        // Keep one requested revision per Note. Old HTML can be regenerated
        // after Undo; retaining every save otherwise crowds out other Notes.
        // Do this even when the new projection is too large to cache.
        for previous in entries.keys.filter({
            $0.workspaceID == key.workspaceID
                && $0.stableTarget == key.stableTarget
                && $0.relativePath == key.relativePath
                && $0 != key
        }) {
            entries.removeValue(forKey: previous)
        }
        let imageRevisions = embeddedImages.mapValues {
            ImageRevision(mimeType: $0.mimeType, fingerprint: DocumentFingerprint(data: $0.data))
        }
        nextAccess &+= 1
        if var cached = entries[key], cached.imageRevisions == imageRevisions {
            cached.access = nextAccess
            entries[key] = cached
            return cached.html
        }
        entries.removeValue(forKey: key)

        let document = NoteDocument(
            relativePath: key.relativePath,
            rawContent: source
        )
        let html =
            if let semantic {
                SafeMarkdownRenderer.render(document, semantic: semantic, embeddedImages: embeddedImages).htmlBody
            } else {
                SafeMarkdownRenderer.render(document, embeddedImages: embeddedImages).htmlBody
            }
        let byteCount = html.utf8.count
        guard byteCount <= maximumBytesPerWorkspace else { return html }
        entries[key] = Entry(html: html, byteCount: byteCount, imageRevisions: imageRevisions, access: nextAccess)
        evictIfNeeded(workspaceID: key.workspaceID)
        return html
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    func entryCount(workspaceID: UUID?) -> Int {
        entries.keys.filter { $0.workspaceID == workspaceID }.count
    }

    func retainedHTMLByteCount(workspaceID: UUID?) -> Int {
        entries.reduce(0) { $0 + ($1.key.workspaceID == workspaceID ? $1.value.byteCount : 0) }
    }

    #if DEBUG
        func qaDiagnosticStats() -> QADiagnosticStats {
            QADiagnosticStats(
                entryCount: entries.count,
                htmlUTF8ByteCount: entries.values.reduce(0) { $0 + $1.byteCount }
            )
        }
    #endif

    private func evictIfNeeded(workspaceID: UUID?) {
        while true {
            let workspaceEntries = entries.filter { $0.key.workspaceID == workspaceID }
            let byteCount = workspaceEntries.values.reduce(0) { $0 + $1.byteCount }
            guard
                workspaceEntries.count > maximumEntriesPerWorkspace
                    || byteCount > maximumBytesPerWorkspace,
                let oldest = workspaceEntries.min(by: { $0.value.access < $1.value.access })
            else { return }
            entries[oldest.key] = nil
        }
    }
}
