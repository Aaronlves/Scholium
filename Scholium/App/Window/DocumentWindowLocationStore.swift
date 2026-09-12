import AppKit
import Combine
import ScholiumContracts
import SwiftUI

/// App-owned locations; document bytes remain in exactly one transferred session.
@MainActor
final class DocumentWindowLocationStore {
    private final class Entry {
        weak var model: WindowModel?
        init(_ model: WindowModel) { self.model = model }
    }
    private unowned let workspaceStore: WorkspaceStore
    private var windows: [UUID: Entry] = [:]
    private var ownedWindows: [UUID: NSWindowController] = [:]
    private var origins: [UUID: UUID] = [:]
    var openMainWindow: ((TriptychWindowRoute) -> Void)?
    private var moving: [DocumentSessionKey: WindowModel] = [:]

    init(workspaceStore: WorkspaceStore) { self.workspaceStore = workspaceStore }

    func register(_ model: WindowModel) { windows[model.nativeWindowID] = Entry(model) }

    func unregister(_ model: WindowModel) {
        windows[model.nativeWindowID] = nil
        ownedWindows[model.nativeWindowID] = nil
        origins[model.nativeWindowID] = nil
    }

    func revealExisting(_ reference: VaultNoteReference, excluding source: WindowModel) -> Bool {
        guard let id = resolvedKey(for: reference, in: source)?.noteID else { return false }
        return revealExisting(key: DocumentSessionKey(vaultID: reference.vaultID, noteID: id), excluding: source)
    }

    func revealExisting(_ document: WindowSelectedDocument, excluding source: WindowModel) -> Bool {
        guard let key = document.sessionKey else { return false }
        return revealExisting(key: key, excluding: source)
    }

    func existingOwner(of reference: VaultNoteReference, excluding source: WindowModel) -> WindowModel? {
        guard let id = resolvedKey(for: reference, in: source)?.noteID else { return nil }
        return existingOwner(key: DocumentSessionKey(vaultID: reference.vaultID, noteID: id), excluding: source)
    }

    private func resolvedKey(for reference: VaultNoteReference, in source: WindowModel) -> DocumentSessionKey? {
        let id = reference.stableNoteID.flatMap(UUID.init(uuidString:))
            ?? source.workspaceProjectionController.cachedNote(
                vaultID: reference.vaultID, stableNoteID: nil, relativePath: reference.relativePath
            )?.stableIdentity.resolvedID
        return id.map { DocumentSessionKey(vaultID: reference.vaultID, noteID: $0) }
    }

    private func existingOwner(key: DocumentSessionKey, excluding source: WindowModel) -> WindowModel? {
        if let owner = moving[key], owner !== source,
            owner.workspaceAssignment?.id == source.workspaceAssignment?.id { return owner }
        return windows.values.compactMap(\.model).first { model in
            model !== source && !model.windowCloseCoordinator.isFinalized
                && model.workspaceAssignment?.id == source.workspaceAssignment?.id
                && model.documentTabController.tabs.contains { $0.document.sessionKey == key }
        }
    }

    private func revealExisting(key: DocumentSessionKey, excluding source: WindowModel) -> Bool {
        guard let model = existingOwner(key: key, excluding: source) else { return false }
        model.nativeWindowCoordinator?.makeKeyAndOrderFront()
        if let tab = model.documentTabController.tabs.first(where: { $0.document.sessionKey == key }) {
            model.selectDocumentTab(withID: tab.id)
        }
        return true
    }

