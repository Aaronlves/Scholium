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
    private struct Entry: Sendable {
        let html: String
        let byteCount: Int
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
        semantic: MarkdownSemanticDocument? = nil
    ) -> String {
        guard DocumentFingerprint(content: source) == key.fingerprint else {
            return ""
        }
        nextAccess &+= 1
        if var cached = entries[key] {
            cached.access = nextAccess
            entries[key] = cached
            return cached.html
        }

        let document = NoteDocument(
            relativePath: key.relativePath,
            rawContent: source
        )
        let html = if let semantic {
            SafeMarkdownRenderer.render(document, semantic: semantic).htmlBody
        } else {
            SafeMarkdownRenderer.render(document).htmlBody
        }
        let byteCount = html.utf8.count
        guard byteCount <= maximumBytesPerWorkspace else { return html }
        entries[key] = Entry(html: html, byteCount: byteCount, access: nextAccess)
        evictIfNeeded(workspaceID: key.workspaceID)
        return html
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    func entryCount(workspaceID: UUID?) -> Int {
        entries.keys.filter { $0.workspaceID == workspaceID }.count
    }

    private func evictIfNeeded(workspaceID: UUID?) {
        while true {
            let workspaceEntries = entries.filter { $0.key.workspaceID == workspaceID }
            let byteCount = workspaceEntries.values.reduce(0) { $0 + $1.byteCount }
            guard workspaceEntries.count > maximumEntriesPerWorkspace
                    || byteCount > maximumBytesPerWorkspace,
                  let oldest = workspaceEntries.min(by: { $0.value.access < $1.value.access })
            else { return }
            entries[oldest.key] = nil
        }
    }
}
