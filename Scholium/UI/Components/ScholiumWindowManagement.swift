import ScholiumContracts
import ScholiumResearchRecordsFeature
import AppKit
import notify
import SwiftUI

enum ScholiumWindowLifecycleError: LocalizedError, Equatable, Sendable {
    case failed(String)
    case unregisteredBeforeReady
    case cancelled
    case timedOut(ScholiumLifecyclePhase)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            message
        case .unregisteredBeforeReady:
            "The destination window closed before its native content became ready."
        case .cancelled:
            "Waiting for the destination window was cancelled."
        case .timedOut(let phase):
            "Scholium timed out while waiting for \(phase.description)."
        }
    }
}

enum ScholiumLifecyclePhase: String, Equatable, Sendable {
    case bridgeRequest
    case routeReadiness
    case contentFlush
    case presentationSnapshot
    case applicationTermination

    var description: String {
        switch self {
        case .bridgeRequest: "the editor bridge"
        case .routeReadiness: "the destination window"
        case .contentFlush: "document content to save"
        case .presentationSnapshot: "window state to save"
        case .applicationTermination: "all windows to finish saving"
        }
    }
}

struct ScholiumLifecyclePolicy: Sendable {
    var bridgeRequest: Duration = .seconds(8)
    var routeReadiness: Duration = .seconds(8)
    var contentFlush: Duration = .seconds(10)
    var presentationSnapshot: Duration = .seconds(2)
    var applicationTermination: Duration = .seconds(12)
    var maximumConcurrentWindowFlushes = 4
}

struct LifecycleAttemptID: Hashable, Sendable {
    let rawValue: UInt64
}

typealias ScholiumLifecycleSleeper = @MainActor @Sendable (Duration) async throws -> Void

@MainActor
private final class ScholiumLifecycleDeadlineRace {
    typealias Outcome = Result<Void, any Error>

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var wasCancelled = false

    func start(
        continuation: CheckedContinuation<Outcome, Never>,
        phase: ScholiumLifecyclePhase,
        timeout: Duration,
        sleep: @escaping ScholiumLifecycleSleeper,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        self.continuation = continuation
        if wasCancelled {
            finish(.failure(CancellationError()))
            return
        }
        operationTask = Task { [self] in
            do {
                try await operation()
                finish(.success(()))
            } catch {
                finish(.failure(error))
            }
        }
        timeoutTask = Task { [self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            finish(.failure(ScholiumWindowLifecycleError.timedOut(phase)))
        }
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        let operationTask = operationTask
        let timeoutTask = timeoutTask
        self.continuation = nil
        self.operationTask = nil
        self.timeoutTask = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(returning: outcome)
    }

    func cancel() {
        wasCancelled = true
        finish(.failure(CancellationError()))
    }
}

@MainActor
func withScholiumLifecycleDeadline(
    phase: ScholiumLifecyclePhase,
    timeout: Duration,
    sleep: @escaping ScholiumLifecycleSleeper = { duration in
        try await Task.sleep(for: duration)
    },
    operation: @escaping @MainActor () async throws -> Void
) async throws {
    let race = ScholiumLifecycleDeadlineRace()
    let outcome = await withTaskCancellationHandler {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<Void, any Error>, Never>) in
            race.start(
                continuation: continuation,
                phase: phase,
                timeout: timeout,
                sleep: sleep,
                operation: operation
            )
        }
    } onCancel: {
        Task { @MainActor in race.cancel() }
    }
    try outcome.get()
}

/// Application-owned coordination for exact scene identities. The registry
/// never searches AppKit's global window list and never owns a window or split
/// controller; each scene explicitly registers and unregisters its capability.
@MainActor
final class ScholiumWindowLifecycleRegistry {
    typealias Flusher = @MainActor () async throws -> Void

    private enum Readiness {
        case pending
        case ready
        case failed(ScholiumWindowLifecycleError)
    }

    private final class Entry {
        var isRegistered = false
        var readiness: Readiness = .pending
        var flusher: Flusher?
        var waiters: [
            UUID: CheckedContinuation<Result<Void, ScholiumWindowLifecycleError>, Never>
        ] = [:]
    }

    private var entries: [UUID: Entry] = [:]
    private var activeWorkspaceWindowID: UUID?
    private let policy: ScholiumLifecyclePolicy

    init(policy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy()) {
        self.policy = policy
    }

    var hasRegisteredWindows: Bool {
        entries.values.contains(where: \.isRegistered)
    }

