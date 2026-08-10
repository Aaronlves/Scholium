import Combine
import Foundation

/// Invalidates focused command presentation only when a command-facing fact
/// changes. It owns no product state and commands continue to read and mutate
/// the existing window and feature owners directly.
@MainActor
final class WindowCommandObservation: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private var cancellables: Set<AnyCancellable> = []

    init(
        shellState: WindowShellState,
        workspaceController: WindowWorkspaceController,
        discoveryController: DiscoveryController,
        documentController: DocumentController,
        documentNavigationHistoryController: DocumentNavigationHistoryController,
        workspaceProjectionController: WindowWorkspaceProjectionController,
        researchActionController: ResearchActionController
    ) {
        func changes<Value>(
            _ publisher: Published<Value>.Publisher
        ) -> AnyPublisher<Void, Never> {
            publisher
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher()
        }

        let discoveryChanges = discoveryController.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
        let documentNavigationChanges = documentNavigationHistoryController.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
        let commandChanges: [AnyPublisher<Void, Never>] = [
            changes(shellState.$libraryVisible),
            changes(shellState.$inspector),
            changes(shellState.$selectedWorkspace),
            changes(shellState.$documentTextScale),
            changes(shellState.$colorScheme),
            workspaceController.$state
                .dropFirst()
                .map { ($0.assignment, $0.registeredTriptychs) }
                .removeDuplicates { lhs, rhs in
                    lhs.0 == rhs.0 && lhs.1 == rhs.1
                }
                .map { _ in () }
                .eraseToAnyPublisher(),
            discoveryChanges,
            documentNavigationChanges,
            changes(documentController.$selectedDocument),
            changes(documentController.$snapshots),
            changes(documentController.$editingDocumentPath),
            changes(documentController.$currentPresentationMode),
            changes(documentController.$noteIdentityByPath),
            changes(workspaceProjectionController.$state),
            changes(researchActionController.$availability),
            changes(researchActionController.$availabilityTarget),
            changes(researchActionController.$isRefreshingAvailability),
            changes(researchActionController.$availabilityError),
            changes(researchActionController.$phase),
            changes(researchActionController.$cancellationRecoveries),
            changes(researchActionController.$pendingCancellationBarrierCount),
        ]

        Publishers.MergeMany(commandChanges)
            .sink { [weak self] in self?.advanceRevision() }
            .store(in: &cancellables)
    }

    private func advanceRevision() {
        revision = revision == .max ? 0 : revision + 1
    }
}
