import ScholiumContracts
import AppKit
import Combine
import Foundation

/// Observable macOS adapter over Application-owned style persistence.
@MainActor
final class CSSSnippetStore: ObservableObject {
    @Published private(set) var snippets: [CSSSnippetRecord] = []
    @Published private(set) var validationErrors: [UUID: String] = [:]
    @Published private(set) var readCSS = ""
    @Published private(set) var livePreviewCSS = ""
    @Published private(set) var safeModeReason: String?
    @Published private(set) var storeError: String?
    @Published private(set) var canModify = true

    private let operations: any StyleUseCases

    init(operations: any StyleUseCases) {
        self.operations = operations
        Task { await refresh() }
    }

    var enabledCount: Int { snippets.lazy.filter(\.isEnabled).count }

    func refresh() async {
        do {
            apply(try await operations.styleSnapshot())
        } catch {
            storeError = error.localizedDescription
        }
    }

    func importSnippet(from sourceURL: URL) async throws {
        apply(try await operations.importStyleSnippet(from: sourceURL))
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        perform { try await self.operations.setStyleSnippetEnabled(enabled, id: id) }
    }

    func move(_ id: UUID, by offset: Int) {
        perform { try await self.operations.moveStyleSnippet(id, by: offset) }
    }

    func rename(_ id: UUID, to requestedName: String) {
        perform { try await self.operations.renameStyleSnippet(id, to: requestedName) }
    }

    func duplicate(_ id: UUID) {
        perform { try await self.operations.duplicateStyleSnippet(id) }
    }

    func reload(_ id: UUID) {
        perform { try await self.operations.reloadStyleSnippet(id) }
    }

    func remove(_ id: UUID) {
        perform { try await self.operations.removeStyleSnippet(id) }
    }

    func disableAll() {
        perform { try await self.operations.disableAllStyleSnippets() }
    }

    func enterSafeMode(after reason: String) {
        perform { try await self.operations.enterStyleSafeMode(reason: reason) }
    }

    func editManagedCopy(_ id: UUID) {
        Task {
            do {
                if let url = try await operations.managedStyleSnippetURL(id) {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                storeError = error.localizedDescription
            }
        }
    }

    func revealManagedFolder() {
        Task {
            do {
                let url = try await operations.managedStylesLocation()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                storeError = error.localizedDescription
            }
        }
    }

    private func perform(
        _ operation: @escaping @Sendable () async throws -> StyleSnapshot
    ) {
        Task {
            do {
                apply(try await operation())
            } catch {
                storeError = error.localizedDescription
            }
        }
    }

    private func apply(_ snapshot: StyleSnapshot) {
        snippets = snapshot.snippets
        validationErrors = snapshot.validationErrors
        readCSS = snapshot.readCSS
        livePreviewCSS = snapshot.livePreviewCSS
        safeModeReason = snapshot.safeModeReason
        storeError = snapshot.storeError
        canModify = snapshot.canModify
    }
}
