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
    let showAttention: @MainActor (AttentionPresentationRequest) -> Void
    let showPreferredAttention: @MainActor () -> Void
    let canShowAttention: @MainActor () -> Bool
}

/// The AppKit window is the appearance ancestor for native titlebar and
/// toolbar content. SwiftUI projects the same researcher choice into the
/// document hierarchy; this boundary maps it once for the native window.
@MainActor
enum ScholiumWindowAppearance {
    static func apply(_ choice: WindowColorSchemeChoice, to window: NSWindow) {
        window.appearance = switch choice {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
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
    private var colorScheme = WindowColorSchemeChoice.system
    private var reduceMotion = false
    private var closeIsAuthorized = false
    private var flushInFlight = false
    private var closeAttemptGeneration: UInt64 = 0
    private var terminatesApplicationAfterClose = false
    private var readinessWasMarked = false
    private var isRegistered = false
    private var didFinalizeWindowAttachments = false
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
        @MainActor (AttentionPresentationRequest) -> Void = { _ in }
    #if DEBUG
    private var qaFocusNotificationToken: Int32?
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
    }

    deinit {
        #if DEBUG
        if let qaFocusNotificationToken {
            notify_cancel(qaFocusNotificationToken)
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
            showAttention: { [weak self] request in
                self?.attentionPresenter(request)
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

    func update(colorScheme: WindowColorSchemeChoice) {
        guard self.colorScheme != colorScheme else { return }
        self.colorScheme = colorScheme
        if let window {
            ScholiumWindowAppearance.apply(colorScheme, to: window)
        }
    }

    func activate(
        showNoteResearchRecords: @escaping @MainActor () -> Void,
        showTriptychResearchRecords: @escaping @MainActor () -> Void,
        showResearchRecordsWindow: @escaping @MainActor () -> Void,
        reviewResearchResult: @escaping @MainActor (
            ResearchResultReviewDestination
        ) -> Void,
        showAttention: @escaping @MainActor (AttentionPresentationRequest) -> Void
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
        Task { [weak self] in
            guard let self,
                  let snapshot = await self.appState.refreshAfterResearchHandoff(),
                  snapshot.triptych.id == triptychID,
                  self.researchRecordsTriptychID == triptychID else { return }
            self.researchResultNotificationCoordinator?.receive(
                activities: snapshot.research.activities,
                arrivals: snapshot.research.resultArrivals,
                triptychID: triptychID
            )
        }
    }

    func reviewResearchResult(_ destination: ResearchResultReviewDestination) {
        guard destination.triptychID == researchRecordsTriptychID else { return }
        researchResultReviewer(destination)
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
        guard !didFinalizeWindowAttachments else { return }
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
        window.tabbingMode = .disallowed
        configureWindowFrame(window)
        installLoadingToolbarIfNeeded()
        previousDelegate = window.delegate
        window.delegate = self
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
        removeToolbar()
        splitController = nil
        noteResearchRecordsPresenter = {}
        triptychResearchRecordsPresenter = {}
        researchRecordsWindowPresenter = {}
        researchResultReviewer = { _ in }
        attentionPresenter = { _ in }
    }

    private func finalizeWindowAttachments(
        forwarding notification: Notification
    ) -> Bool {
        guard !didFinalizeWindowAttachments else { return false }
        didFinalizeWindowAttachments = true
        let shouldTerminateApplication = terminatesApplicationAfterClose
        terminatesApplicationAfterClose = false
        let forwardedDelegate = previousDelegate
        detach()
        unregisterResearchRecordsWorkspace()
        unregisterResearchNotificationWindow()
        if isRegistered {
            lifecycleRegistry.unregister(id: windowID)
            isRegistered = false
        }
        // AppKit can still deliver order-off notifications after
        // windowWillClose. Restore SwiftUI's retained delegate before this
        // coordinator becomes unreachable so those callbacks never target a
        // released forwarding object.
        detachWindow(restoringPreviousDelegate: true)
        forwardedDelegate?.windowWillClose?(notification)
        return shouldTerminateApplication
    }

    private func registerLifecycle() {
        guard !isRegistered else { return }
        readinessWasMarked = false
        lifecycleRegistry.register(id: windowID) { [weak appState] in
            guard let appState else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            _ = try await appState.windowCloseCoordinator.prepare()
        }
        isRegistered = true
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
                receiveActivities: { [weak appState] notifications in
                    appState?.shellState.receiveResearchActivityNotifications(
                        notifications
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
        appState.researchResultNotificationDismissal = {
            [weak self] destination in
            guard let self else { return }
            self.researchResultNotificationCoordinator?.dismiss(
                destination,
                from: self.windowID
            )
        }
    }

    private func unregisterResearchNotificationWindow() {
        // These notices belong to this exact window-to-Triptych binding. Do
        // not let an old activity projection or permission prompt survive when the same
        // native window is reassigned or detached.
        appState.shellState.receiveResearchActivityNotifications([])
        appState.shellState.dismissResearchNotificationPermissionNotice()
        appState.researchResultNotificationDismissal = nil
        guard let token = researchNotificationWindowToken else { return }
        researchResultNotificationCoordinator?.unregisterWindow(
            windowID: windowID,
            token: token
        )
        researchNotificationWindowToken = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if lifecycleRegistry.noteWorkspaceWindowActivated(windowID) {
            appState.attentionPopoverSession.resetForWorkspaceSwitch()
        }
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

    func windowWillClose(_ notification: Notification) {
        // Release App-wide claims before SwiftUI tears down the per-window
        // model so an unresolved request can move to another exact window.
        appState.windowCloseCoordinator.finalize()
        if finalizeWindowAttachments(forwarding: notification) {
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

    private func showPreferredAttention() {
        guard let request = preferredAttentionRoute() else { return }
        attentionPresenter(request)
    }

    private func preferredAttentionRoute() -> AttentionPresentationRequest? {
        let ledgerData = UserDefaults.standard.data(
            forKey: AttentionPreferences.dismissalLedgerKey
        ) ?? Data()
        if appState.sidebarVisible {
            return .queue(
                anchor: .sidebar,
                workspaceSlot: nil,
                noteScope: nil
            )
        }

        if appState.shellState.researchActivityNotifications.contains(where: {
            $0.state.requiresResearcherAttention
        }) {
            return .actionStack
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
        return .queue(
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

    private func configureWindowFrame(_ window: NSWindow) {
        ScholiumWindowAppearance.apply(colorScheme, to: window)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ScholiumColorRole.documentBackground.nsColor
    }

    private func installToolbarIfPossible() {
        guard let window,
              let splitController,
              splitController.nativeSplitViewController.view.window === window
        else { return }
        if let toolbarController,
           toolbarController.controls(splitController.nativeSplitViewController) {
            toolbarController.install(in: window)
            return
        }
        let controller = ScholiumWorkspaceToolbarController(
            appState: appState,
            windowActions: actions,
            splitViewController: splitController.nativeSplitViewController
        )
        toolbarController = controller
        controller.install(in: window)
    }

    /// Keep the native toolbar band present from the window's first frame.
    /// The split-dependent tracking items replace this inert toolbar in place;
    /// document loading therefore cannot move the traffic lights or safe area.
    private func installLoadingToolbarIfNeeded() {
        guard toolbarController == nil, let window else { return }
        if window.toolbar !== loadingToolbar {
            window.toolbar = loadingToolbar
        }
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

    private func detachWindow(restoringPreviousDelegate: Bool = true) {
        if restoringPreviousDelegate,
           let window,
           window.delegate === self {
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
                let outcome = try await appState.windowCloseCoordinator.prepare()
                guard attempt == closeAttemptGeneration,
                      self.window === sender else { return }
                if let warning = outcome.presentationWarning {
                    appState.presentFeedback(
                        String(
                            localized: "The document was saved, but window state could not be saved. \(warning)",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .warning
                    )
                }
                scheduleAuthorizedClose(sender, attempt: attempt)
            } catch {
                guard attempt == closeAttemptGeneration,
                      self.window === sender else { return }
                flushInFlight = false
                appState.lastSaveError = error.localizedDescription
                appState.presentFeedback(
                    String(
                        localized: "Scholium kept this window open because the current note could not be saved. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .error
                )
            }
        }
        return false
    }

    private func scheduleAuthorizedClose(
        _ sender: NSWindow,
        attempt: UInt64
    ) {
        // AppKit synchronously invalidates the closing window's SwiftUI graph.
        // Let the async flush task unwind before beginning that invalidation so
        // SDK 27 does not evaluate View/Commands builders through the task's
        // stale executor context.
        DispatchQueue.main.async { @MainActor [weak self, weak sender] in
            guard let self, let sender,
                  attempt == self.closeAttemptGeneration,
                  self.window === sender else { return }
            self.closeIsAuthorized = true
            self.flushInFlight = false
            sender.performClose(nil)
        }
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
    let colorScheme: WindowColorSchemeChoice

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = configure
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        nsView.onWindowAttachment = configure
        if let window = nsView.window { configure(window) }
    }

    private func configure(_ window: NSWindow) {
        coordinator.update(colorScheme: colorScheme)
        coordinator.attach(to: window)
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentView,
        coordinator: Void
    ) {}
}

struct ResearchRecordsWindowAttachment: NSViewRepresentable {
    let triptychID: UUID
    let colorScheme: WindowColorSchemeChoice

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
        ScholiumWindowAppearance.apply(colorScheme, to: window)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ScholiumColorRole.documentBackground.nsColor
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
    }
}

struct SettingsWindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = configure
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        if let window = nsView.window { configure(window) }
    }

    private func configure(_ window: NSWindow) {
        window.tabbingMode = .disallowed
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ScholiumColorRole.surfaceBackground.nsColor
        window.animationBehavior = .none
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

/// Installs interactive SwiftUI content as the frontmost child of the native
/// window frame. A top-edge notification may therefore cover transparent
/// chrome without leaving AppKit above it in the pointer event path.
private final class ScholiumWindowTopOverlayHostingView<Content: View>:
    NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

struct ScholiumWindowTopOverlayHost<Overlay: View>: NSViewRepresentable {
    let topInset: CGFloat
    let overlay: Overlay

    init(
        topInset: CGFloat,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.topInset = topInset
        self.overlay = overlay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        context.coordinator.update(overlay: overlay, topInset: topInset)
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        context.coordinator.update(overlay: overlay, topInset: topInset)
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private weak var frameView: NSView?
        private var hostingView: ScholiumWindowTopOverlayHostingView<Overlay>?
        private var pendingTopInset: CGFloat = 0

        func update(overlay: Overlay, topInset: CGFloat) {
            pendingTopInset = topInset
            if let hostingView {
                hostingView.rootView = overlay
                hostingView.invalidateIntrinsicContentSize()
                hostingView.needsLayout = true
                hostingView.superview?.needsLayout = true
            } else {
                let hostingView = ScholiumWindowTopOverlayHostingView(
                    rootView: overlay
                )
                hostingView.translatesAutoresizingMaskIntoConstraints = true
                hostingView.autoresizingMask = [.minXMargin, .maxXMargin]
                hostingView.setContentHuggingPriority(.required, for: .horizontal)
                hostingView.setContentHuggingPriority(.required, for: .vertical)
                hostingView.setContentCompressionResistancePriority(
                    .required,
                    for: .horizontal
                )
                hostingView.setContentCompressionResistancePriority(
                    .required,
                    for: .vertical
                )
                hostingView.wantsLayer = true
                hostingView.layer?.zPosition = 10_000
                self.hostingView = hostingView
            }
            layoutHost()
            DispatchQueue.main.async { @MainActor [weak self] in
                self?.layoutHost()
            }
        }

        func attach(to window: NSWindow) {
            guard let hostingView,
                  let contentView = window.contentView else { return }
            let frameView: NSView
            if let titlebarView = fullWidthTitlebarView(in: window) {
                frameView = titlebarView
            } else {
                var rootView = contentView
                while let superview = rootView.superview {
                    rootView = superview
                }
                frameView = rootView
            }
            if self.window === window,
               self.frameView === frameView,
               hostingView.superview === frameView {
                layoutHost()
                return
            }
            detachHost()
            self.window = window
            self.frameView = frameView
            frameView.addSubview(hostingView, positioned: .above, relativeTo: nil)
            layoutHost()
        }

        private func fullWidthTitlebarView(in window: NSWindow) -> NSView? {
            var candidate = window.standardWindowButton(.closeButton)?.superview
            let minimumWidth = window.frame.width * 0.9
            let minimumHeight = max(
                ScholiumGrid.Dimension.minimumCustomTarget,
                window.frame.height - window.contentLayoutRect.height
            )
            while let view = candidate {
                if view.bounds.width >= minimumWidth,
                   view.bounds.height >= minimumHeight {
                    return view
                }
                candidate = view.superview
            }
            return nil
        }

        func detach() {
            detachHost()
            window = nil
            frameView = nil
        }

        private func detachHost() {
            hostingView?.removeFromSuperview()
        }

        private func layoutHost() {
            guard let window, let frameView, let hostingView else { return }
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            let topCenterInScreen = NSPoint(
                x: window.frame.midX,
                y: window.frame.maxY - pendingTopInset - (fittingSize.height / 2)
            )
            let topCenterInWindow = window.convertPoint(fromScreen: topCenterInScreen)
            let topCenter = frameView.convert(topCenterInWindow, from: nil)
            hostingView.frame = NSRect(
                x: topCenter.x - (fittingSize.width / 2),
                y: topCenter.y - (fittingSize.height / 2),
                width: fittingSize.width,
                height: fittingSize.height
            )
        }
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