    /// Returns true only when focus moved from a different Scholium Workspace
    /// window. Popover key-window transitions and app deactivation therefore
    /// do not erase the current window's transient Attention work.
    func noteWorkspaceWindowActivated(_ id: UUID) -> Bool {
        let switchedWorkspace = activeWorkspaceWindowID.map { $0 != id } ?? false
        activeWorkspaceWindowID = id
        return switchedWorkspace
    }

    func register(id: UUID, flusher: @escaping Flusher) {
        let entry = entry(for: id)
        if !entry.isRegistered,
           case .failed(.unregisteredBeforeReady) = entry.readiness {
            entry.readiness = .pending
        }
        entry.isRegistered = true
        entry.flusher = flusher
    }

    func markReady(id: UUID) {
        let entry = entry(for: id)
        guard case .pending = entry.readiness else { return }
        entry.readiness = .ready
        resumeWaiters(in: entry, with: .success(()))
    }

    func markFailed(id: UUID, error: any Error) {
        let entry = entry(for: id)
        guard case .pending = entry.readiness else { return }
        let lifecycleError = ScholiumWindowLifecycleError.failed(error.localizedDescription)
        entry.readiness = .failed(lifecycleError)
        resumeWaiters(in: entry, with: .failure(lifecycleError))
    }

    func waitUntilReady(id: UUID) async throws {
        try await withScholiumLifecycleDeadline(
            phase: .routeReadiness,
            timeout: policy.routeReadiness
        ) { [weak self] in
            guard let self else { throw ScholiumWindowLifecycleError.cancelled }
            try await self.waitUntilReadyWithoutDeadline(id: id)
        }
    }

    private func waitUntilReadyWithoutDeadline(id: UUID) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<
                    Result<Void, ScholiumWindowLifecycleError>,
                    Never
                >) in
                let entry = entry(for: id)
                if Task.isCancelled {
                    continuation.resume(returning: .failure(.cancelled))
                    return
                }
                switch entry.readiness {
                case .pending:
                    entry.waiters[waiterID] = continuation
                case .ready:
                    continuation.resume(returning: .success(()))
                case .failed(let error):
                    continuation.resume(returning: .failure(error))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID, for: id)
            }
        }
        switch result {
        case .success:
            return
        case .failure(.cancelled):
            throw CancellationError()
        case .failure(let error):
            throw error
        }
    }

    func unregister(id: UUID) {
        guard let entry = entries[id] else { return }
        entry.isRegistered = false
        entry.flusher = nil
        switch entry.readiness {
        case .failed:
            return
        case .pending, .ready:
            let error = ScholiumWindowLifecycleError.unregisteredBeforeReady
            entry.readiness = .failed(error)
            resumeWaiters(in: entry, with: .failure(error))
        }
    }

    func flushAll() async throws {
        let flushers = entries.values.compactMap { entry in
            entry.isRegistered ? entry.flusher : nil
        }
        try await withScholiumLifecycleDeadline(
            phase: .applicationTermination,
            timeout: policy.applicationTermination
        ) { [policy] in
            let concurrency = max(1, policy.maximumConcurrentWindowFlushes)
            var firstError: (any Error)?
            for start in stride(from: 0, to: flushers.count, by: concurrency) {
                let end = min(start + concurrency, flushers.count)
                let tasks = flushers[start..<end].map { flusher in
                    Task { @MainActor in
                        try await withScholiumLifecycleDeadline(
                            phase: .contentFlush,
                            timeout: policy.contentFlush,
                            operation: flusher
                        )
                    }
                }
                for task in tasks {
                    do {
                        try await task.value
                    } catch {
                        if firstError == nil { firstError = error }
                    }
                }
            }
            if let firstError { throw firstError }
        }
    }

    private func entry(for id: UUID) -> Entry {
        if let entry = entries[id] { return entry }
        let entry = Entry()
        entries[id] = entry
        return entry
    }

    private func cancelWaiter(_ waiterID: UUID, for id: UUID) {
        guard let entry = entries[id],
              let continuation = entry.waiters.removeValue(forKey: waiterID)
        else { return }
        continuation.resume(returning: .failure(.cancelled))
        if !entry.isRegistered, entry.waiters.isEmpty,
           case .pending = entry.readiness {
            entries.removeValue(forKey: id)
        }
    }

    private func resumeWaiters(
        in entry: Entry,
        with result: Result<Void, ScholiumWindowLifecycleError>
    ) {
        let waiters = entry.waiters.values
        entry.waiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success:
                waiter.resume(returning: .success(()))
            case .failure(let error):
                waiter.resume(returning: .failure(error))
            }
        }
    }
}

