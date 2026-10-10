import ScholiumContracts

/// A source-derived value for the existing Document notice stack. Review uses
/// committed Markdown; an active editor uses its retained exact buffer.
struct DocumentCitationPresentation: Equatable {
    enum Integrity: Equatable { case stale, unresolved }

    let integrity: Integrity?
    let status: String?
    let canRefresh: Bool
    let canOpenSource: Bool
    var isVisible: Bool { integrity != nil || status != nil }

    init(document: NoteDocument, status: String?, canRefresh: Bool, canOpenSource: Bool) {
        self.init(fields: ZoteroMarkdownFields(parsing: document), status: status, canRefresh: canRefresh, canOpenSource: canOpenSource)
    }

    init(fields: ZoteroMarkdownFields, status: String?, canRefresh: Bool, canOpenSource: Bool) {
        integrity = !fields.diagnostics.isEmpty ? .unresolved : fields.citationStateStale ? .stale : nil
        self.status = status
        self.canRefresh = integrity == .stale && canRefresh
        self.canOpenSource = integrity != nil && canOpenSource
    }
}

extension DocumentSessionModel {
    func citationPresentation(committedDocument: NoteDocument, editingIsAvailable: Bool) -> DocumentCitationPresentation {
        PerformanceProbe.shared.measureNoteOpeningWork(
            .citationPresentation, documentID: committedDocument.relativePath, editorSessionID: editorSession.sessionID
        ) {
            let fields: ZoteroMarkdownFields
            if isEditing, let checkedFields = editorSession.citationFields(forDocumentID: editorSession.bridgeDocumentID) {
                fields = checkedFields
            } else {
                let document =
                    isEditing
                    ? NoteDocument(
                        relativePath: committedDocument.relativePath, rawContent: retainedExactSource,
                        citationSnapshot: editorSession.currentCitationSnapshot)
                    : committedDocument
                fields = ZoteroMarkdownFields(parsing: document)
            }
            return DocumentCitationPresentation(
                fields: fields, status: editorSession.citationStatus,
                canRefresh: isEditing && editingIsAvailable && !returnToReadAfterSave && !editorSession.isComposing
                    && editorSession.interactionAvailability?.availableCommands.contains(.refreshCitations) == true,
                canOpenSource: editingIsAvailable && presentationMode != .source && !editorSession.isComposing && !returnToReadAfterSave)
        }
    }
}

extension ExternalMarkdownWindowModel {
    var citationPresentation: DocumentCitationPresentation? {
        guard let snapshot else { return nil }
        let source = mode != .read && editorSession.documentID == documentID ? editorSession.checkedSource : snapshot.source
        return DocumentCitationPresentation(
            document: NoteDocument(relativePath: title, rawContent: source), status: editorSession.citationStatus,
            canRefresh: mode != .read && permitsSourceActions && !isBusy && !editorSession.isComposing && inputResumeError == nil
                && editorSession.interactionAvailability?.availableCommands.contains(.refreshCitations) == true,
            canOpenSource: mode != .source && canSelectMode(.source))
    }
}
