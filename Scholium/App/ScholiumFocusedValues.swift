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
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let importImage: () -> Void
    let indexImage: () -> Void
    let canAttachDocument: Bool
    let attachDocumentCopy: () -> Void
    let referenceOriginalDocument: () -> Void
    var canEditFrontmatter = false
    var goToFrontmatter: () -> Void = {}
}

enum ScholiumEditorCommandRegistrationChange: Equatable {
    case activation
    case refresh
}

/// A Note view owns its callbacks. The Window keeps only a weak reference to
/// this port, so a retained editor cannot keep an obsolete hosting view alive.
@MainActor
final class ScholiumEditorCommandPort: ObservableObject {
    let token = UUID()
    weak var session: DocumentSessionModel?
    var target: DocumentEditingTarget?
    var actions: ScholiumFocusedEditorActions?
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

}
