import Foundation

public enum NoteRestructureOperation: String, Codable, Hashable, Sendable {
    case move, copy, merge
}

public enum NoteRestructureDestination: Codable, Hashable, Sendable {
    case existing(NoteMutationTarget)
    case newNote(relativePath: String)
}

public struct NoteRestructureRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let source: NoteMutationTarget
    public let selectionUTF8: Range<Int>?
    public let destination: NoteRestructureDestination
    public let operation: NoteRestructureOperation

    public init(
        id: UUID = UUID(), source: NoteMutationTarget, selectionUTF8: Range<Int>?, destination: NoteRestructureDestination, operation: NoteRestructureOperation
    ) {
        self.id = id
        self.source = source
        self.selectionUTF8 = selectionUTF8
        self.destination = destination
        self.operation = operation
    }
}

/// Exact before/after source is retained only as machine-local transaction recovery evidence.
/// A nil before creates a new file; a nil after uses the existing system-Trash owner.
public struct NoteRestructureFileEdit: Codable, Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let before: String?
    public let after: String?
    public var expectedRevision: DocumentFingerprint? { before.map { DocumentFingerprint(data: Data($0.utf8)) } }
    public var intendedRevision: DocumentFingerprint? { after.map { DocumentFingerprint(data: Data($0.utf8)) } }

    public init(note: VaultQualifiedNoteID, before: String?, after: String?) {
        self.note = note
        self.before = before
        self.after = after
    }
}

public struct NoteRestructurePreview: Hashable, Sendable {
    public let request: NoteRestructureRequest
    public let destination: VaultQualifiedNoteID
    public let edits: [NoteRestructureFileEdit]
    public let movedAnchorIDs: [String]
    public let observedRevisions: [VaultQualifiedNoteID: DocumentFingerprint]

    public init(
        request: NoteRestructureRequest, destination: VaultQualifiedNoteID, edits: [NoteRestructureFileEdit], movedAnchorIDs: [String],
        observedRevisions: [VaultQualifiedNoteID: DocumentFingerprint]
    ) {
        self.request = request
        self.destination = destination
        self.edits = edits
        self.movedAnchorIDs = movedAnchorIDs
        self.observedRevisions = observedRevisions
    }
}

public struct NoteRestructureCommit: Sendable {
    public let destination: VaultQualifiedNoteID
    public let documents: [VaultQualifiedNoteID: NoteDocument]
    public let removedNotes: [VaultQualifiedNoteID]

    public init(destination: VaultQualifiedNoteID, documents: [VaultQualifiedNoteID: NoteDocument], removedNotes: [VaultQualifiedNoteID]) {
        self.destination = destination
        self.documents = documents
        self.removedNotes = removedNotes
    }
}

public enum NoteRestructureError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}
