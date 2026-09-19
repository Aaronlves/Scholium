import SwiftUI

struct ScholiumSearchActions {
    let advanced: () -> Void
}

struct ScholiumApplicationBootstrapStatus: Equatable, Sendable {
    let isReady: Bool
}

struct ScholiumApplicationBootstrapStatusFocusedKey: FocusedValueKey {
    typealias Value = ScholiumApplicationBootstrapStatus
}

struct ScholiumSearchActionsFocusedKey: FocusedValueKey {
    typealias Value = ScholiumSearchActions
}

struct ScholiumWorkspaceWindowActionsFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceWindowActions
}

struct ScholiumFocusedEditorActions {
    let documentID: String
    let isComposing: Bool
    let allowsReplace: Bool
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let presentFind: () -> Void
    let presentReplace: () -> Void
    let findNext: () -> Void
    let findPrevious: () -> Void
    let useSelectionForFind: () -> Void
    let importImage: () -> Void
    let indexImage: () -> Void
    let canAttachDocument: Bool
    let attachDocumentCopy: () -> Void
    let referenceOriginalDocument: () -> Void
    var canEditFrontmatter = false
    var goToFrontmatter: () -> Void = {}
}

struct ScholiumFocusedEditorActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedEditorActions
}

extension FocusedValues {
    var scholiumApplicationBootstrapStatus: ScholiumApplicationBootstrapStatus? {
        get { self[ScholiumApplicationBootstrapStatusFocusedKey.self] }
        set { self[ScholiumApplicationBootstrapStatusFocusedKey.self] = newValue }
    }

    var scholiumSearchActions: ScholiumSearchActions? {
        get { self[ScholiumSearchActionsFocusedKey.self] }
        set { self[ScholiumSearchActionsFocusedKey.self] = newValue }
    }

    var scholiumWorkspaceWindowActions: WorkspaceWindowActions? {
        get { self[ScholiumWorkspaceWindowActionsFocusedKey.self] }
        set { self[ScholiumWorkspaceWindowActionsFocusedKey.self] = newValue }
    }

    var scholiumEditorActions: ScholiumFocusedEditorActions? {
        get { self[ScholiumFocusedEditorActionsKey.self] }
        set { self[ScholiumFocusedEditorActionsKey.self] = newValue }
    }
}
