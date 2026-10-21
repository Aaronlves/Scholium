import Foundation
import ScholiumContracts

#if DEBUG
    import WebKit
#endif

/// Records synthetic-fixture performance boundaries only when an explicit
/// isolated JSONL destination and one supported metric are supplied. Records
/// contain timing and count metadata only—never queries, paths, or note text.
@MainActor
final class PerformanceProbe {
    enum Metric: String {
        case warmLibraryLaunch = "warm_library_launch"
        case indexedSearch = "indexed_search"
        case warmReadActivation = "warm_read_activation"
        case firstReadActivation = "first_read_activation"
        case editorKeyToPaint = "editor_key_to_paint"
        case editorModeTransition = "editor_mode_transition"
        case editorCachedPreview = "editor_cached_preview"
        case warmEditActivation = "warm_edit_activation"
        case firstEditActivation = "first_edit_activation"
        case noteOpenToInput = "note_open_to_input"
        case noteOpenToVisible = "note_open_to_visible"
        case editorVisibleProjection = "editor_visible_projection"
        case editorRetainedMemory = "editor_retained_memory"
        case editorLargeCJKCorrectness = "editor_large_cjk_correctness"
        case chatEntry = "chat_entry"
    }

    enum NoteOpeningPhase: String, CaseIterable {
        case transitionStarted = "transition_started"
        case prepared
        case hydrationStarted = "hydration_started"
        case hydrated
        case documentInstalled = "document_installed"
        case attached
        case rendererReady = "renderer_ready"
        case loaded
        case stableVisible = "stable_visible"
        case focused
    }

    enum NoteOpeningBridgeOperation: String {
        case initialize
        case completePreparation = "complete_preparation"
        case releasePreparation = "release_preparation"
    }

    /// Diagnostic milestones keep framework scheduling separate from the
    /// existing, user-visible opening endpoint. Only numeric offsets escape.
    enum NoteOpeningMilestone: String {
        case clickRecognized = "click_recognized"
        case outgoingFrozen = "outgoing_frozen"
        case outgoingFlushed = "outgoing_flushed"
        case outgoingRecaptured = "outgoing_recaptured"
        case poolRecycleEntered = "pool_recycle_entered"
        case poolOutgoingDetached = "pool_outgoing_detached"
        case poolHandoffOffered = "pool_handoff_offered"
        case poolReuseRequested = "pool_reuse_requested"
        case poolReuseReturned = "pool_reuse_returned"
        case mountRequested = "mount_requested"
        case pageAcquired = "page_acquired"
        case webViewPrepared = "web_view_prepared"
        case sessionPrepared = "session_prepared"
        case containerPrepared = "container_prepared"
        case bootstrapLoadRequested = "bootstrap_load_requested"
        case bootstrapLoadReturned = "bootstrap_load_returned"
        case bootstrapNavigationStarted = "bootstrap_navigation_started"
        case bootstrapNavigationCommitted = "bootstrap_navigation_committed"
        case bootstrapNavigationFinished = "bootstrap_navigation_finished"
        case loadScheduled = "load_scheduled"
        case loadStarted = "load_started"
        case initializationRequested = "initialization_requested"
        case initialized
        case presentationConverged = "presentation_converged"
        case preparationCompleted = "preparation_completed"
        case sessionLoaded = "session_loaded"
        case readProjectionStarted = "read_projection_started"
        case readProjectionReady = "read_projection_ready"
    }

    enum NoteOpeningWork: String {
        case citationPresentation = "citation_presentation"
        case outlineProjection = "outline_projection"
        case editorScriptLoad = "editor_script_load"
        case editorResourceValidation = "editor_resource_validation"
        case editorContainerConstruction = "editor_container_construction"
    }

    static let shared = PerformanceProbe()

    #if DEBUG
        static let qaMemoryOwnerNotification =
            "com.scholium.qa.performance-memory-owner-snapshot"
        private static let qaMemoryOwnerFilename = "qa-memory-owner-diagnostics.jsonl"

        enum QAReaderFailurePhase: String {
            case finalization
            case navigation
            case provisionalNavigation = "provisional_navigation"
            case processTerminated = "process_terminated"
            case presentationUpdate = "presentation_update"
        }

        enum QASaveStage: String {
            case nativeKeyMenuResult = "native_key_menu_result"
            case nativeMenuEntry = "native_menu_entry"
            case jsSaveAdmission = "js_save_admission"
            case editorDeltaAdmission = "editor_delta_admission"
            case controllerRequest = "controller_request"
            case controllerJoin = "controller_join"
            case controllerAttempt = "controller_attempt"
            case controllerSnapshot = "controller_snapshot"
            case controllerCommitted = "controller_committed"
            case controllerAcknowledged = "controller_acknowledged"
            case controllerFailed = "controller_failed"
        }

        enum QASaveFlag: String {
            case accepted, composing, dirty, superseded, cancelled, conflict
            case surfaceActive = "surface_active"
            case sameTransport = "same_transport"
            case sameDocument = "same_document"
            case sameFingerprint = "same_fingerprint"
            case sameGeneration = "same_generation"
            case actionsPresent = "actions_present"
            case selectedDocument = "selected_document"
            case menuHandled = "menu_handled"
            case menuEnabled = "menu_enabled"
            case menuItemFound = "menu_item_found"
            case activeSave = "active_save"
            case sourceMatchesCommitted = "source_matches_committed"
            case externalFlush = "external_flush"
        }

        enum QASaveCount: String {
            case generation
            case messageGeneration = "message_generation"
            case snapshotGeneration = "snapshot_generation"
        }
    #endif

    private struct Configuration {
        let resultURL: URL
        let runID: String
        let firstSample: Int
        let sampleCount: Int
        let metric: Metric
        let expectedQuery: String?
        let expectedDocument: String?
        let expectedCount: Int?
        let externalStartNanoseconds: UInt64?
        let initialReviewPresentation: Bool
    }

