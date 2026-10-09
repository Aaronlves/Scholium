import Foundation
import ScholiumContracts

/// Immutable Note metadata for Chat presentation. Capture and source authority
/// remain with the window's document owner.
final class AgentChatNoteCatalog {
    let orderedNotes: [WorkspaceCatalogNote]
    let materialCandidates: [AgentChatComposerCandidate]
    private let notesByID: [UUID: WorkspaceCatalogNote]

    init(notes: [WorkspaceCatalogNote]) {
        var valid: [(offset: Int, note: WorkspaceCatalogNote)] = []
        var indexed: [UUID: WorkspaceCatalogNote] = [:]
        for (offset, note) in notes.enumerated() {
            guard let id = note.reference.stableNoteID.flatMap(UUID.init(uuidString:)) else { continue }
            valid.append((offset, note))
            // Preserve the activity resolver's original first-match rule.
            if indexed[id] == nil { indexed[id] = note }
        }
        orderedNotes = valid.sorted {
            let order = $0.note.title.localizedStandardCompare($1.note.title)
            return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
        }.map { $0.note }
        materialCandidates = AgentChatComposerCatalog.materials(preorderedNotes: orderedNotes)
        notesByID = indexed
    }

    func note(_ id: UUID) -> WorkspaceCatalogNote? { notesByID[id] }

    func matchingNotes(query: String) -> [WorkspaceCatalogNote] {
        let needle = AgentChatSearch.query(query)
        guard !needle.isEmpty else { return orderedNotes }
        return orderedNotes.filter {
            AgentChatSearch.matches($0.title, query: needle)
                || AgentChatSearch.matches($0.reference.relativePath, query: needle)
        }
    }
}

/// One lazy projection retained by a window's Chat presentation. Comparing the
/// exact current cohort avoids sorting again for draft and streaming updates.
@MainActor
final class AgentChatNoteCatalogCache {
    private var notes: [WorkspaceCatalogNote]?
    private var localeIdentifier: String?
    private var value: AgentChatNoteCatalog?

    func catalog(
        notes: [WorkspaceCatalogNote], localeIdentifier: String = Locale.current.identifier
    ) -> AgentChatNoteCatalog {
        if let previous = self.notes, let value,
            self.localeIdentifier == localeIdentifier, Self.matches(previous, notes)
        {
            return value
        }
        let value = AgentChatNoteCatalog(notes: notes)
        self.notes = notes
        self.localeIdentifier = localeIdentifier
        self.value = value
        return value
    }

    private static func matches(_ lhs: [WorkspaceCatalogNote], _ rhs: [WorkspaceCatalogNote]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Array values share immutable storage until a participant changes an
        // element. Compare addresses only within both pointer lifetimes.
        let sameStorage = lhs.withUnsafeBufferPointer { lhs in
            rhs.withUnsafeBufferPointer { rhs in lhs.baseAddress == rhs.baseAddress }
        }
        if sameStorage { return true }
        for (lhs, rhs) in zip(lhs, rhs) {
            guard lhs.reference.vaultID == rhs.reference.vaultID,
                lhs.reference.vaultRole == rhs.reference.vaultRole,
                lhs.fingerprint == rhs.fingerprint,
                exact(lhs.reference.vaultName, rhs.reference.vaultName),
                exact(lhs.reference.relativePath, rhs.reference.relativePath),
                exact(lhs.reference.stableNoteID, rhs.reference.stableNoteID),
                exact(lhs.title, rhs.title), exact(lhs.aliases, rhs.aliases),
                exact(lhs.authors, rhs.authors), exact(lhs.publicationDate, rhs.publicationDate),
                exact(lhs.validationWarnings, rhs.validationWarnings)
            else { return false }
        }
        return true
    }

    private static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func exact(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): exact(lhs, rhs)
        default: false
        }
    }

    private static func exact(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { exact($0.0, $0.1) }
    }
}
