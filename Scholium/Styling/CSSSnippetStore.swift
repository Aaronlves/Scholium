import ScholiumContracts
import AppKit
import Combine
import Darwin
import Foundation

/// Observable macOS adapter over Application-owned style persistence.
@MainActor
final class CSSSnippetStore: ObservableObject {
    @Published private(set) var appearanceProfiles: [DocumentAppearanceProfile] = []
    @Published private(set) var appearanceReloadRevision = 0
    @Published private(set) var selectedAppearanceProfileID: UUID?
    @Published private(set) var appearanceCSS = ""
    @Published private(set) var snippets: [CSSSnippetRecord] = []
    @Published private(set) var validationErrors: [UUID: String] = [:]
    @Published private(set) var readCSS = ""
    @Published private(set) var livePreviewCSS = ""
    @Published private(set) var safeModeReason: String?
    @Published private(set) var storeError: String?
    @Published private(set) var canModify = true

    private let operations: any StyleUseCases
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var snippetWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var refreshTask: Task<Void, Never>?

    init(operations: any StyleUseCases) {
        self.operations = operations
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Observe the folder before the first reconciliation. A directory
            // event then closes the scan window if a file is added or removed
            // while the initial snapshot is being built.
            await prepareObservation()
            await refresh()
        }
    }

    deinit {
        refreshTask?.cancel()
        directoryWatcher?.cancel()
        for watcher in snippetWatchers.values { watcher.cancel() }
    }

    var enabledCount: Int { snippets.lazy.filter(\.isEnabled).count }
    var selectedAppearanceProfile: DocumentAppearanceProfile? {
        appearanceProfiles.first { $0.id == selectedAppearanceProfileID }
    }

    func refresh() async {
        do {
            apply(try await operations.refreshStyleSnippets())
            await restartSnippetWatchers()
        } catch {
            storeError = error.localizedDescription
        }
    }

    func reloadSnippets() {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    func importSnippet(from sourceURL: URL) async throws {
        apply(try await operations.importStyleSnippet(from: sourceURL))
    }

    func createAppearance(named name: String = "Untitled Appearance") {
        perform { try await self.operations.createAppearanceProfile(named: name) }
    }

    func selectAppearance(_ id: UUID) {
        perform { try await self.operations.selectAppearanceProfile(id) }
    }

    func updateAppearance(_ profile: DocumentAppearanceProfile) {
        perform { try await self.operations.updateAppearanceProfile(profile) }
    }

    func renameAppearance(_ id: UUID, to name: String) {
        perform { try await self.operations.renameAppearanceProfile(id, to: name) }
    }

    func duplicateAppearance(_ id: UUID) {
        perform { try await self.operations.duplicateAppearanceProfile(id) }
    }

    func removeAppearance(_ id: UUID) {
        perform { try await self.operations.removeAppearanceProfile(id) }
    }

    func revealAppearanceConfiguration() {
        Task {
            do {
                let url = try await operations.appearanceConfigurationURL()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { storeError = error.localizedDescription }
        }
    }

    func reloadAppearanceConfiguration() {
        Task {
            do {
                apply(try await operations.reloadAppearanceConfiguration())
                appearanceReloadRevision += 1
            } catch { storeError = error.localizedDescription }
        }
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

    private func prepareObservation() async {
        guard directoryWatcher == nil else { return }
        do {
            let initial = try await operations.styleSnapshot()
            let folder = try await operations.managedStylesLocation()
            guard let watcher = makeWatcher(for: folder) else { return }
            directoryWatcher = watcher
            await installSnippetWatchers(for: initial.snippets)
        } catch {
            // The normal refresh reports the authoritative failure. A watcher
            // is an enhancement and must never make an otherwise readable
            // appearance unavailable.
        }
    }

    private func restartSnippetWatchers() async {
        for watcher in snippetWatchers.values { watcher.cancel() }
        snippetWatchers.removeAll()
        await installSnippetWatchers(for: snippets)
    }

    private func installSnippetWatchers(for records: [CSSSnippetRecord]) async {
        for record in records {
            guard snippetWatchers[record.managedFileName] == nil,
                  let url = try? await operations.managedStyleSnippetURL(record.id),
                  FileManager.default.fileExists(atPath: url.path),
                  let watcher = makeWatcher(for: url) else { continue }
            snippetWatchers[record.managedFileName] = watcher
        }
    }

    private func makeWatcher(for url: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        watcher.setCancelHandler {
            close(descriptor)
        }
        watcher.resume()
        return watcher
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self else { return }
            await self.refresh()
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
        appearanceProfiles = snapshot.appearanceProfiles
        selectedAppearanceProfileID = snapshot.selectedAppearanceProfileID
        appearanceCSS = DocumentAppearanceStyles.css(
            for: snapshot.appearanceProfiles.first { $0.id == snapshot.selectedAppearanceProfileID }
        )
        snippets = snapshot.snippets
        validationErrors = snapshot.validationErrors
        readCSS = snapshot.readCSS
        livePreviewCSS = snapshot.livePreviewCSS
        safeModeReason = snapshot.safeModeReason
        storeError = snapshot.storeError
        canModify = snapshot.canModify
    }
}
