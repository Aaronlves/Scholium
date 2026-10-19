import ScholiumContracts

/// A source-derived value for the existing Document notice stack. An editor's
/// most recent admitted status is presentation, never mutation authority.
struct DocumentCitationPresentation: Equatable {
    enum Integrity: Equatable { case stale, unresolved }

    let integrity: Integrity?
    let status: String?
    let canRefresh: Bool
    let canOpenSource: Bool
    var isVisible: Bool { integrity != nil || status != nil }

    init(fields: ZoteroMarkdownFields, status: String?, canRefresh: Bool, canOpenSource: Bool) {
        self.init(
            citationState: !fields.diagnostics.isEmpty ? .unresolved : fields.citationStateStale ? .stale : .current,
            status: status, canRefresh: canRefresh, canOpenSource: canOpenSource)
    }

    init(citationState: MarkdownEditorCitationState, status: String?, canRefresh: Bool, canOpenSource: Bool) {
        integrity =
            switch citationState {
            case .current: nil
            case .stale: .stale
            case .unresolved: .unresolved
            }
        self.status = status
        self.canRefresh = integrity == .stale && canRefresh
        self.canOpenSource = integrity != nil && canOpenSource
    }
}

/// One disposable source-derived value per Document owner. Committed source
/// uses its existing exact-byte fingerprint; the retained mirror advances a
/// local version on every assignment, including canonically equal Unicode.
@MainActor
final class DocumentCitationFieldsCache {
    enum SourceRevision: Equatable {
        case committed(DocumentFingerprint)
        case retained(UInt64)
    }

    private struct Key: Equatable {
        let relativePath: String
        let sourceRevision: SourceRevision
        // Revision is the companion file's exact-byte fingerprint. Compare
        // the complete immutable snapshot as well: identity, source binding,
        // status and decoded data all participate, without re-encoding it.
        let citationSnapshot: ZoteroCitationSnapshot?
    }

    private var entry: (key: Key, fields: ZoteroMarkdownFields)?

    func fields(
        relativePath: String, sourceRevision: SourceRevision,
        citationSnapshot: ZoteroCitationSnapshot?, prepared: ZoteroMarkdownFields?,
        document: () -> NoteDocument
    ) -> ZoteroMarkdownFields {
        let key = Key(relativePath: relativePath, sourceRevision: sourceRevision, citationSnapshot: citationSnapshot)
        if let entry, entry.key == key { return entry.fields }
        let source = document()
        // Workspace cached semantics deliberately exclude companion-bearing
        // documents. Keep that same admission boundary for prepared fields.
        let fields =
            if citationSnapshot == nil, let prepared, prepared.fingerprint == source.fingerprint {
                prepared
            } else {
                ZoteroMarkdownFields(parsing: source)
            }
        entry = (key, fields)
        return fields
    }

    func removeAll() { entry = nil }
}

extension DocumentSessionModel {
    func citationPresentation(
        committedDocument: NoteDocument, committedFields: ZoteroMarkdownFields?, editingIsAvailable: Bool
    ) -> DocumentCitationPresentation {
        PerformanceProbe.shared.measureNoteOpeningWork(
            .citationPresentation, documentID: committedDocument.relativePath, editorSessionID: editorSession.sessionID
        ) {
            let canRefresh =
                isEditing && editingIsAvailable && !returnToReadAfterSave && !editorSession.isComposing
                && editorSession.interactionAvailability?.availableCommands.contains(.refreshCitations) == true
            let canOpenSource = editingIsAvailable && presentationMode != .source && !editorSession.isComposing && !returnToReadAfterSave
            // Keep the last admitted notice while the next interaction is in
            // flight. Commands independently capture and validate current source.
            if isEditing, editorSession.documentID == editorSession.bridgeDocumentID,
                let citationState = editorSession.interactionAvailability?.citationState
            {
                return DocumentCitationPresentation(
                    citationState: citationState, status: editorSession.citationStatus,
                    canRefresh: canRefresh, canOpenSource: canOpenSource)
            }
            let fields: ZoteroMarkdownFields
            if isEditing, let checkedFields = editorSession.citationFields(forDocumentID: editorSession.bridgeDocumentID) {
                fields = checkedFields
            } else if isEditing {
                let companion = editorSession.currentCitationSnapshot
                fields = citationFieldsCache.fields(
                    relativePath: committedDocument.relativePath, sourceRevision: .retained(retainedCitationSourceRevision),
                    citationSnapshot: companion, prepared: nil
                ) {
                    NoteDocument(relativePath: committedDocument.relativePath, rawContent: retainedExactSource, citationSnapshot: companion)
                }
            } else {
                fields = citationFieldsCache.fields(
                    relativePath: committedDocument.relativePath, sourceRevision: .committed(committedDocument.fingerprint),
                    citationSnapshot: committedDocument.citationSnapshot, prepared: committedFields
                ) { committedDocument }
            }
            return DocumentCitationPresentation(
                fields: fields, status: editorSession.citationStatus,
                canRefresh: canRefresh, canOpenSource: canOpenSource)
        }
    }
}

extension ExternalMarkdownWindowModel {
    var citationPresentation: DocumentCitationPresentation? {
        guard let snapshot else { return nil }
        let canRefresh =
            mode != .read && permitsSourceActions && !isBusy && !editorSession.isComposing && inputResumeError == nil
            && editorSession.interactionAvailability?.availableCommands.contains(.refreshCitations) == true
        let canOpenSource = mode != .source && canSelectMode(.source)
        if mode != .read, editorSession.documentID == documentID,
            let citationState = editorSession.interactionAvailability?.citationState
        {
            return DocumentCitationPresentation(
                citationState: citationState, status: editorSession.citationStatus,
                canRefresh: canRefresh, canOpenSource: canOpenSource)
        }
        let fields: ZoteroMarkdownFields
        if mode != .read, let checkedFields = editorSession.citationFields(forDocumentID: documentID) {
            fields = checkedFields
        } else {
            fields = citationFieldsCache.fields(
                relativePath: title, sourceRevision: .committed(snapshot.fingerprint),
                citationSnapshot: nil, prepared: readProjection?.citationFields
            ) { NoteDocument(relativePath: title, rawContent: snapshot.source) }
        }
        return DocumentCitationPresentation(
            fields: fields, status: editorSession.citationStatus,
            canRefresh: canRefresh, canOpenSource: canOpenSource)
    }
}
