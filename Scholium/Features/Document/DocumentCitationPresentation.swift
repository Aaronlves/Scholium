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
        let fields = ZoteroMarkdownFields(parsing: document)
        integrity = !fields.diagnostics.isEmpty ? .unresolved : fields.citationStateStale ? .stale : nil
        self.status = status
        self.canRefresh = integrity == .stale && canRefresh
        self.canOpenSource = integrity != nil && canOpenSource
    }
}

extension DocumentSessionModel {
    func citationPresentation(committedDocument: NoteDocument, editingIsAvailable: Bool) -> DocumentCitationPresentation {
        let document =
            isEditing
            ? NoteDocument(
                relativePath: committedDocument.relativePath, rawContent: retainedExactSource,
                citationSnapshot: editorSession.currentCitationSnapshot)
            : committedDocument
        return DocumentCitationPresentation(
            document: document, status: editorSession.citationStatus,
            canRefresh: isEditing && editingIsAvailable && !returnToReadAfterSave && !editorSession.isComposing
                && editorSession.interactionAvailability?.availableCommands.contains(.refreshCitations) == true,
            canOpenSource: editingIsAvailable && presentationMode != .source && !editorSession.isComposing && !returnToReadAfterSave)
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