    /// Library and Chat enter the same single-location policy without briefly
    /// replacing or inserting a document in the main window.
    func openSeparate(_ reference: VaultNoteReference, from source: WindowModel) async throws -> WindowModel {
        guard let key = resolvedKey(for: reference, in: source) else { throw DocumentControllerError.documentUnavailable }
        let owner = existingOwner(of: reference, excluding: source) ?? source
        if let tab = owner.documentTabController.tabs.first(where: { $0.document.sessionKey == key }) {
            if owner.isDetachedDocumentWindow {
                owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
                return owner
            }
            return try await moveTab(tab.id, from: owner)
        }
        guard !source.transferInProgress, moving[key] == nil,
            let triptychID = source.workspaceAssignment?.id,
            let registry = source.nativeWindowCoordinator?.registry
        else { throw DocumentControllerError.documentUnavailable }
        source.transferInProgress = true
        moving[key] = source
        defer { source.transferInProgress = false; moving[key] = nil }
        let destination = try await makeDocumentWindow(triptychID: triptychID, registry: registry)
        do {
            moving[key] = destination.model
            try await destination.model.activateWorkspaceReference(reference, tabActivation: .place(.newTab))
            guard destination.model.documentController.selectedDocument?.sessionKey == key else {
                throw DocumentControllerError.documentUnavailable
            }
            origins[destination.model.nativeWindowID] = source.isDetachedDocumentWindow
                ? origins[source.nativeWindowID] : source.nativeWindowID
            destination.controller.showWindow(nil)
            destination.model.nativeWindowCoordinator?.makeKeyAndOrderFront()
            return destination.model
        } catch {
            destination.controller.window?.close()
            throw error
        }
    }

    @discardableResult
    func moveTab(_ id: UUID, from source: WindowModel, at point: NSPoint? = nil) async throws -> WindowModel {
        guard !source.isDetachedDocumentWindow, !source.transferInProgress,
            let tab = source.documentTabController.tabs.first(where: { $0.id == id }),
            let key = tab.document.sessionKey,
            moving[key] == nil,
            let coordinator = source.nativeWindowCoordinator,
            let triptychID = source.workspaceAssignment?.id
        else { throw DocumentControllerError.documentUnavailable }
        guard !source.documentController.session(for: tab.document.editingTarget).editorSession.isComposing
        else { throw DocumentControllerError.editorUnavailable }
        source.transferInProgress = true
        moving[key] = source
        defer { source.transferInProgress = false; moving[key] = nil }
        await source.waitForDocumentTransitions()
        let destination = try await makeDocumentWindow(
            triptychID: triptychID, registry: coordinator.registry
        )
        do {
            try await transfer(tab, from: source, to: destination.model)
            origins[destination.model.nativeWindowID] = source.nativeWindowID
            if let point, let window = destination.controller.window {
                let titlebarHeight = window.frame.height - window.contentLayoutRect.height
                window.setFrameTopLeftPoint(NSPoint(x: point.x - window.frame.width / 2, y: point.y + titlebarHeight / 2))
            }
            destination.controller.showWindow(nil)
            destination.controller.window?.makeKeyAndOrderFront(nil)
            return destination.model
        } catch {
            destination.controller.window?.close()
            throw error
        }
    }

    func moveBack(from source: WindowModel) async throws {
        guard source.isDetachedDocumentWindow, !source.transferInProgress,
            let tab = source.documentTabController.selectedTab,
            let key = tab.document.sessionKey, moving[key] == nil,
            let triptychID = source.workspaceAssignment?.id,
            let coordinator = source.nativeWindowCoordinator
        else { throw DocumentControllerError.documentUnavailable }
        guard !source.documentController.session(for: tab.document.editingTarget).editorSession.isComposing
        else { throw DocumentControllerError.editorUnavailable }
        source.transferInProgress = true
        moving[key] = source
        defer { source.transferInProgress = false; moving[key] = nil }
        await source.waitForDocumentTransitions()
        let original = origins[source.nativeWindowID].flatMap { windows[$0]?.model }
        let existing = ([original] + windows.values.map(\.model)).compactMap { $0 }.first {
            !$0.isDetachedDocumentWindow && !$0.windowCloseCoordinator.isFinalized
                && $0.workspaceAssignment?.id == triptychID && !$0.transferInProgress
        }
        let destination: WindowModel
        if let existing {
            destination = existing
        } else {
            guard let openMainWindow else { throw DocumentControllerError.documentUnavailable }
            let route = TriptychWindowRoute(triptychID: triptychID)
            openMainWindow(route)
            try await coordinator.registry.waitUntilReady(id: route.windowID)
            guard let ready = windows[route.windowID]?.model else { throw DocumentControllerError.documentUnavailable }
            destination = ready
        }
        do {
            try await transfer(tab, from: source, to: destination)
        } catch {
            if existing == nil, destination.documentTabController.tabs.isEmpty {
                destination.nativeWindowCoordinator?.closeTransferredContainer()
            }
            throw error
        }
        destination.nativeWindowCoordinator?.makeKeyAndOrderFront()
        // The session has left. This is a container close, not a document save.
        coordinator.closeTransferredContainer()
    }

