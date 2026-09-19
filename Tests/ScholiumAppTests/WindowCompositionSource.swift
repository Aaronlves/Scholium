import Foundation

/// The window composition root is a directory, not a single file: the app
/// entry point, its scenes, its commands and `WindowModel` with its extensions
/// all live under `Scholium/App`. Architecture tests that read the root as
/// text read every file it is written across, so that splitting a behaviour
/// into its own file cannot quietly retire the assertion guarding it.
enum WindowCompositionSource {
    /// Every file the former `Scholium/App/ScholiumApp.swift` was split into,
    /// in the order a reader would meet them.
    static let relativePaths: [String] = [
        "Scholium/App/ScholiumApplicationDelegate.swift",
        "Scholium/App/ScholiumWindowScenes.swift",
        "Scholium/App/ScholiumFocusedValues.swift",
        "Scholium/App/ScholiumCommands.swift",
        "Scholium/App/Window/WindowModelObservers.swift",
        "Scholium/App/ScholiumApp.swift",
        "Scholium/App/Window/WindowNoteIdentityActions.swift",
        "Scholium/App/Window/WindowDocumentTransitionActions.swift",
        "Scholium/App/Window/WindowIntentActions.swift",
        "Scholium/App/Window/WindowPerformanceHarness.swift",
        "Scholium/App/Window/WindowLibraryFilters.swift",
        "Scholium/App/Window/WindowDocumentTabActions.swift",
        "Scholium/App/Window/WindowSessionRestoration.swift",
        "Scholium/App/Window/WindowTriptychConfiguration.swift",
        "Scholium/App/Window/WindowOperationReporting.swift",
        "Scholium/App/Window/WindowWorkspaceOpeningActions.swift",
        "Scholium/App/Window/WindowLibraryPublicationActions.swift",
        "Scholium/App/Window/WindowRecoveryActions.swift",
        "Scholium/App/Window/WindowDocumentOpeningActions.swift",
        "Scholium/App/Window/WindowDocumentTabProjection.swift",
        "Scholium/App/Window/WindowWorkspaceProjectionActions.swift",
    ]

    /// The composition root read as one text.
    static func text(at repositoryRoot: URL) throws -> String {
        try relativePaths
            .map {
                try String(
                    contentsOf: repositoryRoot.appendingPathComponent($0),
                    encoding: .utf8
                )
            }
            .joined(separator: "\n")
    }
}
