import ScholiumContracts
import SwiftUI

/// Both presentations observe the same originating window's Search owners.
/// This host refreshes completion and saved-query projections in either window.
struct ResearchSearchSurface<Library: View>: View {
    let presentation: SearchPresentation
    let revealDocument: () -> Void
    let library: Library
    @ObservedObject private var searchController: WindowSearchController
    @ObservedObject private var discoveryController: DiscoveryController
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController

    init(
        controller: DiscoveryController, searchController: WindowSearchController,
        shellState: WindowShellState, workspaceProjectionController: WindowWorkspaceProjectionController,
        presentation: SearchPresentation,
        revealDocument: @escaping () -> Void,
        @ViewBuilder library: () -> Library
    ) {
        self.presentation = presentation
        self.revealDocument = revealDocument
        self.library = library()
        _searchController = ObservedObject(wrappedValue: searchController)
        _discoveryController = ObservedObject(wrappedValue: controller)
        _shellState = ObservedObject(wrappedValue: shellState)
        _workspaceProjectionController = ObservedObject(wrappedValue: workspaceProjectionController)
    }

    var body: some View {
        ResearchSearchView(
            controller: discoveryController, searchController: searchController,
            context: searchContext, presentation: presentation
        ) { library }
    }

    private var searchContext: ResearchSearchContext {
        ResearchSearchContext(
            completionContext: searchCompletionContext,
            savedSearches: searchController.savedSearches,
            savedSearchLoadFailure: searchController.savedSearchLoadFailure,
            recoverSavedSearches: {
                await searchController.recoverSavedSearches()
            },
            refresh: { await searchController.refresh() },
            dismiss: { searchController.dismiss() },
            save: { searchController.saveCurrent(named: $0) },
            run: { searchController.run($0) },
            rename: { searchController.rename($0, to: $1) },
            move: { searchController.move($0, by: $1) },
            delete: { searchController.delete($0) },
            openNote: { result in
                Task {
                    if await searchController.open(result, disposition: .replaceCurrent),
                        searchController.presentation == .advanced
                    {
                        revealDocument()
                    }
                }
            }
        )
    }

    private var searchCompletionContext: SearchCompletionContext {
        let options = workspaceProjectionController.propertyCompletionOptions(scope: searchController.criteria.scope)
        return SearchCompletionContext(propertyKeys: options.keys, propertyValues: options.valuesByKey)

    }

}