    private func transfer(_ tab: DocumentTabItem, from source: WindowModel, to destination: WindowModel) async throws {
        guard !destination.transferInProgress,
            source.documentTabController.tabs.contains(tab),
            destination.documentController.canReceiveSessionTransfer(tab.document),
            !destination.documentTabController.tabs.contains(where: { $0.document.editingTarget == tab.document.editingTarget })
        else { throw DocumentControllerError.documentUnavailable }
        if let current = destination.documentController.selectedDocument,
            destination.documentController.session(for: current.editingTarget).editorSession.isComposing {
            throw DocumentControllerError.editorUnavailable
        }
        destination.transferInProgress = true
        defer { destination.transferInProgress = false }
        await destination.waitForDocumentTransitions()
        let previousDestination = destination.documentController.selectedDocument
        defer {
            if let previousDestination {
                destination.documentController.resumeAutosave(afterTransferOf: previousDestination)
            }
            source.documentController.resumeAutosave(afterTransferOf: tab.document)
        }
        if let previousDestination {
            try await destination.documentController.prepareSessionTransfer(previousDestination)
        }
        try await source.documentController.prepareSessionTransfer(tab.document)
        guard source.documentTabController.tabs.contains(tab),
            destination.documentController.canReceiveSessionTransfer(tab.document) else {
            throw DocumentControllerError.documentUnavailable
        }
        let originalIndex = source.documentTabController.tabs.firstIndex { $0.id == tab.id } ?? 0
        let wasSelected = source.documentTabController.selectedTabID == tab.id
        let transfer = try source.takeDocumentForTransfer(tabID: tab.id)
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while transfer.session.editorSession.hasAttachedWebView, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard !transfer.session.editorSession.hasAttachedWebView else { throw DocumentControllerError.editorUnavailable }
            destination.finishIncomingTransfer(transfer, tab: tab)
        } catch {
            source.documentController.receiveSessionTransfer(transfer, selecting: wasSelected)
            if !source.documentTabController.tabs.contains(where: { $0.id == tab.id }) {
                source.documentTabController.insertTransferredTab(tab, at: originalIndex, select: wasSelected)
            }
            throw error
        }
    }

    private func makeDocumentWindow(triptychID: UUID, registry: ScholiumWindowLifecycleRegistry) async throws
        -> (model: WindowModel, controller: NSWindowController) {
        let id = UUID()
        let model = WindowModel(workspaceStore: workspaceStore, nativeWindowID: id, requestedTriptychID: triptychID)
        model.isDetachedDocumentWindow = true
        await model.restoreWindowSession(id: id)
        guard model.workspaceAssignment?.id == triptychID, model.vaultConfig != nil else {
            throw DocumentControllerError.documentUnavailable
        }
        let coordinator = WorkspaceWindowCoordinator(windowID: id, appState: model, lifecycleRegistry: registry)
        let root = ScholiumWindowObservedRoot(
            appState: model, windowCoordinator: coordinator,
            route: TriptychWindowRoute(windowID: id, triptychID: triptychID), lifecycleRegistry: registry
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)
        let host = NSHostingController(rootView: root)
        // This window is AppKit-owned. SwiftUI must not install its own
        // toolbar/delegate forwarding wrapper around the native coordinator.
        host.sceneBridgingOptions = []
        host.sizingOptions = []
        window.contentViewController = host
        window.center()
        let controller = NSWindowController(window: window)
        ownedWindows[id] = controller
        coordinator.attach(to: window)
        window.setContentSize(NSSize(width: 760, height: 780))
        return (model, controller)
    }
}