    private let configuration: Configuration?
    private let now: () -> UInt64
    #if DEBUG
        private let qaMemoryOwnerResultURL: URL?
        private var qaMemoryOwnerSampleCount = 0
        private var qaEditorWorkSampleCount = 0
        private var qaReaderFailureCount = 0
        private var qaSaveStageCount = 0
    #endif
    private var searchStartNanoseconds: UInt64?
    private var searchDispatchNanoseconds: UInt64?
    private var readStartNanoseconds: UInt64?
    private var editorModeTransition:
        (
            documentID: String,
            mode: MarkdownEditorMode,
            startNanoseconds: UInt64,
            bridgeStartedNanoseconds: UInt64?,
            acknowledgedNanoseconds: UInt64?
        )?
    private var editActivation:
        (
            documentID: String,
            startNanoseconds: UInt64,
            attachedNanoseconds: UInt64?,
            rendererReadyNanoseconds: UInt64?,
            loadedObservedNanoseconds: UInt64?,
            reusedPage: Bool?
        )?
    private var cachedPreviewStart: (documentID: String, nanoseconds: UInt64)?
    private var warmLibraryWindowModelInitializationNanoseconds: UInt64?
    private var warmLibraryWorkspaceReadyNanoseconds: UInt64?
    private var startupSafetyReadyNanoseconds: UInt64?
    private var vaultConfigurationReadyNanoseconds: UInt64?
    private var warmLibraryProjectionNanoseconds: UInt64?
    private var firstReadDocumentSelectedNanoseconds: UInt64?
    private var firstReadTaskStartedNanoseconds: UInt64?
    private var firstReadHTMLReadyNanoseconds: UInt64?
    private var firstReadNavigationStartedNanoseconds: UInt64?
    private var firstReadNavigationFinishedNanoseconds: UInt64?
    private var searchIsArmed = true
    private var readIsArmed = true
    private var recordedSampleCount = 0
    private var pendingNoteOpeningDumpCount = 0
    private struct ChatEntry {
        let id = UUID()
        let conversationID: UUID
        let messageCount: Int
        let started: UInt64
        var mounted: UInt64?
        var hydrated: UInt64?
        var readerCount = 0
    }
    private var chatEntry: ChatEntry?
    private var chatEntryTask: Task<Void, Never>?
    private struct NoteOpening {
        let id: UUID
        let documentID: String
        let started: UInt64
        var editorSessionID: UUID?
        var sourceReusedAt: UInt64?
        var phases: [NoteOpeningPhase: UInt64] = [:]
        var milestones: [NoteOpeningMilestone: UInt64] = [:]
        var work: [NoteOpeningWork: (total: UInt64, maximum: UInt64, count: Int)] = [:]
        var bridges: [NoteOpeningBridgeOperation: (returned: UInt64, validated: UInt64, count: Int)] =
            [:]
    }
    private var noteOpening: NoteOpening?
    private var completedNoteOpening: (sample: Int, documentID: String, editorSessionID: UUID)?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleID: String? = Bundle.main.bundleIdentifier,
        bundleURL: URL = Bundle.main.bundleURL,
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.now = now
        #if DEBUG
            qaMemoryOwnerResultURL = Self.safeQAMemoryOwnerResultURL(
                environment: environment,
                arguments: arguments,
                bundleID: bundleID,
                bundleURL: bundleURL
            )
        #endif
        let requestedSampleCount =
            environment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"]
            .flatMap(Int.init) ?? 1
        guard let rawURL = environment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"],
            let rawMetric = environment["SCHOLIUM_PERFORMANCE_METRIC"],
            let metric = Metric(rawValue: rawMetric),
            metric != .chatEntry || bundleID == ScholiumRuntimeIsolation.qaBundleIdentifier,
            let rawRunID = environment["SCHOLIUM_PERFORMANCE_RUN_ID"],
            Self.isSafeRunID(rawRunID),
            let bundleID,
            Self.allowsConfiguration(
                environment: environment,
                bundleID: bundleID,
                arguments: arguments
            ),
            let resultURL = Self.safeResultURL(
                rawURL,
                runID: rawRunID,
                bundleID: bundleID,
                isolatedHomePath: environment["SCHOLIUM_HOME"]
            ),
            let rawSample = environment["SCHOLIUM_PERFORMANCE_SAMPLE"],
            let sample = Int(rawSample),
            sample >= 0,
            requestedSampleCount > 0,
            requestedSampleCount <= 1_000,
            sample <= Int.max - requestedSampleCount
        else {
            configuration = nil
            return
        }
        configuration = Configuration(
            resultURL: resultURL,
            runID: rawRunID,
            firstSample: sample,
            sampleCount: requestedSampleCount,
            metric: metric,
            expectedQuery: environment["SCHOLIUM_PERFORMANCE_EXPECTED_QUERY"],
            expectedDocument: environment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"],
            expectedCount: environment["SCHOLIUM_PERFORMANCE_EXPECTED_COUNT"].flatMap(Int.init),
            externalStartNanoseconds: environment["SCHOLIUM_PERFORMANCE_STARTED_NS"].flatMap(UInt64.init),
            initialReviewPresentation: environment["SCHOLIUM_PERFORMANCE_INITIAL_REVIEW"] == "1"
        )
    }

    var isEnabled: Bool { configuration != nil }
    var measuresChatEntry: Bool { configuration?.metric == .chatEntry }
    var measuresNoteOpeningLifecycle: Bool {
        configuration?.metric == .noteOpenToInput || configuration?.metric == .noteOpenToVisible
    }

    func measuresNoteOpening(documentID: String) -> Bool {
        measuresNoteOpeningLifecycle && configuration?.expectedDocument == documentID
    }

    @discardableResult
    func beginNoteOpening(documentID: String, startNanoseconds: UInt64? = nil) -> UUID? {
        noteOpening = nil
        completedNoteOpening = nil
        guard let configuration, measuresNoteOpeningLifecycle,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else { return nil }
        let observed = now()
        let started = startNanoseconds ?? observed
        guard started <= observed else { return nil }
        let opening = NoteOpening(id: UUID(), documentID: documentID, started: started)
        noteOpening = opening
        return opening.id
    }

    func currentNoteOpeningAttempt(documentID: String) -> UUID? {
        guard measuresNoteOpeningLifecycle, noteOpening?.documentID == documentID else { return nil }
        return noteOpening?.id
    }

    /// Lifecycle owners without a destination identity capture this token
    /// before suspension; a late completion cannot borrow a newer attempt.
    var armedNoteOpeningAttemptID: UUID? {
        measuresNoteOpeningLifecycle ? noteOpening?.id : nil
    }

    func currentNoteOpeningAttempt(editorSessionID: UUID) -> UUID? {
        guard measuresNoteOpeningLifecycle, noteOpening?.editorSessionID == editorSessionID else {
            return nil
        }
        return noteOpening?.id
    }

    @discardableResult
    func bindNoteOpening(attemptID: UUID?, documentID: String? = nil, editorSessionID: UUID) -> Bool {
        guard let attemptID, let opening = noteOpening, opening.id == attemptID,
            documentID == nil || documentID == opening.documentID,
            opening.editorSessionID == nil || opening.editorSessionID == editorSessionID
        else { return false }
        noteOpening?.editorSessionID = editorSessionID
        return true
    }

    func cancelNoteOpening(attemptID: UUID?) {
        guard let attemptID, noteOpening?.id == attemptID else { return }
        noteOpening = nil
    }

    /// A replacement WebContent process has a new JavaScript clock and
    /// attachment counter. Never join its samples to the lost page's opening.
    func invalidateNoteOpeningPage(editorSessionID: UUID) {
        if noteOpening?.editorSessionID == editorSessionID { noteOpening = nil }
        if completedNoteOpening?.editorSessionID == editorSessionID { completedNoteOpening = nil }
    }

    /// The opening owner has revalidated a retained exact-source snapshot.
    /// Reuse is a distinct source-resolution boundary, never disk hydration.
    func markNoteOpeningSourceReused(attemptID: UUID?, documentID: String) {
        guard let attemptID, var opening = noteOpening, opening.id == attemptID,
            opening.documentID == documentID, opening.sourceReusedAt == nil
        else { return }
        let timestamp = now()
        guard timestamp >= opening.started,
            timestamp >= (opening.phases.values.max() ?? opening.started)
        else { return }
        opening.sourceReusedAt = timestamp
        noteOpening = opening
    }

    func markNoteOpeningMilestone(
        _ milestone: NoteOpeningMilestone, attemptID: UUID?, editorSessionID: UUID? = nil
    ) {
        guard let attemptID, var opening = noteOpening, opening.id == attemptID,
            editorSessionID == nil || opening.editorSessionID == editorSessionID,
            opening.milestones[milestone] == nil
        else { return }
        let timestamp = now()
        guard timestamp >= opening.started else { return }
        opening.milestones[milestone] = timestamp
        noteOpening = opening
    }

    func measureNoteOpeningWork<Value>(
        _ work: NoteOpeningWork, documentID: String, editorSessionID: UUID,
        operation: () -> Value
    ) -> Value {
        guard let attemptID = currentNoteOpeningAttempt(documentID: documentID),
            noteOpening?.editorSessionID == nil || noteOpening?.editorSessionID == editorSessionID
        else { return operation() }
        let started = now()
        let value = operation()
        let ended = now()
        if var opening = noteOpening, opening.id == attemptID, started >= opening.started,
            ended >= started
        {
            let elapsed = ended - started
            let previous = opening.work[work] ?? (total: 0, maximum: 0, count: 0)
            let (total, overflow) = previous.total.addingReportingOverflow(elapsed)
            if !overflow, total < 600_000_000_000, previous.count < Int.max {
                opening.work[work] = (total, max(previous.maximum, elapsed), previous.count + 1)
                noteOpening = opening
            }
        }
        return value
    }

    func markNoteOpeningPhase(
        _ phase: NoteOpeningPhase, attemptID: UUID?, documentID: String? = nil,
        editorSessionID: UUID? = nil
    ) {
        guard let attemptID, var opening = noteOpening, opening.id == attemptID,
            documentID == nil || documentID == opening.documentID,
            opening.phases[phase] == nil
        else { return }
        switch phase {
        case .attached, .rendererReady, .loaded, .stableVisible, .focused:
            guard let editorSessionID, opening.editorSessionID == editorSessionID else { return }
        default:
            if let editorSessionID, opening.editorSessionID != editorSessionID { return }
        }
        let timestamp = now()
        guard timestamp >= opening.started,
            timestamp >= (opening.phases.values.max() ?? opening.started)
        else { return }
        opening.phases[phase] = timestamp
        noteOpening = opening
        guard let visible = opening.phases[.stableVisible] else { return }
        let focused: UInt64
        if configuration?.metric == .noteOpenToVisible {
            focused = visible
        } else if let received = opening.phases[.focused] {
            focused = received
        } else {
            return
        }
        let sourceResolvedAt: UInt64?
        if let hydrationStarted = opening.phases[.hydrationStarted],
            let hydrated = opening.phases[.hydrated], hydrated >= hydrationStarted
        {
            sourceResolvedAt = hydrated
        } else {
            sourceResolvedAt = opening.sourceReusedAt
        }
        guard let sourceResolvedAt, sourceResolvedAt <= min(visible, focused) else { return }
        let completed = max(visible, focused)
        noteOpening = nil
        let previousCount = recordedSampleCount
        record(
            startNanoseconds: opening.started, observedCount: nil, completedNanoseconds: completed,
            phaseDurations: noteOpeningDurations(opening, completed: completed)
        )
        if recordedSampleCount > previousCount, let configuration,
            let sessionID = opening.editorSessionID
        {
            completedNoteOpening = (
                configuration.firstSample + previousCount, opening.documentID, sessionID
            )
        }
    }

    func markNoteOpeningEditorPhase(
        _ phase: NoteOpeningPhase, editorSessionID: UUID, attemptID: UUID? = nil
    ) {
        guard let currentAttempt = currentNoteOpeningAttempt(editorSessionID: editorSessionID),
            attemptID == nil || attemptID == currentAttempt
        else { return }
        switch phase {
        case .attached, .rendererReady, .loaded, .stableVisible, .focused:
            markNoteOpeningPhase(phase, attemptID: currentAttempt, editorSessionID: editorSessionID)
        default:
            return
        }
    }

    func recordNoteOpeningBridge(
        operation: NoteOpeningBridgeOperation, attemptID: UUID, editorSessionID: UUID,
        dispatchNanoseconds: UInt64, returnedNanoseconds: UInt64, validatedNanoseconds: UInt64
    ) {
        guard var opening = noteOpening, opening.id == attemptID,
            opening.editorSessionID == editorSessionID,
            dispatchNanoseconds >= opening.started, returnedNanoseconds >= dispatchNanoseconds,
            validatedNanoseconds >= returnedNanoseconds, validatedNanoseconds <= now()
        else { return }
        let existing = opening.bridges[operation] ?? (returned: 0, validated: 0, count: 0)
        let (returned, returnOverflow) = existing.returned.addingReportingOverflow(
            returnedNanoseconds - dispatchNanoseconds)
        let (validated, validationOverflow) = existing.validated.addingReportingOverflow(
            validatedNanoseconds - returnedNanoseconds)
        guard !returnOverflow, !validationOverflow, returned < 600_000_000_000,
            validated < 600_000_000_000, existing.count < Int.max
        else { return }
        opening.bridges[operation] = (returned, validated, existing.count + 1)
        noteOpening = opening
    }

    func completedNoteOpeningSample(documentID: String, editorSessionID: UUID) -> Int? {
        guard measuresNoteOpeningLifecycle, noteOpening == nil,
            let completed = completedNoteOpening, completed.documentID == documentID,
            completed.editorSessionID == editorSessionID
        else { return nil }
        return completed.sample
    }

    /// On-demand failure evidence; emits only closed phase names, booleans
    /// and numeric offsets, independently of whether pixels have appeared.
    func recordPendingNoteOpeningState(
        editorSessionID: UUID, isEditing: Bool, editorIsLoaded: Bool, editorIsReady: Bool,
        editorHasWebView: Bool, windowModeIsEditing: Bool, focusState: [String: Bool] = [:]
    ) {
        guard let configuration, measuresNoteOpeningLifecycle, pendingNoteOpeningDumpCount < 4 else { return }
        let destination = configuration.resultURL.deletingPathExtension().appendingPathExtension("pending.jsonl")
        var value: [String: Any] = [
            "recorded_samples": recordedSampleCount,
            "has_pending": noteOpening != nil, "has_completed": completedNoteOpening != nil,
            "current_session_matches_pending": noteOpening?.editorSessionID == editorSessionID,
            "current_is_editing": isEditing, "current_loaded": editorIsLoaded, "current_ready": editorIsReady,
            "current_has_webview": editorHasWebView, "window_mode_is_editing": windowModeIsEditing,
        ]
        let focusKeys: Set<String> = [
            "authorized", "pending", "closed", "composing", "suspended", "mode_matches",
            "native", "allows_input", "hidden", "key_window", "sheet", "responder",
        ]
        if !focusState.isEmpty { value["focus"] = focusState.filter { focusKeys.contains($0.key) } }
        if let opening = noteOpening {
            value["bound_session"] = opening.editorSessionID != nil
            value["source_reused"] = opening.sourceReusedAt != nil
            value["phases"] = Dictionary(
                uniqueKeysWithValues: opening.phases.map {
                    ($0.key.rawValue, milliseconds($0.value - opening.started))
                })
            value["milestones"] = Dictionary(
                uniqueKeysWithValues: opening.milestones.map {
                    ($0.key.rawValue, milliseconds($0.value - opening.started))
                })
        }
        if append(value, to: destination) { pendingNoteOpeningDumpCount += 1 }
    }

    func recordNoteOpeningWebSamples(
        _ samples: [MarkdownEditorPerformanceSample], documentID: String, sample: Int? = nil
    ) {
        guard let configuration, measuresNoteOpeningLifecycle, recordedSampleCount > 0, noteOpening == nil,
            documentID == configuration.expectedDocument, let completed = completedNoteOpening,
            completed.documentID == documentID, sample == nil || sample == completed.sample,
            samples.count <= 256
        else { return }
        let allowedNames: Set<String> = [
            "startup", "projection", "projection-index", "exact-source-update", "document-load",
            "bootstrap", "bootstrap-state", "bootstrap-view",
            "bridge-request",
            "opening-atomic-state", "opening-preparation", "opening-release",
            "memory-sample", "scroll-session", "mode-toggle", "mode-toggle-work", "cached-preview",
            "cached-preview-work",
            "input-to-state", "input-to-paint", "key-to-state", "key-to-paint",
            "projection-topology-proof", "projection-index-map", "exact-source-admission",
            "recovery-restore", "recovery-composition", "recovery-live-install",
            "bridge-dispatch-stages", "bridge-message-post", "interaction-report-queue", "interaction-context",
            "citation-projection-admission", "citation-catalog", "citation-field-validation",
            "review-html-insertion", "review-reader-initialization", "review-scroll-registry", "review-layout-settle",
        ]
        let allowedObserved: Set<String> = [
            "documentLength", "visibleRangeCount", "decorationCount", "projectionWindowUTF16Count",
            "changeCount",
            "requestBytes", "resultBytes", "styleWorkMilliseconds", "fontsWaitMilliseconds",
            "projectionWorkMilliseconds",
            "measureWorkMilliseconds", "scrollWorkMilliseconds", "measureCount", "measureCompletedCount", "loopCount",
            "widgetWaitMilliseconds",
            "widgetWaitCount", "imageWaitMilliseconds", "imageWaitCount", "completed", "expired",
            // Unified-host preparation reports completed measurements, pending
            // visible widgets and Review without exposing document content.
            "widgetWaitEnteredCount", "pendingMathWidgetCount", "pendingMermaidWidgetCount", "pendingOtherWidgetCount", "review",
            "selectionScoped", "viewportIncremental", "widgetReuseCount", "usedJSHeapBytes", "frameCount",
            "longestFrameMilliseconds", "droppedFrameCount", "transitionSequence", "composing",
            "literalCount", "tableCount", "calloutCount", "footnoteCount",
            "blockCount", "inlineCount", "mapped", "localProof", "admitted",
            "semanticMapMilliseconds", "derivedMapMilliseconds", "finalizationMilliseconds",
            "documentStartToBundleStartMilliseconds", "bundleStartToEntryMilliseconds",
            "entryToBundleEndMilliseconds", "bundleExecutionMilliseconds",
            // Exact-history/bootstrap producers, including refused-history fallback.
            "sourceUTF16Length", "historyBytes", "capacityMilliseconds", "parseMilliseconds",
            "payloadValidationMilliseconds", "firstStateMilliseconds", "roundtripAndEffectsMilliseconds",
            "doneEvents", "undoneEvents", "finalStateMilliseconds", "finalAdmissionMilliseconds", "branchesMilliseconds",
            "rangeCount", "historyPreserved", "selectionMilliseconds", "codecMilliseconds", "bindingMilliseconds",
            "failedHistoryAttemptMilliseconds", "fallbackMilliseconds", "recovery",
            // Bridge, interaction scheduling and input/paint producers in editor.ts.
            "requestEnvelopeMilliseconds", "admissionMilliseconds", "executeMilliseconds", "resultEnvelopeMilliseconds", "accepted",
            "generation", "interactionRevision", "documentChanged", "postedAtMilliseconds", "frame", "watchdog", "explicit",
            "trustedInput", "visibilityVisible", "documentHasFocus", "editorOwnsFocus", "frameWaitMilliseconds", "taskWaitMilliseconds",
            // Citation projection/validation and topology-proof subphases.
            "fieldCount", "catalogMilliseconds", "rangeMappingMilliseconds", "reservedScanMilliseconds",
            "snapshotMilliseconds", "parserContextMilliseconds", "companionValidationMilliseconds",
            "vendorTextMilliseconds", "fallbackTextMilliseconds",
            "ensureTreeMilliseconds", "languageStateReadMilliseconds", "ensureTreeAfterStateReadMilliseconds",
            "previousLocalPreparationMilliseconds", "nextSemanticMilliseconds", "signatureMilliseconds",
            "fullTextMaterializationMilliseconds", "fullTextMaterializationUTF16Count",
            "htmlUTF16Length", "candidateCount", "registeredBlockCount", "styleReadCount",
            "mathWaitMilliseconds", "mermaidWaitMilliseconds", "geometryChanged",
        ]
        guard
            samples.allSatisfy({ value in
                allowedNames.contains(value.name) && value.durationMilliseconds.isFinite
                    && value.durationMilliseconds >= 0
                    && value.observed.allSatisfy {
                        allowedObserved.contains($0.key) && $0.value.isFinite && $0.value >= 0
                    }
            })
        else { return }
        let destination = configuration.resultURL.deletingPathExtension().appendingPathExtension(
            "web.jsonl")
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil
        else { return }
        let values: [[String: Any]] = samples.map {
            ["name": $0.name, "duration_ms": $0.durationMilliseconds, "observed": $0.observed]
        }
        _ = append(
            [
                "schema": "scholium-note-opening-web-v1", "run_id": configuration.runID,
                "sample": completed.sample, "samples": values,
            ], to: destination)
    }

    /// Diagnostic-only QA timing. Each activation owns a token, so an outgoing
    /// page cannot complete a later visit to the same conversation.
    func beginChatEntry(in conversationID: UUID, messageCount: Int) {
        guard measuresChatEntry else { return }
        cancelChatEntry()
        chatEntry = ChatEntry(
            conversationID: conversationID, messageCount: messageCount, started: now())
    }

    func chatEntryID(in conversationID: UUID?) -> UUID? {
        guard chatEntry?.conversationID == conversationID else { return nil }
        return chatEntry?.id
    }

    func markChatDetailMounted(_ id: UUID, readerCount: Int) {
        guard chatEntry?.id == id, chatEntry?.mounted == nil else { return }
        chatEntry?.mounted = now()
        chatEntry?.readerCount = readerCount
    }

    func markChatReadersHydrated(_ id: UUID, viewportIsReady: @escaping @MainActor () -> Bool) {
        guard chatEntry?.id == id, chatEntry?.mounted != nil, chatEntry?.hydrated == nil else { return }
        chatEntry?.hydrated = now()
        chatEntryTask = Task { @MainActor [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !Task.isCancelled, ContinuousClock.now < deadline {
                guard let self, let entry = self.chatEntry, entry.id == id else { return }
                if viewportIsReady(), let mounted = entry.mounted, let hydrated = entry.hydrated {
                    let completed = self.now()
                    guard mounted >= entry.started, hydrated >= mounted, completed >= hydrated else { return }
                    self.record(
                        startNanoseconds: entry.started, observedCount: entry.messageCount,
                        completedNanoseconds: completed,
                        phaseDurations: [
                            "detail_mount_ms": self.milliseconds(mounted - entry.started),
                            "reply_hydration_ms": self.milliseconds(hydrated - mounted),
                            "viewport_position_ms": self.milliseconds(completed - hydrated),
                            "mounted_reader_count": Double(entry.readerCount),
                        ])
                    self.chatEntry = nil
                    self.chatEntryTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func cancelChatEntry() {
        chatEntryTask?.cancel()
        chatEntryTask = nil
        chatEntry = nil
    }
    #if DEBUG
        var measuresQAMemoryOwners: Bool { qaMemoryOwnerResultURL != nil }

        /// Content-free editor phase samples share the existing synthetic QA
        /// authorization and isolated home. They never include source or identity.
        func recordQAEditorWork(_ samples: [MarkdownEditorPerformanceSample]) {
            guard let qaMemoryOwnerResultURL, qaEditorWorkSampleCount < 16,
                samples.count <= 256
            else { return }
            let names: Set<String> = [
                "projection", "projection-index", "projection-topology-proof", "projection-index-map",
                "exact-source-admission", "exact-source-update", "input-to-state", "key-to-state",
                "input-to-paint", "key-to-paint", "scroll-session", "bridge-request",
                "citation-field-validation", "citation-catalog", "citation-projection-admission",
                "interaction-report-queue", "interaction-context", "bridge-message-post",
                "startup", "opening-atomic-state", "opening-preparation", "opening-release",
                "bootstrap", "bootstrap-state", "bootstrap-view",
            ]
            let fields: Set<String> = [
                "documentLength", "changeCount", "blockCount", "inlineCount", "literalCount",
                "tableCount", "calloutCount", "footnoteCount", "mapped", "localProof", "admitted",
                "semanticMapMilliseconds", "derivedMapMilliseconds", "finalizationMilliseconds",
                "composing", "decorationCount", "visibleRangeCount", "projectionWindowUTF16Count",
                "frameCount", "longestFrameMilliseconds", "droppedFrameCount",
                "generation", "interactionRevision", "trustedInput", "visibilityVisible",
                "documentHasFocus", "editorOwnsFocus", "frame", "watchdog", "explicit",
                "frameWaitMilliseconds", "taskWaitMilliseconds",
                "documentChanged", "postedAtMilliseconds", "fieldCount",
                "companionValidationMilliseconds", "vendorTextMilliseconds", "fallbackTextMilliseconds",
                "reservedScanMilliseconds", "snapshotMilliseconds", "parserContextMilliseconds",
                "catalogMilliseconds", "rangeMappingMilliseconds",
                "ensureTreeMilliseconds", "languageStateReadMilliseconds", "ensureTreeAfterStateReadMilliseconds",
                "previousLocalPreparationMilliseconds", "nextSemanticMilliseconds",
                "signatureMilliseconds", "fullTextMaterializationMilliseconds", "fullTextMaterializationUTF16Count",
                "styleWorkMilliseconds", "fontsWaitMilliseconds", "projectionWorkMilliseconds",
                "measureWorkMilliseconds", "scrollWorkMilliseconds", "measureCount", "loopCount",
                "widgetWaitMilliseconds", "widgetWaitCount", "imageWaitMilliseconds", "imageWaitCount",
                "completed", "expired",
                "documentStartToBundleStartMilliseconds", "bundleStartToEntryMilliseconds",
                "entryToBundleEndMilliseconds", "bundleExecutionMilliseconds",
            ]
            let values: [[String: Any]] = samples.compactMap { sample in
                guard names.contains(sample.name), sample.durationMilliseconds.isFinite,
                    sample.durationMilliseconds >= 0
                else { return nil }
                return [
                    "name": sample.name, "duration_ms": sample.durationMilliseconds,
                    "observed": sample.observed.filter {
                        fields.contains($0.key) && $0.value.isFinite && $0.value >= 0
                    },
                ]
            }
            guard !values.isEmpty else { return }
            let result = qaMemoryOwnerResultURL.deletingLastPathComponent()
                .appendingPathComponent("qa-editor-work.jsonl")
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: result.path)) == nil,
                append(
                    [
                        "schema": "scholium-qa-editor-work-v1", "sample": qaEditorWorkSampleCount,
                        "completed_uptime_ns": now(), "measurements": values,
                    ], to: result)
            else { return }
            qaEditorWorkSampleCount += 1
        }

        func recordQAMemoryOwners(_ stats: DocumentController.QAMemoryOwnerStats) {
            guard let resultURL = qaMemoryOwnerResultURL,
                qaMemoryOwnerSampleCount < 128
            else { return }
            let object: [String: Any] = [
                "schema": "scholium-qa-memory-owners-v1",
                "sample": qaMemoryOwnerSampleCount,
                "completed_uptime_ns": now(),
                "retained_sessions": stats.retainedSessions,
                "leased_sessions": stats.leasedSessions,
                "pinned_sessions": stats.pinnedSessions,
                "attached_webview_sessions": stats.attachedWebViewSessions,
                "full_snapshots": stats.fullSnapshots,
                "pending_hydrations": stats.pendingHydrations,
                "read_projection_entries": stats.readProjectionEntries,
                "read_projection_html_utf8_bytes": stats.readProjectionHTMLUTF8Bytes,
                "editor_pool_idle": stats.editorPoolIdle,
                "editor_pool_attached": stats.editorPoolAttached,
                "editor_pool_preparing": stats.editorPoolPreparing,
                "editor_pool_abandoned_live": stats.editorPoolAbandonedLive,
                "editor_pool_waiting": stats.editorPoolWaiting,
            ]
            // `createFile` can follow a dangling symlink before the shared
            // append helper checks it. Keep this QA artifact inside its home.
            guard
                (try? FileManager.default.destinationOfSymbolicLink(
                    atPath: resultURL.path
                )) == nil,
                append(object, to: resultURL)
            else { return }
            qaMemoryOwnerSampleCount += 1
        }

        /// Reuses the memory-owner probe's verified synthetic QA home. Error
        /// payloads and document identity never leave their owning renderer.
        func recordQAReaderFailure(
            phase: QAReaderFailurePhase, generation: UInt64, error: (any Error)? = nil
        ) {
            guard let qaMemoryOwnerResultURL, qaReaderFailureCount < 32,
                error != nil || phase == .processTerminated
            else { return }
            let resultURL = qaMemoryOwnerResultURL.deletingLastPathComponent()
                .appendingPathComponent("qa-reader-failures.jsonl")
            var object: [String: Any] = [
                "schema": "scholium-qa-reader-failures-v1",
                "sample": qaReaderFailureCount,
                "completed_uptime_ns": now(),
                "phase": phase.rawValue,
                "generation": generation,
                "category": "process_terminated",
            ]
            if let error {
                let nsError = error as NSError
                object["error_domain"] = nsError.domain
                object["error_code"] = nsError.code
                var category = "error"
                if error is CancellationError
                    || nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
                    || nsError.domain == NSCocoaErrorDomain
                        && nsError.code == CocoaError.Code.userCancelled.rawValue
                {
                    category = "cancelled"
                }
                if let lifecycleError = error as? ScholiumWindowLifecycleError {
                    switch lifecycleError {
                    case .timedOut: category = "deadline"
                    case .cancelled: category = "cancelled"
                    default: break
                    }
                }
                object["category"] = category
                if nsError.domain == WKErrorDomain,
                    nsError.code == WKError.Code.javaScriptExceptionOccurred.rawValue
                {
                    // WebKit's exception message can include authored content.
                    // Emit only exact app-owned classifications, never text.
                    let classification: String
                    switch nsError.userInfo["WKJavaScriptExceptionMessage"] as? String {
                    case "stale reader preparation", "Error: stale reader preparation":
                        classification = "stale_reader_preparation"
                    case "stale presentation update", "Error: stale presentation update":
                        classification = "stale_presentation_update"
                    default:
                        classification = "other"
                    }
                    object["javascript_exception"] = classification
                }
            }
            guard
                (try? FileManager.default.destinationOfSymbolicLink(atPath: resultURL.path)) == nil,
                append(object, to: resultURL)
            else { return }
            qaReaderFailureCount += 1
        }

        /// Optional, bounded stage evidence inside the existing synthetic QA
        /// boundary. Closed keys admit no source, paths, titles or error text.
        func recordQASaveStage(
            _ stage: QASaveStage, sessionID: UUID? = nil, saveToken: UUID? = nil,
            flags: @autoclosure () -> [QASaveFlag: Bool] = [:],
            counts: @autoclosure () -> [QASaveCount: Int] = [:]
        ) {
            guard let qaMemoryOwnerResultURL, qaSaveStageCount < 512 else { return }
            let counts = counts()
            guard counts.values.allSatisfy({ $0 >= 0 }) else { return }
            let flags = flags()
            let resultURL = qaMemoryOwnerResultURL.deletingLastPathComponent()
                .appendingPathComponent("qa-save-stages.jsonl")
            var object: [String: Any] = [
                "schema": "scholium-qa-save-stages-v1",
                "sample": qaSaveStageCount,
                "completed_uptime_ns": now(),
                "stage": stage.rawValue,
                "flags": Dictionary(uniqueKeysWithValues: flags.map { ($0.key.rawValue, $0.value) }),
                "counts": Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            ]
            object["session_id"] = sessionID?.uuidString
            object["save_token"] = saveToken?.uuidString
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: resultURL.path)) == nil,
                let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                encoded.count < 2_048
            else { return }
            let maximumBytes = 512 * 1_024
            if FileManager.default.fileExists(atPath: resultURL.path) {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: resultURL.path),
                    attributes[.type] as? FileAttributeType == .typeRegular,
                    let size = attributes[.size] as? NSNumber,
                    size.intValue >= 0, size.intValue <= maximumBytes - encoded.count - 1
                else { return }
            }
            guard append(object, to: resultURL) else { return }
            qaSaveStageCount += 1
        }
    #endif
    var measuresWarmLibraryLaunch: Bool {
        configuration?.metric == .warmLibraryLaunch
    }
    var measuresEditorModeTransition: Bool {
        configuration?.metric == .editorModeTransition
    }
    var measuresEditorKeyToPaint: Bool {
        configuration?.metric == .editorKeyToPaint
    }
    var measuresEditorCachedPreview: Bool {
        configuration?.metric == .editorCachedPreview
    }
    var measuresEditorVisibleProjection: Bool {
        configuration?.metric == .editorVisibleProjection
    }
    var exercisesLargeCJKCorrectness: Bool {
        configuration?.metric == .editorLargeCJKCorrectness
    }
    var requiresInitialReviewPresentation: Bool {
        configuration?.metric == .warmReadActivation
            || configuration?.metric == .firstReadActivation
            || configuration?.metric == .firstEditActivation
            || (measuresNoteOpeningLifecycle && configuration?.initialReviewPresentation == true)
    }

    func markWarmLibraryWindowModelInitializationStarted() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryWindowModelInitializationNanoseconds == nil
        else { return }
        warmLibraryWindowModelInitializationNanoseconds = now()
    }

    func markWarmLibraryWorkspaceReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryWorkspaceReadyNanoseconds == nil
        else { return }
        warmLibraryWorkspaceReadyNanoseconds = now()
    }

    func markStartupSafetyReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            startupSafetyReadyNanoseconds == nil
        else { return }
        startupSafetyReadyNanoseconds = now()
    }

    func markVaultConfigurationReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            vaultConfigurationReadyNanoseconds == nil
        else { return }
        vaultConfigurationReadyNanoseconds = now()
    }

    func markWarmLibraryProjectionReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryProjectionNanoseconds == nil
        else { return }
        warmLibraryProjectionNanoseconds = now()
    }

    func beginSearch(query: String) {
        guard let configuration, configuration.metric == .indexedSearch else { return }
        guard query == configuration.expectedQuery else {
            searchStartNanoseconds = nil
            searchDispatchNanoseconds = nil
            searchIsArmed = true
            return
        }
        guard searchIsArmed else { return }
        searchIsArmed = false
        searchStartNanoseconds = now()
        searchDispatchNanoseconds = nil
    }

    func markSearchDispatched(query: String) {
        guard let configuration,
            configuration.metric == .indexedSearch,
            query == configuration.expectedQuery,
            searchStartNanoseconds != nil,
            searchDispatchNanoseconds == nil
        else { return }
        searchDispatchNanoseconds = now()
    }

    func markSearchResultsReady(query: String, resultCount: Int) {
        guard let configuration,
            configuration.metric == .indexedSearch,
            query == configuration.expectedQuery,
            configuration.expectedCount.map({ $0 == resultCount }) ?? true,
            let start = searchStartNanoseconds
        else { return }
        let ready = now()
        var phases: [String: Double] = [:]
        if let dispatch = searchDispatchNanoseconds,
            dispatch >= start, ready >= dispatch
        {
            phases["search_input_to_dispatch_duration_ms"] = milliseconds(dispatch - start)
            phases["search_dispatch_to_ready_duration_ms"] = milliseconds(ready - dispatch)
        }
        record(
            startNanoseconds: start,
            observedCount: resultCount,
            completedNanoseconds: ready,
            phaseDurations: phases
        )
    }

    func beginReadActivation(documentID: String) {
        guard let configuration,
            configuration.metric == .warmReadActivation
                || configuration.metric == .firstReadActivation
        else { return }
        guard documentID == configuration.expectedDocument else {
            readStartNanoseconds = nil
            readIsArmed = true
            return
        }
        guard readIsArmed else { return }
        readIsArmed = false
        readStartNanoseconds = now()
    }

    func markFirstReadDocumentSelected(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadDocumentSelectedNanoseconds == nil
        else { return }
        firstReadDocumentSelectedNanoseconds = now()
    }

    func markReadTaskStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadTaskStartedNanoseconds == nil
        else { return }
        firstReadTaskStartedNanoseconds = now()
    }

    func markReadHTMLReady(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadHTMLReadyNanoseconds == nil
        else { return }
        firstReadHTMLReadyNanoseconds = now()
    }

    func markReadNavigationStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadNavigationStartedNanoseconds == nil
        else { return }
        firstReadNavigationStartedNanoseconds = now()
    }

    func markReadNavigationFinished(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadNavigationFinishedNanoseconds == nil
        else { return }
        firstReadNavigationFinishedNanoseconds = now()
    }

    func markReadReady(documentID: String) {
        guard let configuration,
            documentID == configuration.expectedDocument
        else { return }
        switch configuration.metric {
        case .warmReadActivation:
            guard let start = readStartNanoseconds else { return }
            record(startNanoseconds: start, observedCount: nil)
        case .firstReadActivation:
            guard let start = readStartNanoseconds else { return }
            let completed = now()
            let phases = firstReadPhaseDurations(
                startNanoseconds: start,
                completedNanoseconds: completed
            )
            record(
                startNanoseconds: start,
                observedCount: nil,
                completedNanoseconds: completed,
                phaseDurations: phases
            )
        default:
            return
        }
    }

    func beginEditorModeTransition(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else {
            editorModeTransition = nil
            return
        }
        editorModeTransition = (
            documentID: documentID,
            mode: mode,
            startNanoseconds: now(),
            bridgeStartedNanoseconds: nil,
            acknowledgedNanoseconds: nil
        )
    }

    func markEditorModeBridgeStarted(mode: MarkdownEditorMode) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            var transition = editorModeTransition,
            transition.mode == mode,
            transition.bridgeStartedNanoseconds == nil
        else { return }
        transition.bridgeStartedNanoseconds = now()
        editorModeTransition = transition
    }

    func markEditorModeAcknowledged(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            documentID == configuration.expectedDocument,
            var transition = editorModeTransition,
            transition.documentID == documentID,
            transition.mode == mode,
            transition.acknowledgedNanoseconds == nil
        else { return }
        transition.acknowledgedNanoseconds = now()
        editorModeTransition = transition
    }

    /// Completes only after the acknowledged editor mode has crossed the
    /// native layout boundary that exposes it to accessibility. The bridge
    /// acknowledgment alone is intentionally not a visible-latency endpoint.
    func markEditorModeVisible(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            documentID == configuration.expectedDocument,
            let transition = editorModeTransition,
            transition.documentID == documentID,
            transition.mode == mode,
            let bridgeStarted = transition.bridgeStartedNanoseconds,
            let acknowledged = transition.acknowledgedNanoseconds
        else { return }
        let completed = now()
        guard bridgeStarted >= transition.startNanoseconds,
            acknowledged >= bridgeStarted,
            completed >= acknowledged
        else { return }
        editorModeTransition = nil
        record(
            startNanoseconds: transition.startNanoseconds,
            observedCount: nil,
            observedMode: mode == .livePreview ? "live_preview" : "source",
            completedNanoseconds: completed,
            phaseDurations: [
                "acknowledged_duration_ms": Double(
                    acknowledged - transition.startNanoseconds
                ) / 1_000_000,
                "bridge_started_duration_ms": Double(
                    bridgeStarted - transition.startNanoseconds
                ) / 1_000_000,
                "bridge_roundtrip_duration_ms": Double(
                    acknowledged - bridgeStarted
                ) / 1_000_000,
                "layout_duration_ms": Double(completed - acknowledged) / 1_000_000,
            ]
        )
    }

    func recordEditorKeyToPaint(
        documentID: String,
        durationMilliseconds: Double
    ) {
        guard let configuration,
            configuration.metric == .editorKeyToPaint,
            documentID == configuration.expectedDocument,
            durationMilliseconds.isFinite,
            durationMilliseconds > 0,
            durationMilliseconds < 600_000,
            recordedSampleCount < configuration.sampleCount
        else { return }
        let completed = now()
        let object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": durationMilliseconds,
            "completed_uptime_ns": completed,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    func recordEditorWebDuration(
        documentID: String,
        metric: Metric,
        durationMilliseconds: Double
    ) {
        guard let configuration,
            configuration.metric == metric,
            metric == .editorVisibleProjection,
            documentID == configuration.expectedDocument,
            durationMilliseconds.isFinite,
            durationMilliseconds > 0,
            durationMilliseconds < 600_000,
            recordedSampleCount < configuration.sampleCount
        else { return }
        let completed = now()
        let object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": durationMilliseconds,
            "completed_uptime_ns": completed,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    func beginEditorCachedPreview(documentID: String) {
        guard let configuration,
            configuration.metric == .editorCachedPreview,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else { return }
        cachedPreviewStart = (documentID, now())
    }

    func markEditorCachedPreviewVisible(documentID: String) {
        guard let configuration,
            configuration.metric == .editorCachedPreview,
            documentID == configuration.expectedDocument,
            let start = cachedPreviewStart,
            start.documentID == documentID
        else { return }
        cachedPreviewStart = nil
        record(startNanoseconds: start.nanoseconds, observedCount: nil)
    }

    func beginEditActivation(documentID: String) {
        guard let configuration,
            configuration.metric == .warmEditActivation
                || configuration.metric == .firstEditActivation,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else {
            editActivation = nil
            return
        }
        editActivation = (documentID, now(), nil, nil, nil, nil)
    }

    func markEditActivationAttached(documentID: String, reusedPage: Bool) {
        guard measuresExpectedEditActivation(documentID),
            let activation = editActivation, activation.attachedNanoseconds == nil
        else { return }
        let timestamp = now()
        guard timestamp >= activation.startNanoseconds else { return }
        editActivation?.attachedNanoseconds = timestamp
        editActivation?.reusedPage = reusedPage
    }

    func markEditActivationRendererReady(documentID: String) {
        guard measuresExpectedEditActivation(documentID),
            let activation = editActivation, let attached = activation.attachedNanoseconds,
            activation.rendererReadyNanoseconds == nil, activation.loadedObservedNanoseconds == nil
        else { return }
        let timestamp = now()
        guard timestamp >= attached else { return }
        editActivation?.rendererReadyNanoseconds = timestamp
    }

    func markEditActivationLoaded(documentID: String) {
        guard measuresExpectedEditActivation(documentID),
            let activation = editActivation, let attached = activation.attachedNanoseconds,
            activation.loadedObservedNanoseconds == nil
        else { return }
        let timestamp = now()
        guard timestamp >= (activation.rendererReadyNanoseconds ?? attached) else { return }
        editActivation?.loadedObservedNanoseconds = timestamp
    }

    func markEditorVisible(documentID: String) {
        guard let configuration,
            documentID == configuration.expectedDocument
        else { return }
        switch configuration.metric {
        case .warmEditActivation, .firstEditActivation:
            guard let activation = editActivation,
                activation.documentID == documentID
            else { return }
            editActivation = nil
            let completed = now()
            var phases: [String: Double] = [:]
            if let attached = activation.attachedNanoseconds, attached <= completed {
                phases["request_to_attached_duration_ms"] = milliseconds(
                    attached - activation.startNanoseconds)
            }
            if let attached = activation.attachedNanoseconds,
                let ready = activation.rendererReadyNanoseconds, ready <= completed
            {
                phases["attached_to_renderer_ready_duration_ms"] = milliseconds(ready - attached)
            }
            if let ready = activation.rendererReadyNanoseconds,
                let loaded = activation.loadedObservedNanoseconds, loaded <= completed
            {
                phases["renderer_ready_to_loaded_observed_duration_ms"] = milliseconds(loaded - ready)
            }
            if let loaded = activation.loadedObservedNanoseconds, loaded <= completed {
                phases["loaded_observed_to_visible_duration_ms"] = milliseconds(completed - loaded)
            }
            record(
                startNanoseconds: activation.startNanoseconds, observedCount: nil,
                completedNanoseconds: completed, phaseDurations: phases,
                poolReusedPage: activation.reusedPage
            )
        default:
            return
        }
    }

    func markLibraryReady(noteCount: Int) {
        guard let configuration,
            configuration.metric == .warmLibraryLaunch,
            configuration.expectedCount.map({ $0 == noteCount }) ?? true,
            let start = configuration.externalStartNanoseconds
        else { return }
        let completed = now()
        record(
            startNanoseconds: start,
            observedCount: noteCount,
            completedNanoseconds: completed,
            phaseDurations: launchPhaseDurations(
                startNanoseconds: start,
                completedNanoseconds: completed
            )
        )
    }

    /// Publishes the retained Editor handshake only after the WebKit bridge
    /// has acknowledged the requested mode. The UI-test driver can read the
    /// sampler acknowledgment, but it deliberately cannot write into the app
    /// container that owns this probe file.
    func markEditorModeReady(documentID: String, mode: MarkdownEditorMode) {
        guard let configuration,
            configuration.metric == .editorRetainedMemory,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else { return }
        let expectedMode: MarkdownEditorMode =
            recordedSampleCount.isMultiple(of: 2)
            ? .livePreview
            : .source
        guard mode == expectedMode else { return }
        let object: [String: Any] = [
            "sample": configuration.firstSample + recordedSampleCount,
            "transition": configuration.firstSample + recordedSampleCount,
            "mode": mode == .livePreview ? "live_preview" : "source",
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    /// Persists the packaged CJK journey's final privacy-safe handshake only
    /// after the driver has restored the exact source and requested this
    /// record. The performance driver owns the isolated destination.
    func recordLargeCJKCorrectness(documentID: String, source: String) {
        guard let configuration,
            configuration.metric == .editorLargeCJKCorrectness,
            documentID == configuration.expectedDocument,
            recordedSampleCount == 0
        else { return }
        let characterCount = source.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x4E00...0x9FFF).contains(scalar.value) { count += 1 }
        }
        guard characterCount == 100_000 else { return }
        let object: [String: Any] = [
            "schema": "scholium-cjk-correctness-v1",
            "run_id": configuration.runID,
            "character_count": characterCount,
            "beginning_edit_undo": true,
            "middle_edit_undo": true,
            "end_edit_save": true,
            "mode_switching": true,
            "exact_source_restored": true,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount = 1
    }

    private func record(
        startNanoseconds: UInt64,
        observedCount: Int?,
        observedMode: String? = nil,
        completedNanoseconds: UInt64? = nil,
        phaseDurations: [String: Double] = [:],
        poolReusedPage: Bool? = nil
    ) {
        guard let configuration,
            recordedSampleCount < configuration.sampleCount
        else { return }
        let end = completedNanoseconds ?? now()
        guard end >= startNanoseconds else { return }
        let elapsed = end - startNanoseconds
        guard elapsed < 600_000_000_000 else { return }
        var object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": Double(elapsed) / 1_000_000,
            "completed_uptime_ns": end,
        ]
        if let observedCount { object["observed_count"] = observedCount }
        if let observedMode { object["observed_mode"] = observedMode }
        if let poolReusedPage { object["pool_reused_page"] = poolReusedPage }
        object.merge(phaseDurations) { _, phaseDuration in phaseDuration }
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
        searchStartNanoseconds = nil
        searchDispatchNanoseconds = nil
        readStartNanoseconds = nil
    }

    private func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    private func noteOpeningDurations(_ opening: NoteOpening, completed: UInt64) -> [String: Double] {
        var durations: [String: Double] = ["source_reused": opening.sourceReusedAt == nil ? 0 : 1]
        if let sourceReusedAt = opening.sourceReusedAt, sourceReusedAt <= completed {
            durations["source_reused_since_click_ms"] = milliseconds(sourceReusedAt - opening.started)
        }
        var previousName = "click"
        var previous: UInt64? = opening.started
        for phase in NoteOpeningPhase.allCases.dropLast(2) {
            let timestamp = opening.phases[phase]
            if let previous, let timestamp, timestamp >= previous, timestamp <= completed {
                durations["\(previousName)_to_\(phase.rawValue)_duration_ms"] = milliseconds(
                    timestamp - previous)
            }
            previous = timestamp
            previousName = phase.rawValue
        }
        if let loaded = opening.phases[.loaded], loaded <= completed {
            let endpoint = configuration?.metric == .noteOpenToVisible ? "visible" : "input_ready"
            durations["loaded_to_\(endpoint)_duration_ms"] = milliseconds(completed - loaded)
            for phase in [NoteOpeningPhase.stableVisible, .focused] {
                if let timestamp = opening.phases[phase], timestamp >= loaded {
                    durations["loaded_to_\(phase.rawValue)_duration_ms"] = milliseconds(timestamp - loaded)
                }
            }
        }
        for (operation, bridge) in opening.bridges {
            durations["\(operation.rawValue)_bridge_dispatch_to_return_duration_ms"] = milliseconds(
                bridge.returned)
            durations["\(operation.rawValue)_bridge_return_to_validated_duration_ms"] = milliseconds(
                bridge.validated)
            durations["\(operation.rawValue)_bridge_duration_ms"] =
                milliseconds(bridge.returned) + milliseconds(bridge.validated)
            durations["\(operation.rawValue)_bridge_count"] = Double(bridge.count)
        }
        for (milestone, timestamp) in opening.milestones where timestamp <= completed {
            durations["\(milestone.rawValue)_since_click_ms"] = milliseconds(timestamp - opening.started)
        }
        for (work, value) in opening.work {
            durations["\(work.rawValue)_work_total_ms"] = milliseconds(value.total)
            durations["\(work.rawValue)_work_max_ms"] = milliseconds(value.maximum)
            durations["\(work.rawValue)_work_count"] = Double(value.count)
        }
        return durations
    }

    private func measuresExpectedFirstRead(_ documentID: String) -> Bool {
        configuration?.metric == .firstReadActivation
            && configuration?.expectedDocument == documentID
    }

    private func measuresExpectedEditActivation(_ documentID: String) -> Bool {
        guard let configuration,
            configuration.metric == .warmEditActivation || configuration.metric == .firstEditActivation,
            configuration.expectedDocument == documentID,
            recordedSampleCount < configuration.sampleCount
        else { return false }
        return editActivation?.documentID == documentID
    }

    private func launchPhaseDurations(
        startNanoseconds: UInt64,
        completedNanoseconds: UInt64
    ) -> [String: Double] {
        guard let windowModelInitialization = warmLibraryWindowModelInitializationNanoseconds,
            let workspaceReady = warmLibraryWorkspaceReadyNanoseconds,
            let projection = warmLibraryProjectionNanoseconds,
            windowModelInitialization >= startNanoseconds,
            workspaceReady >= windowModelInitialization,
            projection >= workspaceReady,
            completedNanoseconds >= projection
        else { return [:] }
        var phases = [
            "process_to_window_model_init_duration_ms": milliseconds(
                windowModelInitialization - startNanoseconds
            ),
            "window_model_init_to_workspace_ready_duration_ms": milliseconds(
                workspaceReady - windowModelInitialization
            ),
            "workspace_ready_to_projection_duration_ms": milliseconds(
                projection - workspaceReady
            ),
            "projection_to_layout_duration_ms": milliseconds(
                completedNanoseconds - projection
            ),
        ]
        if let actualStartupSafetyReady = startupSafetyReadyNanoseconds,
            let vaultConfigurationReady = vaultConfigurationReadyNanoseconds,
            actualStartupSafetyReady >= windowModelInitialization,
            actualStartupSafetyReady <= projection,
            vaultConfigurationReady >= max(actualStartupSafetyReady, workspaceReady),
            projection >= vaultConfigurationReady
        {
            // Restoring an existing Triptych completes safety work before
            // workspace adoption. In that path it contributes zero time to
            // the workspace-ready-to-projection interval.
            let startupSafetyReady = max(actualStartupSafetyReady, workspaceReady)
            phases["workspace_ready_to_startup_safety_ready_duration_ms"] =
                milliseconds(startupSafetyReady - workspaceReady)
            phases["startup_safety_ready_to_vault_configuration_ready_duration_ms"] =
                milliseconds(vaultConfigurationReady - startupSafetyReady)
            phases["vault_configuration_ready_to_projection_duration_ms"] =
                milliseconds(projection - vaultConfigurationReady)
        }
        return phases
    }

    private func firstReadPhaseDurations(
        startNanoseconds: UInt64,
        completedNanoseconds: UInt64
    ) -> [String: Double] {
        guard let documentSelected = firstReadDocumentSelectedNanoseconds,
            let readTaskStarted = firstReadTaskStartedNanoseconds,
            let htmlReady = firstReadHTMLReadyNanoseconds,
            let navigationStarted = firstReadNavigationStartedNanoseconds,
            let navigationFinished = firstReadNavigationFinishedNanoseconds,
            documentSelected >= startNanoseconds,
            readTaskStarted >= documentSelected,
            htmlReady >= readTaskStarted,
            navigationStarted >= htmlReady,
            navigationFinished >= navigationStarted,
            completedNanoseconds >= navigationFinished
        else { return [:] }
        return [
            "activation_to_document_selection_duration_ms": milliseconds(
                documentSelected - startNanoseconds
            ),
            "document_selection_to_read_task_start_duration_ms": milliseconds(
                readTaskStarted - documentSelected
            ),
            "read_task_start_to_html_ready_duration_ms": milliseconds(
                htmlReady - readTaskStarted
            ),
            "read_html_ready_to_navigation_start_duration_ms": milliseconds(
                navigationStarted - htmlReady
            ),
            "read_navigation_duration_ms": milliseconds(
                navigationFinished - navigationStarted
            ),
            "read_navigation_to_ready_duration_ms": milliseconds(
                completedNanoseconds - navigationFinished
            ),
        ]
    }

    private func append(_ object: [String: Any], to resultURL: URL) -> Bool {
        guard
            let encoded = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        else { return false }
        do {
            if !FileManager.default.fileExists(atPath: resultURL.path) {
                guard FileManager.default.createFile(atPath: resultURL.path, contents: nil) else {
                    return false
                }
            }
            let values = try resultURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return false }
            let handle = try FileHandle(forWritingTo: resultURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded + Data([0x0A]))
            try handle.close()
            return true
        } catch {
            // Performance evidence is optional and must never affect product
            // behavior or expose a research path through user-facing errors.
            return false
        }
    }

    private static func safeResultURL(
        _ rawPath: String,
        runID: String,
        bundleID: String,
        isolatedHomePath: String?
    ) -> URL? {
        guard bundleID == "com.scholium.app" || bundleID == "com.scholium.qa" else {
            return nil
        }
        let candidate = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard candidate.pathExtension == "jsonl",
            candidate.lastPathComponent == (rawPath as NSString).lastPathComponent
        else {
            return nil
        }
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let isolatedSuffix = "/.build/performance-\(runID)/app-state/raw"
        let isSystemTemporary =
            bundleID == "com.scholium.qa"
            && (parent.path == "/tmp"
                || parent.path.hasPrefix("/tmp/")
                || parent.path == "/private/tmp"
                || parent.path.hasPrefix("/private/tmp/"))
        let isolatedRaw = parent.path.components(separatedBy: isolatedSuffix).first.map {
            $0 + isolatedSuffix
        }
        let isIsolatedBuildOutput =
            bundleID == "com.scholium.qa"
            && parent.path.hasPrefix("/Users/")
            && isolatedRaw.map {
                parent.path == $0 || parent.path.hasPrefix($0 + "/")
            } == true
        let packagedRunRoot = isolatedHomePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
        }
        let packagedRawRoot = packagedRunRoot?.appendingPathComponent(
            "raw",
            isDirectory: true
        )
        let isPackagedOutput =
            bundleID == "com.scholium.app"
            && packagedRunRoot?.lastPathComponent == runID
            && packagedRunRoot?.deletingLastPathComponent().lastPathComponent
                == "Performance Runs"
            && packagedRawRoot.map {
                parent.path == $0.path || parent.path.hasPrefix($0.path + "/")
            } == true
        guard isSystemTemporary || isIsolatedBuildOutput || isPackagedOutput else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return parent.appendingPathComponent(candidate.lastPathComponent, isDirectory: false)
    }

    #if DEBUG
        private static func safeQAMemoryOwnerResultURL(
            environment: [String: String],
            arguments: [String],
            bundleID: String?,
            bundleURL: URL
        ) -> URL? {
            guard bundleID == ScholiumRuntimeIsolation.qaBundleIdentifier,
                environment["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] == "1",
                let home = ScholiumRuntimeIsolation.homeURL(
                    environment: environment,
                    arguments: arguments,
                    bundleIdentifier: bundleID
                ),
                let fixture = ScholiumRuntimeIsolation.fixtureRootURL(
                    environment: environment,
                    arguments: arguments,
                    bundleIdentifier: bundleID,
                    isDebugBuild: true
                )
            else { return nil }

            // Accept only a QA bundle, home and fixture under the same checkout's
            // ignored build root. In particular, never export into a vault or the
            // researcher's ordinary application home.
            let bundlePath = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard let buildRange = bundlePath.range(of: "/.build/") else { return nil }
            let buildRoot = String(bundlePath[..<buildRange.upperBound])
            let homeURL = home.standardizedFileURL.resolvingSymlinksInPath()
            let fixtureURL = fixture.standardizedFileURL.resolvingSymlinksInPath()
            guard homeURL.path.hasPrefix(buildRoot),
                fixtureURL.path.hasPrefix(buildRoot),
                homeURL != fixtureURL,
                !homeURL.path.hasPrefix(fixtureURL.path + "/"),
                !fixtureURL.path.hasPrefix(homeURL.path + "/")
            else { return nil }
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: homeURL.path, isDirectory: &isDirectory
                ), isDirectory.boolValue
            else { return nil }
            return homeURL.appendingPathComponent(qaMemoryOwnerFilename)
        }
    #endif

    private static func allowsConfiguration(
        environment: [String: String],
        bundleID: String,
        arguments: [String]
    ) -> Bool {
        bundleID == "com.scholium.qa"
            || ScholiumRuntimeIsolation.allowsPackagedPerformanceIsolation(
                environment: environment,
                arguments: arguments,
                bundleIdentifier: bundleID
            )
    }

    private static func isSafeRunID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
    }
}