struct WorkspaceWindowActions {
    let setLibraryVisible: @MainActor (Bool) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let showNoteResearchRecords: @MainActor () -> Void
    let showTriptychResearchRecords: @MainActor () -> Void
    let showAttention: @MainActor (
        AttentionPopoverAnchor,
        VaultQualifiedNoteID?
    ) -> Void
    let showPreferredAttention: @MainActor () -> Void
    let canShowAttention: @MainActor () -> Bool
}

@MainActor
protocol ScholiumWorkspaceSplitControlling: AnyObject {
    var nativeSplitViewController: NSSplitViewController { get }
    var libraryIsVisible: Bool { get }
    var researchInspectorIsVisible: Bool { get }
    func setLibraryVisible(_ visible: Bool, animated: Bool)
    func setResearchInspectorVisible(_ visible: Bool, animated: Bool)
}

/// The sole AppKit boundary for one workspace route. SwiftUI owns scene
/// creation; this coordinator owns that scene's exact NSWindow delegate,
/// toolbar, native split attachment, visibility intents, and close flushing.
@MainActor
final class WorkspaceWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    let windowID: UUID

    private let appState: WindowModel
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    private let researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator?
    private let researchResultNotificationCoordinator:
        ResearchResultNotificationCoordinator?
    private weak var window: NSWindow?
    private weak var splitController: (any ScholiumWorkspaceSplitControlling)?
    // `NSWindow.delegate` is not an ownership boundary. Keep SwiftUI's
    // delegate alive while forwarding optional callbacks, then restore it.
    nonisolated(unsafe) private var previousDelegate: (any NSWindowDelegate)?
    private var toolbarController: ScholiumWorkspaceToolbarController?
    private let loadingToolbar: NSToolbar
    private var reduceMotion = false
    private var closeIsAuthorized = false
    private var flushInFlight = false
    private var closeAttemptGeneration: UInt64 = 0
    private var terminatesApplicationAfterClose = false
    private var readinessWasMarked = false
    private var isRegistered = false
    private var pendingLibraryVisibility: Bool?
    private var pendingInspectorVisibility: Bool?
    private var noteResearchRecordsPresenter: @MainActor () -> Void = {}
    private var triptychResearchRecordsPresenter: @MainActor () -> Void = {}
    private var researchRecordsWindowPresenter: @MainActor () -> Void = {}
    private var researchResultReviewer:
        @MainActor (ResearchResultReviewDestination) -> Void = { _ in }
    private var researchRecordsWorkspaceToken: UUID?
    private var researchRecordsTriptychID: UUID?
    private var researchNotificationWindowToken: UUID?
    private var attentionPresenter:
        @MainActor (
            AttentionPopoverAnchor,
            WorkspaceVaultSlot?,
            VaultQualifiedNoteID?
        ) -> Void = { _, _, _ in }
    private weak var agentRequestPriorResponder: NSResponder?
    private var agentRequestWindowIsRegistered = false
    #if DEBUG
    private var qaFocusNotificationToken: Int32?
    private var qaWriteSetExtensionNotificationToken: Int32?
    #endif

    init(
        windowID: UUID,
        appState: WindowModel,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry,
        researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator? = nil,
        researchResultNotificationCoordinator:
            ResearchResultNotificationCoordinator? = nil
    ) {
        self.windowID = windowID
        self.appState = appState
        self.lifecycleRegistry = lifecycleRegistry
        self.researchRecordsWindowCoordinator = researchRecordsWindowCoordinator
        self.researchResultNotificationCoordinator =
            researchResultNotificationCoordinator
        let loadingToolbar = NSToolbar(
            identifier: NSToolbar.Identifier("scholium.workspaceToolbar.loading")
        )
        loadingToolbar.allowsUserCustomization = false
        loadingToolbar.autosavesConfiguration = false
        loadingToolbar.displayMode = .iconOnly
        loadingToolbar.itemIdentifiers = [.flexibleSpace]
        self.loadingToolbar = loadingToolbar
        super.init()
        appState.bindResearchRecordSearchPresentation { [weak self] result in
            self?.presentResearchRecordSearchResult(result)
        }
        registerLifecycle()
        registerQAFocusRequest()
        registerQAWriteSetExtensionRequest()
    }

    deinit {
        #if DEBUG
        if let qaFocusNotificationToken {
            notify_cancel(qaFocusNotificationToken)
        }
        if let qaWriteSetExtensionNotificationToken {
            notify_cancel(qaWriteSetExtensionNotificationToken)
        }
        #endif
    }

    var actions: WorkspaceWindowActions {
        WorkspaceWindowActions(
            setLibraryVisible: { [weak self] visible in
                self?.setLibraryVisible(visible)
            },
            setResearchInspectorVisible: { [weak self] visible in
                self?.setResearchInspectorVisible(visible)
            },
            showNoteResearchRecords: { [weak self] in
                self?.noteResearchRecordsPresenter()
            },
            showTriptychResearchRecords: { [weak self] in
                self?.triptychResearchRecordsPresenter()
            },
            showAttention: { [weak self] anchor, noteScope in
                self?.attentionPresenter(anchor, nil, noteScope)
            },
            showPreferredAttention: { [weak self] in
                self?.showPreferredAttention()
            },
            canShowAttention: { [weak self] in
                self?.preferredAttentionRoute() != nil
            }
        )
    }

    func update(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    func activate(
        showNoteResearchRecords: @escaping @MainActor () -> Void,
        showTriptychResearchRecords: @escaping @MainActor () -> Void,
        showResearchRecordsWindow: @escaping @MainActor () -> Void,
        reviewResearchResult: @escaping @MainActor (
            ResearchResultReviewDestination
        ) -> Void,
        showAttention: @escaping @MainActor (
            AttentionPopoverAnchor,
            WorkspaceVaultSlot?,
            VaultQualifiedNoteID?
        ) -> Void
    ) {
        registerLifecycle()
        noteResearchRecordsPresenter = showNoteResearchRecords
        triptychResearchRecordsPresenter = showTriptychResearchRecords
        researchRecordsWindowPresenter = showResearchRecordsWindow
        researchResultReviewer = reviewResearchResult
        if let triptychID = researchRecordsTriptychID {
            researchResultNotificationCoordinator?.registerReviewRouter(
                triptychID: triptychID,
                openReview: reviewResearchResult
            )
        }
        attentionPresenter = showAttention
    }

    func updateResearchRecordsRouting(triptychID: UUID?) {
        if researchRecordsTriptychID == triptychID,
           (researchRecordsWorkspaceToken != nil
               || researchRecordsWindowCoordinator == nil),
           (researchNotificationWindowToken != nil
               || researchResultNotificationCoordinator == nil)
               || triptychID == nil {
            return
        }
        unregisterResearchRecordsWorkspace()
        unregisterResearchNotificationWindow()
        guard let triptychID else { return }
        researchRecordsTriptychID = triptychID
        researchResultNotificationCoordinator?.registerReviewRouter(
            triptychID: triptychID,
            openReview: researchResultReviewer
        )
        if let researchRecordsWindowCoordinator {
            researchRecordsWorkspaceToken =
                researchRecordsWindowCoordinator.registerWorkspace(
                    triptychID: triptychID,
                    windowID: windowID
                ) { [weak self] noteID, note, sourceLine in
                    guard let self else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    self.window?.makeKeyAndOrderFront(nil)
                    self.appState.requestOpenNote(
                        note,
                        stableNoteID: noteID,
                        sourceLine: sourceLine
                    )
                }
        }
        registerResearchNotificationWindow(triptychID: triptychID)
    }

    func recordSuccessfulResearchHandoff(runID: UUID) {
        guard let triptychID = researchRecordsTriptychID else { return }
        researchResultNotificationCoordinator?.recordSuccessfulHandoff(
            runID: runID,
            triptychID: triptychID,
            sourceWindowID: windowID
        )
    }

    func reviewResearchResult(_ destination: ResearchResultReviewDestination) {
        guard destination.triptychID == researchRecordsTriptychID else { return }
        researchResultReviewer(destination)
        appState.shellState.dismissResearchResultNotice(matching: destination)
    }

    func requestResearchNotificationAuthorization() {
        researchResultNotificationCoordinator?.requestNotificationAuthorization(
            windowID: windowID
        )
    }

    func openResearchNotificationSettings() {
        researchResultNotificationCoordinator?.openNotificationSettings()
    }

    private func presentResearchRecordSearchResult(
        _ result: RecordSearchResult
    ) {
        guard let triptychID = researchRecordsTriptychID,
              let researchRecordsWindowCoordinator else { return }
        researchRecordsWindowCoordinator.submit(ResearchRecordsWindowRequest(
            triptychID: triptychID,
            initialView: .records,
            recordID: result.recordID,
            expectedRecordFingerprint: result.fingerprint,
            statementID: result.statementID
        ))
        researchRecordsWindowPresenter()
    }

    func attach(to window: NSWindow) {
        if self.window === window, window.delegate === self {
            installLoadingToolbarIfNeeded()
            installToolbarIfPossible()
            markReadyIfPossible()
            return
        }
        removeToolbar()
        detachWindow()
        self.window = window
        window.identifier = NSUserInterfaceItemIdentifier(
            "scholium-main-\(windowID.uuidString)"
        )
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        applyWindowChrome(to: window)
        installLoadingToolbarIfNeeded()
        previousDelegate = window.delegate
        window.delegate = self
        registerResearchAgentPermissionWindow()
        installToolbarIfPossible()
        markReadyIfPossible()
    }

    func attach(splitController: any ScholiumWorkspaceSplitControlling) {
        self.splitController = splitController
        if let visible = pendingLibraryVisibility {
            pendingLibraryVisibility = nil
            splitController.setLibraryVisible(visible, animated: !reduceMotion)
        }
        if let visible = pendingInspectorVisibility {
            pendingInspectorVisibility = nil
            splitController.setResearchInspectorVisible(visible, animated: !reduceMotion)
        }
        recordNativeVisibility(from: splitController)
        installToolbarIfPossible()
        markReadyIfPossible()
    }

    func detach(splitController: any ScholiumWorkspaceSplitControlling) {
        guard self.splitController === splitController else { return }
        self.splitController = nil
        replaceConfiguredToolbarWithLoadingToolbar()
    }

    func failReadiness(_ error: any Error) {
        guard !readinessWasMarked else { return }
        readinessWasMarked = true
        lifecycleRegistry.markFailed(id: windowID, error: error)
    }

    func detach() {
        closeAttemptGeneration &+= 1
        flushInFlight = false
        closeIsAuthorized = false
        terminatesApplicationAfterClose = false
        appState.finalizeWindowClose()
        removeToolbar()
        splitController = nil
        unregisterResearchAgentPermissionWindow()
        unregisterResearchRecordsWorkspace()
        unregisterResearchNotificationWindow()
        detachWindow()
        noteResearchRecordsPresenter = {}
        triptychResearchRecordsPresenter = {}
        researchRecordsWindowPresenter = {}
        researchResultReviewer = { _ in }
        attentionPresenter = { _, _, _ in }
        if isRegistered {
            lifecycleRegistry.unregister(id: windowID)
            isRegistered = false
        }
    }

    private func registerLifecycle() {
        guard !isRegistered else { return }
        readinessWasMarked = false
        lifecycleRegistry.register(id: windowID) { [weak appState] in
            guard let appState else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            _ = try await appState.prepareForWindowClose()
        }
        isRegistered = true
    }

    private func registerResearchAgentPermissionWindow() {
        guard !agentRequestWindowIsRegistered else { return }
        agentRequestWindowIsRegistered = true
        appState.researchAgentPermissionWindowController.registerWindowEndpoint(
            activeTriptychID: { [weak appState] in
                appState?.activeTriptychServicesID
            },
            isKeyWindow: { [weak self] in
                self?.window?.isKeyWindow == true
            },
            canPresent: { [weak self, weak appState] in
                guard let self, let appState, let window = self.window else {
                    return false
                }
                return window.isVisible
                    && !window.isMiniaturized
                    && window.attachedSheet == nil
                    && appState.presentationRouter.sheet == nil
            },
            willPresent: { [weak self] in
                self?.agentRequestPriorResponder = self?.window?.firstResponder
            },
            focus: { [weak self] in
                self?.focusResearchAgentPermissionSheet()
            }
        )
    }

    private func unregisterResearchAgentPermissionWindow() {
        guard agentRequestWindowIsRegistered else { return }
        appState.researchAgentPermissionWindowController.unregisterWindow()
        agentRequestWindowIsRegistered = false
        agentRequestPriorResponder = nil
    }

    private func unregisterResearchRecordsWorkspace() {
        guard let researchRecordsTriptychID,
              let researchRecordsWorkspaceToken,
              let researchRecordsWindowCoordinator else {
            self.researchRecordsTriptychID = nil
            self.researchRecordsWorkspaceToken = nil
            return
        }
        researchRecordsWindowCoordinator.unregisterWorkspace(
            triptychID: researchRecordsTriptychID,
            token: researchRecordsWorkspaceToken
        )
        self.researchRecordsTriptychID = nil
        self.researchRecordsWorkspaceToken = nil
    }

    private func registerResearchNotificationWindow(triptychID: UUID) {
        guard researchNotificationWindowToken == nil,
              let researchResultNotificationCoordinator else { return }
        researchNotificationWindowToken =
            researchResultNotificationCoordinator.registerWindow(
                windowID: windowID,
                triptychID: triptychID,
                presentResult: { [weak appState] destination in
                    appState?.shellState.presentResearchResultNotice(destination)
                },
                dismissResult: { [weak appState] destination in
                    appState?.shellState.dismissResearchResultNotice(
                        matching: destination
                    )
                },
                presentPermission: { [weak appState] notice in
                    appState?.shellState
                        .presentResearchNotificationPermissionNotice(notice)
                },
                dismissPermission: { [weak appState] in
                    appState?.shellState
                        .dismissResearchNotificationPermissionNotice()
                },
                openReview: { [weak self] destination in
                    self?.reviewResearchResult(destination)
                }
            )
    }

    private func unregisterResearchNotificationWindow() {
        // These notices belong to this exact window-to-Triptych binding. Do
        // not let an old result or permission prompt survive when the same
        // native window is reassigned or detached.
        appState.shellState.dismissResearchResultNotice()
        appState.shellState.dismissResearchNotificationPermissionNotice()
        guard let token = researchNotificationWindowToken else { return }
        researchResultNotificationCoordinator?.unregisterWindow(
            windowID: windowID,
            token: token
        )
        researchNotificationWindowToken = nil
    }

    private func focusResearchAgentPermissionSheet() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.attachedSheet?.makeKeyAndOrderFront(nil)
    }

    func restoreResearchAgentPermissionFocus() {
        defer { agentRequestPriorResponder = nil }
        guard let window, let responder = agentRequestPriorResponder else { return }
        window.makeFirstResponder(responder)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if lifecycleRegistry.noteWorkspaceWindowActivated(windowID) {
            appState.attentionPopoverSession.resetForWorkspaceSwitch()
        }
        appState.researchAgentPermissionWindowController.noteWindowActivated()
        if let researchRecordsTriptychID, let researchRecordsWorkspaceToken {
            researchRecordsWindowCoordinator?.workspaceDidActivate(
                triptychID: researchRecordsTriptychID,
                token: researchRecordsWorkspaceToken
            )
        }
        if let researchNotificationWindowToken {
            researchResultNotificationCoordinator?.windowDidActivate(
                windowID: windowID,
                token: researchNotificationWindowToken
            )
        }
        previousDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window,
           let notificationWindow = notification.object as? NSWindow,
           notificationWindow === window {
            reapplyWindowChromeAfterFullScreenTransition()
        }
        previousDelegate?.windowDidEnterFullScreen?(notification)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if let window,
           let notificationWindow = notification.object as? NSWindow,
           notificationWindow === window {
            reapplyWindowChromeAfterFullScreenTransition()
        }
        previousDelegate?.windowDidExitFullScreen?(notification)
    }

    func windowWillClose(_ notification: Notification) {
        // Release App-wide claims before SwiftUI tears down the per-window
        // model so an unresolved request can move to another exact window.
        appState.finalizeWindowClose()
        unregisterResearchAgentPermissionWindow()
        unregisterResearchRecordsWorkspace()
        unregisterResearchNotificationWindow()
        if isRegistered {
            lifecycleRegistry.unregister(id: windowID)
            isRegistered = false
        }
        previousDelegate?.windowWillClose?(notification)
        if terminatesApplicationAfterClose {
            terminatesApplicationAfterClose = false
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// The Restore Access route has no usable document session to flush. Close
    /// that exact unavailable window first, then let application termination
    /// flush every remaining registered workspace through the normal owner.
    func closeUnavailableWorkspaceAndTerminateApplication() {
        guard let window else {
            NSApplication.shared.terminate(nil)
            return
        }
        closeAttemptGeneration &+= 1
        flushInFlight = false
        terminatesApplicationAfterClose = true
        window.close()
    }

    private struct PreferredAttentionRoute {
        let anchor: AttentionPopoverAnchor
        let workspaceSlot: WorkspaceVaultSlot?
        let noteScope: VaultQualifiedNoteID?
    }

    private func showPreferredAttention() {
        guard let route = preferredAttentionRoute() else { return }
        attentionPresenter(route.anchor, route.workspaceSlot, route.noteScope)
    }

    private func preferredAttentionRoute() -> PreferredAttentionRoute? {
        let ledgerData = UserDefaults.standard.data(
            forKey: AttentionPreferences.dismissalLedgerKey
        ) ?? Data()
        if appState.sidebarVisible {
            return PreferredAttentionRoute(
                anchor: .sidebar,
                workspaceSlot: nil,
                noteScope: nil
            )
        }

        guard appState.researchInspectorVisible,
              let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID
        else { return nil }
        let noteScope = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: note.relativePath
        )
        let ledger = AttentionPreferences.decodeLedger(ledgerData)
        let noteItems = (appState.workspaceCatalog?.attention ?? []).filter {
            $0.note.vaultID == noteScope.vaultID
                && $0.note.relativePath == noteScope.relativePath
        }
        guard !ledger.visible(noteItems).isEmpty else { return nil }
        return PreferredAttentionRoute(
            anchor: .inspector,
            workspaceSlot: nil,
            noteScope: noteScope
        )
    }

    private func registerQAFocusRequest() {
        #if DEBUG
        guard Bundle.main.bundleIdentifier == "com.scholium.qa" else { return }
        var token: Int32 = 0
        let name = "com.scholium.qa.focus-workspace.\(windowID.uuidString)"
        let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let window = self?.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        if status == NOTIFY_STATUS_OK {
            qaFocusNotificationToken = token
        }
        #endif
    }

    private func registerQAWriteSetExtensionRequest() {
        #if DEBUG
        guard Bundle.main.bundleIdentifier == "com.scholium.qa",
              ProcessInfo.processInfo.arguments.contains(
                "--scholium-write-set-extension-fixture"
              ) else { return }
        var token: Int32 = 0
        let name = "com.scholium.qa.present-write-set-extension.\(windowID.uuidString)"
        let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let triptychID = appState.activeTriptychServicesID,
                      let record = try? Self.qaWriteSetExtensionRecord(
                        triptychID: triptychID
                      ) else { return }
                appState.researchAgentPermissionWindowController.present(
                    .writeSetExtension(record),
                    activeTriptychID: triptychID
                )
            }
        }
        if status == NOTIFY_STATUS_OK {
            qaWriteSetExtensionNotificationToken = token
        }
        #endif
    }

    #if DEBUG
    private static func qaWriteSetExtensionRecord(
        triptychID: UUID
    ) throws -> ResearchWriteSetExtensionRecord {
        let runID = UUID(
            uuidString: "11000000-0000-0000-0000-000000000001"
        )!
        let noteID = UUID(
            uuidString: "22000000-0000-0000-0000-000000000001"
        )!
        let selector = try ResearchWriteSetTargetSelector(
            role: .topic,
            relativePath: "QA Autosave B.md",
            operations: [.modifyMarkdown]
        )
        let intent = try ResearchWriteSetExtensionIntent(
            targets: [selector],
            academicReason: "The current argument requires one bounded update to the related Topic."
        )
        let candidate = try ResearchWriteSetCandidate(
            handle: ResearchWriteTargetHandle(runID: runID, noteID: noteID),
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(
                    uuidString: "33000000-0000-0000-0000-000000000001"
                )!,
                relativePath: selector.relativePath
            ),
            role: selector.role,
            title: "QA Autosave B",
            operations: selector.operations,
            expectedRevision: DocumentFingerprint(content: "# QA Autosave B\n")
        )
        let receivedAt = Date()
        return try ResearchWriteSetExtensionRecord(
            id: UUID(),
            runID: runID,
            triptychID: triptychID,
            intent: intent,
            intentDigest: DocumentFingerprint(content: "qa-write-set-extension"),
            candidates: [candidate],
            policy: .askEveryTime,
            policyRevision: DocumentFingerprint(content: "qa-policy"),
            state: .pending,
            receivedAt: receivedAt,
            expiresAt: receivedAt.addingTimeInterval(5 * 60)
        )
    }
    #endif

    private func setLibraryVisible(_ visible: Bool) {
        guard let splitController else {
            pendingLibraryVisibility = visible
            return
        }
        splitController.setLibraryVisible(visible, animated: !reduceMotion)
    }

    private func setResearchInspectorVisible(_ visible: Bool) {
        guard let splitController else {
            pendingInspectorVisibility = visible
            return
        }
        splitController.setResearchInspectorVisible(visible, animated: !reduceMotion)
    }

    private func recordNativeVisibility(
        from splitController: any ScholiumWorkspaceSplitControlling
    ) {
        appState.recordLibraryVisibility(splitController.libraryIsVisible)
        appState.recordResearchInspectorVisibility(
            splitController.researchInspectorIsVisible
        )
    }

    private func markReadyIfPossible() {
        guard !readinessWasMarked,
              let window,
              let splitController,
              splitController.nativeSplitViewController.view.window === window,
              toolbarController != nil
        else { return }
        readinessWasMarked = true
        lifecycleRegistry.markReady(id: windowID)
    }

    private func applyWindowChrome(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.backgroundColor = ScholiumColorRole.documentBackground.nsColor
        applyNativeTitlebarBackground(to: window)
    }

    private func applyNativeTitlebarBackground(to window: NSWindow) {
        // Full-screen mode promotes AppKit's toolbar into a separate native
        // titlebar container. Keep that container on the same opaque semantic
        // plane as the workspace so the system toolbar cannot expose its white
        // default material during the transition.
        guard let titlebarContainer = window.standardWindowButton(.closeButton)?
            .superview?.superview else { return }
        titlebarContainer.wantsLayer = true
        titlebarContainer.layer?.backgroundColor =
            ScholiumColorRole.documentBackground.nsColor.cgColor
    }

    private func installToolbarIfPossible() {
        guard let window,
              let splitController,
              splitController.nativeSplitViewController.view.window === window
        else { return }
        if let toolbarController,
           toolbarController.controls(splitController.nativeSplitViewController) {
            toolbarController.install(in: window)
            applyWindowChrome(to: window)
            return
        }
        let controller = ScholiumWorkspaceToolbarController(
            appState: appState,
            windowActions: actions,
            splitViewController: splitController.nativeSplitViewController
        )
        toolbarController = controller
        controller.install(in: window)
        applyWindowChrome(to: window)
    }

    private func reapplyWindowChromeAfterFullScreenTransition() {
        guard let window else { return }
        applyWindowChrome(to: window)
        installLoadingToolbarIfNeeded()
        installToolbarIfPossible()
    }

    /// Keep the native toolbar band present from the window's first frame.
    /// The split-dependent tracking items replace this inert toolbar in place;
    /// document loading therefore cannot move the traffic lights or safe area.
    private func installLoadingToolbarIfNeeded() {
        guard toolbarController == nil, let window else { return }
        if window.toolbar !== loadingToolbar {
            window.toolbar = loadingToolbar
        }
        window.toolbarStyle = .unified
    }

    private func replaceConfiguredToolbarWithLoadingToolbar() {
        toolbarController = nil
        installLoadingToolbarIfNeeded()
    }

    private func removeToolbar() {
        guard let window else {
            toolbarController = nil
            return
        }
        let isConfiguredToolbar = window.toolbar?.identifier
            == ScholiumWorkspaceToolbarController.toolbarIdentifier
        if window.toolbar === loadingToolbar || isConfiguredToolbar {
            window.toolbar = nil
        }
        toolbarController = nil
    }

    private func detachWindow() {
        if let window, window.delegate === self {
            window.delegate = previousDelegate
        }
        window = nil
        previousDelegate = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeIsAuthorized {
            closeIsAuthorized = false
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }
        guard !flushInFlight else { return false }
        flushInFlight = true
        closeAttemptGeneration &+= 1
        let attempt = closeAttemptGeneration
        Task { @MainActor [weak self, weak sender] in
            guard let self, let sender else { return }
            do {
                let outcome = try await appState.prepareForWindowClose()
                guard attempt == closeAttemptGeneration,
                      self.window === sender else { return }
                closeIsAuthorized = true
                flushInFlight = false
                if let warning = outcome.presentationWarning {
                    appState.showToast(
                        "The document was saved, but window state could not be saved. \(warning)",
                        kind: .warning
                    )
                }
                sender.performClose(nil)
            } catch {
                guard attempt == closeAttemptGeneration,
                      self.window === sender else { return }
                flushInFlight = false
                appState.lastSaveError = error.localizedDescription
                appState.showToast(
                    "Scholium kept this window open because the current note could not be saved. \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }
}

struct WorkspaceWindowAttachment: NSViewRepresentable {
    let coordinator: WorkspaceWindowCoordinator

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        if let window = nsView.window { coordinator.attach(to: window) }
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentView,
        coordinator: Void
    ) {}
}

struct ResearchRecordsWindowAttachment: NSViewRepresentable {
    let triptychID: UUID

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = configure
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        if let window = nsView.window { configure(window) }
    }

    func configure(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(
            "scholium-research-records-\(triptychID.uuidString.lowercased())"
        )
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ScholiumColorRole.documentBackground.nsColor
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
    }
}

final class WindowAttachmentView: NSView {
    var onWindowAttachment: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onWindowAttachment?(window)
    }
}

struct BootstrapWindowAttachment: NSViewRepresentable {
    let windowID: UUID
    let lifecycleRegistry: ScholiumWindowLifecycleRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(windowID: windowID, lifecycleRegistry: lifecycleRegistry)
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        if let window = nsView.window { context.coordinator.attach(to: window) }
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private let windowID: UUID
        private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
        private weak var window: NSWindow?
        private var isRegistered = false

        init(
            windowID: UUID,
            lifecycleRegistry: ScholiumWindowLifecycleRegistry
        ) {
            self.windowID = windowID
            self.lifecycleRegistry = lifecycleRegistry
            lifecycleRegistry.register(id: windowID) {}
            isRegistered = true
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            window.tabbingMode = .disallowed
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = ScholiumColorRole.documentBackground.nsColor
            lifecycleRegistry.markReady(id: windowID)
        }

        func detach() {
            window = nil
            if isRegistered {
                lifecycleRegistry.unregister(id: windowID)
                isRegistered = false
            }
        }
    }
}
