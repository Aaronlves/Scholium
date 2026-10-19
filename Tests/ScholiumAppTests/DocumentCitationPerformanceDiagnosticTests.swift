import AppKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

#if DEBUG
    /// Opt-in real WebKit diagnostic, run alone. DOM editing commands exercise
    /// CodeMirror input rather than OS keyboard/IME delivery. Measures native
    /// source/selection admission; animation frames and visible paint are excluded.
    @Suite("Document citation input diagnostics", .serialized)
    @MainActor
    struct DocumentCitationPerformanceDiagnosticTests {
        private typealias Harness = MarkdownEditorWebViewIntegrationTests.EditorHarness

        @Test(
            "Ordinary input away from managed citations preserves the exact source and companion",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_CITATIONS"] == "1"))
        func ordinaryInputWithManagedCitations() async throws {
            let environment = ProcessInfo.processInfo.environment
            let requestedBytes = try #require(
                Int(environment["SCHOLIUM_CITATION_SOURCE_BYTES"] ?? "131072"))
            try #require(
                [128 * 1_024, 1_024 * 1_024].contains(requestedBytes),
                "Choose 131072 or 1048576 source bytes.")
            let citationCount = try #require(Int(environment["SCHOLIUM_CITATION_COUNT"] ?? "100"))
            try #require([1, 100].contains(citationCount), "Choose 1 or 100 managed citations.")
            let requestedMode = environment["SCHOLIUM_CITATION_MODE"] ?? "edit"
            try #require(["edit", "source"].contains(requestedMode), "Choose edit or source.")
            let mode: MarkdownEditorMode = requestedMode == "edit" ? .livePreview : .source
            let activate = environment["SCHOLIUM_CITATION_ACTIVATE"] == "1"
            let priorActivationPolicy: NSApplication.ActivationPolicy?
            if activate {
                _ = NSApplication.shared
                priorActivationPolicy = NSApp.activationPolicy()
                NSApp.setActivationPolicy(.regular)
            } else {
                priorActivationPolicy = nil
            }
            defer {
                if let priorActivationPolicy { NSApp.setActivationPolicy(priorActivationPolicy) }
            }
            let fixture = try Fixture(requestedBytes: requestedBytes, citationCount: citationCount)
            let harness = Harness(
                source: fixture.source, citationSnapshot: fixture.snapshot, initialMode: mode)
            defer { harness.close() }
            do {
                try await harness.waitUntilReady()
                if activate {
                    harness.activateForWritingTesting()
                    try await harness.session.focusAndWait()
                    try await harness.waitUntilFocused()
                    try await waitForForeground(harness)
                }
                try await prepareCompleteCitationContext(harness, fixture: fixture)
                try await reportSetupState(harness, mode: requestedMode, activated: activate)
                try await measureInputs(
                    harness, fixture: fixture, mode: requestedMode, requestedBytes: requestedBytes)
                await harness.closeAndDrain()
            } catch {
                await harness.closeAndDrain()
                throw error
            }
        }

        private func waitForForeground(_ harness: Harness) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while try await harness.callPageJavaScript(
                "return document.visibilityState === 'visible' && document.hasFocus();") as? Bool != true
            {
                guard ContinuousClock.now < deadline else {
                    Issue.record("The synthetic editor window did not become visible and focused.")
                    throw DiagnosticError.foregroundUnavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        private func reportSetupState(_ harness: Harness, mode: String, activated: Bool) async throws {
            let raw = try await harness.callPageJavaScript(
                """
                return JSON.stringify({
                    visibilityState: document.visibilityState,
                    documentHasFocus: document.hasFocus(),
                    editorOwnsFocus: document.activeElement === document.querySelector('.cm-content')
                });
                """
            )
            let json = try #require(raw as? String)
            let state = try JSONDecoder().decode(SetupState.self, from: Data(json.utf8))
            if activated {
                try #require(state.visibilityState == "visible" && state.documentHasFocus && state.editorOwnsFocus)
            }
            try report([
                "schema": "scholium-citation-input-diagnostic-v1", "phase": "setup", "mode": mode,
                "requested_activation": activated, "visibility_state": state.visibilityState,
                "document_has_focus": state.documentHasFocus, "editor_owns_focus": state.editorOwnsFocus,
            ])
        }

        private func prepareCompleteCitationContext(_ harness: Harness, fixture: Fixture) async throws {
            let webView = try #require(harness.session.webView)
            // A leading viewport alone does not prove parser completion. Visit the
            // final citation and require its parser-owned Link context before any
            // input sample. Returning to the leading paragraph preserves that tree.
            let finalHead = try #require(
                EditorSourceOffsetMap(source: fixture.source).editorUTF16Offset(
                    forSourceUTF16Offset: fixture.lastCitationHead))
            _ = try await harness.session.send(
                .revealSourceRange(fromUTF16: finalHead, toUTF16: finalHead), in: webView)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while true {
                // A query may finish ParseContext without publishing LanguageState.
                // Dispatch the existing source-neutral refresh so this setup does
                // not depend on background frames to publish the completed tree.
                _ = try await harness.session.send(.measureVisibleProjection, in: webView)
                let reply = try await harness.session.send(.queryContext, in: webView)
                if let context = reply.context,
                    context.activeInlineConstructs.contains("Link"), context.citationState == .stale,
                    context.availableCommands.contains(.refreshCitations)
                {
                    break
                }
                if ContinuousClock.now >= deadline {
                    try report([
                        "phase": "setup-failure", "expected_head": finalHead,
                        "actual_head": reply.context?.selections.first?.head ?? -1,
                        "inline_constructs": reply.context?.activeInlineConstructs ?? [],
                        "citation_state": reply.context?.citationState?.rawValue ?? "missing",
                        "can_refresh": reply.context?.availableCommands.contains(.refreshCitations) ?? false,
                    ])
                    throw DiagnosticError.incompleteParser
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            harness.session.revealSourceRange(
                fromUTF16: fixture.insertionHead, toUTF16: fixture.insertionHead)
            let editorHead = try #require(
                EditorSourceOffsetMap(source: fixture.source).editorUTF16Offset(
                    forSourceUTF16Offset: fixture.insertionHead))
            try await harness.waitUntilSelection(anchor: editorHead, head: editorHead)
            try await harness.waitUntilFocused()
            _ = try await harness.callPageJavaScript("await document.fonts.ready;")
            let context = try #require(try await harness.session.send(.queryContext, in: webView).context)
            try #require(
                context.citationState == .stale && context.availableCommands.contains(.refreshCitations))
            try #require(context.undoLabel == nil)
            try await verifyPair(harness, source: fixture.source, fixture: fixture)
        }

        private func measureInputs(
            _ harness: Harness, fixture: Fixture, mode: String, requestedBytes: Int
        ) async throws {
            let webView = try #require(harness.session.webView)
            let coordinator = try #require(webView.navigationDelegate as? MarkdownEditorWebView.Coordinator)
            let nativeStages = NativeInputStageRecorder()
            coordinator.testingInputMessageObserver = { [weak nativeStages] timing in
                nativeStages?.append(timing)
            }
            harness.session.testingEditorChangeObserver = { [weak nativeStages] timing in
                nativeStages?.append(timing)
            }
            harness.session.testingImageRefreshObserver = { [weak nativeStages] timing in
                nativeStages?.append(timing)
            }
            defer {
                coordinator.testingInputMessageObserver = nil
                harness.session.testingEditorChangeObserver = nil
                harness.session.testingImageRefreshObserver = nil
            }
            let initialEditorHead = try #require(
                EditorSourceOffsetMap(source: fixture.source).editorUTF16Offset(
                    forSourceUTF16Offset: fixture.insertionHead))
            let sampleCount = 6
            var previousInputStartedAt: ContinuousClock.Instant?
            for sample in 0..<sampleCount {
                let expected = fixture.insertingCharacters(sample + 1)
                let expectedHead = initialEditorHead + sample + 1
                let beforeGeneration = harness.session.generation
                let nativeStart = ContinuousClock.now
                let raw = try await harness.callPageJavaScript(
                    """
                    const content = document.querySelector('.cm-content');
                    if (!content || document.activeElement !== content) throw new Error('The editor does not own DOM input');
                    let inputEvents = 0;
                    const onInput = () => inputEvents++;
                    content.addEventListener('input', onInput, true);
                    try {
                        const began = performance.now();
                        if (!document.execCommand('insertText', false, 'x')) throw new Error('DOM insertion was rejected');
                        const dispatchMilliseconds = performance.now() - began;
                        return JSON.stringify({beganAtMilliseconds: began, dispatchMilliseconds, inputEvents});
                    } finally {
                        content.removeEventListener('input', onInput, true);
                    }
                    """
                )
                let nativeDOMReturned = ContinuousClock.now
                let json = try #require(raw as? String)
                let dom = try JSONDecoder().decode(DOMMeasurement.self, from: Data(json.utf8))
                try #require(dom.inputEvents > 0, "The DOM command must produce a real WebKit input event.")
                try #require(dom.dispatchMilliseconds.isFinite)
                try #require(dom.beganAtMilliseconds.isFinite)

                // Observe ordinary incoming source/context messages before issuing
                // a typed query that could otherwise force synchronization itself.
                let ownerDeadline = ContinuousClock.now.advanced(by: .seconds(10))
                let expectedSelection = [
                    MarkdownEditorSelectionRange(anchor: expectedHead, head: expectedHead)
                ]
                while harness.session.generation <= beforeGeneration
                    || harness.session.context?.selections != expectedSelection
                    || !nativeStages.hasAcceptedStages(generation: beforeGeneration + 1, since: nativeStart)
                {
                    try #require(
                        ContinuousClock.now < ownerDeadline,
                        "The ordinary input did not reach the native source/selection owner.")
                    try await Task.sleep(for: .milliseconds(1))
                }
                let ownerAdmitted = ContinuousClock.now
                // Capture only ordinary notifications already admitted at this point.
                // Later typed queries and exact-source oracles cannot supply this proof.
                let admittedStages = try nativeStages.acceptedStages(
                    generation: harness.session.generation, since: nativeStart)
                let scrollStages = nativeStages.scrollStages(from: nativeStart, through: ownerAdmitted)
                let editorChangeTiming = try nativeStages.acceptedEditorChangeTiming(
                    generation: harness.session.generation, since: nativeStart)
                let imageRefreshTimings = nativeStages.imageRefreshTimings(from: previousInputStartedAt ?? nativeStart, through: ownerAdmitted)
                previousInputStartedAt = nativeStart
                let contextStart = ContinuousClock.now
                let reply = try await harness.session.send(.queryContext, in: webView)
                let contextMilliseconds = milliseconds(contextStart.duration(to: .now))
                let context = try #require(reply.context)
                try #require(context.selections == expectedSelection)
                try #require(context.citationState == .stale && context.undoLabel != nil)
                try #require(harness.session.isDirty)
                // Full-source transfer and byte/opaque-companion oracles are outside
                // every measured boundary. They are not ordinary typing work.
                try await verifyPair(harness, source: expected, fixture: fixture)
                try report([
                    "schema": "scholium-citation-input-diagnostic-v1",
                    "phase": sample == 0 ? "first-input" : "warm-input", "sample": sample,
                    "generation": beforeGeneration + 1, "js_input_began_ms": dom.beganAtMilliseconds,
                    "mode": mode, "requested_source_utf8_bytes": requestedBytes,
                    "source_utf8_bytes": fixture.source.utf8.count, "citations": fixture.data.fields.count,
                    "dom_dispatch_ms": dom.dispatchMilliseconds,
                    "native_dom_request_ms": milliseconds(nativeStart.duration(to: nativeDOMReturned)),
                    "native_input_to_owner_ms": milliseconds(nativeStart.duration(to: ownerAdmitted)),
                    "owner_wait_after_dom_return_ms": milliseconds(
                        nativeDOMReturned.duration(to: ownerAdmitted)),
                    "typed_context_request_ms": contextMilliseconds, "input_events": dom.inputEvents,
                    "oracle": "pass",
                ])
                try reportNativeStages(admittedStages, sample: sample, mode: mode, inputStartedAt: nativeStart)
                try reportNativeStages(
                    scrollStages, sample: sample, mode: mode, inputStartedAt: nativeStart,
                    phase: "native-scroll-stages")
                try reportEditorChangeTiming(editorChangeTiming, sample: sample, mode: mode, inputStartedAt: nativeStart)
                try reportImageRefreshTimings(imageRefreshTimings, sample: sample, mode: mode, inputStartedAt: nativeStart)
                if ProcessInfo.processInfo.environment["SCHOLIUM_CITATION_INPUT_PHASES"] == "1" {
                    let samples = try await harness.session.queryPerformanceSamples()
                    try report([
                        "phase": "web-phases", "sample": sample,
                        "samples": samples.suffix(48).map {
                            ["name": $0.name, "milliseconds": $0.durationMilliseconds, "observed": $0.observed]
                        },
                    ])
                }
            }

            // Real typing can form one or several history groups. Undo the actual
            // groups until the original source returns, rather than asserting that
            // six DOM commands must create six independent history events.
            var current = fixture.insertingCharacters(sampleCount)
            var undoGroups = 0
            while !current.utf8.elementsEqual(fixture.source.utf8), undoGroups < sampleCount {
                let previousBytes = current.utf8.count
                let handled =
                    try await harness.callPageJavaScript(
                        """
                        const event = new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', keyCode: 90,
                            which: 90, metaKey: true, bubbles: true, cancelable: true});
                        document.querySelector('.cm-content').dispatchEvent(event);
                        return event.defaultPrevented;
                        """
                    ) as? Bool
                try #require(handled == true, "The editor did not handle Undo.")
                current = try await harness.session.currentText(for: harness.documentID)
                undoGroups += 1
                try #require(
                    current.utf8.count < previousBytes, "Undo did not remove an ordinary input group.")
                let remaining = current.utf8.count - fixture.source.utf8.count
                try #require((0..<sampleCount).contains(remaining))
                try #require(current.utf8.elementsEqual(fixture.insertingCharacters(remaining).utf8))
                try await verifyPair(harness, source: current, fixture: fixture)
            }
            try #require(current.utf8.elementsEqual(fixture.source.utf8))
            let restored = try #require(try await harness.session.send(.queryContext, in: webView).context)
            try #require(restored.selections == [.init(anchor: initialEditorHead, head: initialEditorHead)])
            try #require(restored.undoLabel == nil && restored.redoLabel != nil)
            try report([
                "schema": "scholium-citation-input-diagnostic-v1", "phase": "undo-oracle", "mode": mode,
                "source_utf8_bytes": fixture.source.utf8.count, "citations": fixture.data.fields.count,
                "inputs": sampleCount, "undo_groups": undoGroups, "oracle": "pass",
            ])
        }

        private func reportEditorChangeTiming(
            _ timing: MarkdownEditorSession.TestingEditorChangeTiming, sample: Int, mode: String,
            inputStartedAt: ContinuousClock.Instant
        ) throws {
            var values: [String: Any] = [
                "schema": "scholium-citation-input-diagnostic-v1", "phase": "native-editor-change-stages",
                "sample": sample, "mode": mode, "base_generation": timing.baseGeneration,
                "generation": timing.resultingGeneration, "accepted": timing.accepted,
                "start_after_input_ms": milliseconds(inputStartedAt.duration(to: timing.startedAt)),
                "total_ms": milliseconds(timing.startedAt.duration(to: timing.completedAt)),
                "validate_and_map_ms": milliseconds(timing.validationAndMapping),
            ]
            if let duration = timing.bufferApply { values["buffer_apply_ms"] = milliseconds(duration) }
            if let duration = timing.offsetMap { values["offset_map_ms"] = milliseconds(duration) }
            if let duration = timing.publishingAndCallbacks { values["publish_callbacks_ms"] = milliseconds(duration) }
            try report(values)
        }

        private func reportImageRefreshTimings(
            _ timings: [MarkdownEditorSession.TestingImageRefreshTiming], sample: Int, mode: String,
            inputStartedAt: ContinuousClock.Instant
        ) throws {
            let events = timings.map { timing -> [String: Any] in
                var event: [String: Any] = [
                    "generation": timing.generation, "accepted": timing.accepted,
                    "start_after_input_ms": milliseconds(inputStartedAt.duration(to: timing.startedAt)),
                    "completed_after_input_ms": milliseconds(inputStartedAt.duration(to: timing.completedAt)),
                    "total_ms": milliseconds(timing.startedAt.duration(to: timing.completedAt)),
                    "source_capture_ms": milliseconds(timing.sourceCapture),
                ]
                if let duration = timing.containsAndQuery { event["contains_and_query_elapsed_ms"] = milliseconds(duration) }
                if let duration = timing.admissionGuard { event["admission_guard_ms"] = milliseconds(duration) }
                if let duration = timing.publication { event["publication_ms"] = milliseconds(duration) }
                return event
            }
            try report([
                "schema": "scholium-citation-input-diagnostic-v1", "phase": "native-image-refresh-stages",
                "sample": sample, "mode": mode, "events": events,
            ])
        }

        private func reportNativeStages(
            _ stages: [MarkdownEditorWebView.Coordinator.TestingInputMessageTiming], sample: Int,
            mode: String, inputStartedAt: ContinuousClock.Instant, phase: String = "native-stages"
        ) throws {
            let events = stages.map { stage -> [String: Any] in
                var event: [String: Any] = [
                    "kind": stage.kind.rawValue, "generation": stage.documentVersion, "accepted": stage.accepted,
                    "receive_after_input_ms": milliseconds(inputStartedAt.duration(to: stage.receivedAt)),
                    "decode_ms": milliseconds(stage.receivedAt.duration(to: stage.decodedAt)),
                    "after_decode_before_admission_ms": milliseconds(
                        stage.decodedAt.duration(to: stage.admissionStartedAt)),
                    "admission_ms": milliseconds(stage.admissionStartedAt.duration(to: stage.admissionCompletedAt)),
                    "admission_completed_after_input_ms": milliseconds(
                        inputStartedAt.duration(to: stage.admissionCompletedAt)),
                ]
                if let revision = stage.interactionRevision { event["interaction_revision"] = revision }
                return event
            }
            try report([
                "schema": "scholium-citation-input-diagnostic-v1", "phase": phase, "sample": sample,
                "mode": mode, "events": events,
            ])
        }

        private func verifyPair(_ harness: Harness, source: String, fixture: Fixture) async throws {
            let actual = try await harness.session.currentText(for: harness.documentID)
            try #require(actual.utf8.elementsEqual(source.utf8))
            try #require(harness.session.checkedSource.utf8.elementsEqual(source.utf8))
            let companion = try #require(harness.session.checkedCitationData)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try #require(try encoder.encode(companion).elementsEqual(fixture.companionBytes))
            try #require(harness.session.committedCitationSnapshot == fixture.snapshot)
            try #require(
                harness.session.currentCitationSnapshot?.sourceFingerprint
                    == DocumentFingerprint(content: source))
        }

        private func milliseconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
        }

        private func report(_ values: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            print("DOCUMENT_CITATION_INPUT_NATIVE \(String(decoding: bytes, as: UTF8.self))")
        }

        private struct DOMMeasurement: Decodable {
            let beganAtMilliseconds: Double
            let dispatchMilliseconds: Double
            let inputEvents: Int
        }

        private struct SetupState: Decodable {
            let visibilityState: String
            let documentHasFocus: Bool
            let editorOwnsFocus: Bool
        }

        @MainActor
        private final class NativeInputStageRecorder {
            typealias Stage = MarkdownEditorWebView.Coordinator.TestingInputMessageTiming
            typealias EditorChangeTiming = MarkdownEditorSession.TestingEditorChangeTiming
            typealias ImageRefreshTiming = MarkdownEditorSession.TestingImageRefreshTiming
            private let capacity = 128
            private var stages: [Stage] = []
            private var editorChanges: [EditorChangeTiming] = []
            private var imageRefreshes: [ImageRefreshTiming] = []
            private var overflowed = false

            init() {
                stages.reserveCapacity(capacity)
                editorChanges.reserveCapacity(capacity)
                imageRefreshes.reserveCapacity(capacity)
            }

            func append(_ stage: Stage) {
                guard stages.count + editorChanges.count + imageRefreshes.count < capacity else {
                    overflowed = true
                    return
                }
                stages.append(stage)
            }

            func append(_ timing: EditorChangeTiming) {
                guard stages.count + editorChanges.count + imageRefreshes.count < capacity else {
                    overflowed = true
                    return
                }
                editorChanges.append(timing)
            }

            func append(_ timing: ImageRefreshTiming) {
                guard stages.count + editorChanges.count + imageRefreshes.count < capacity else {
                    overflowed = true
                    return
                }
                imageRefreshes.append(timing)
            }

            func imageRefreshTimings(
                from startedAt: ContinuousClock.Instant, through endedAt: ContinuousClock.Instant
            ) -> [ImageRefreshTiming] {
                // Keep complete overlapping intervals, including work admitted for the
                // prior generation. Capture now so later queries cannot add evidence.
                imageRefreshes.filter { $0.startedAt <= endedAt && $0.completedAt >= startedAt }
            }

            func acceptedEditorChangeTiming(
                generation: Int, since inputStartedAt: ContinuousClock.Instant
            ) throws -> EditorChangeTiming {
                try #require(!overflowed, "The bounded native diagnostic recorder overflowed.")
                let candidates = editorChanges.filter {
                    $0.resultingGeneration == generation && $0.startedAt >= inputStartedAt && $0.accepted
                }
                try #require(candidates.count == 1, "Expected one accepted editor change before typed queries.")
                let timing = try #require(candidates.first)
                try #require(timing.bufferApply != nil && timing.offsetMap != nil && timing.publishingAndCallbacks != nil)
                return timing
            }

            func acceptedStages(generation: Int, since inputStartedAt: ContinuousClock.Instant) throws -> [Stage] {
                try #require(!overflowed, "The bounded native diagnostic recorder overflowed.")
                let candidates = stages.filter {
                    $0.documentVersion == generation && $0.receivedAt >= inputStartedAt && $0.accepted
                }
                return try [Stage.Kind.documentChanged, .interactionChanged].map { kind in
                    let stage = try #require(
                        candidates.first { $0.kind == kind },
                        "An ordinary accepted notification was missing before typed queries.")
                    try #require(
                        stage.receivedAt <= stage.decodedAt && stage.decodedAt <= stage.admissionStartedAt
                            && stage.admissionStartedAt <= stage.admissionCompletedAt)
                    return stage
                }
            }

            func hasAcceptedStages(generation: Int, since inputStartedAt: ContinuousClock.Instant) -> Bool {
                // A concurrent presentation reply can publish the new selection
                // before its ordinary coalesced notification. Wait for that
                // notification rather than mistaking reply admission for it.
                [Stage.Kind.documentChanged, .interactionChanged].allSatisfy { kind in
                    stages.contains {
                        $0.kind == kind && $0.documentVersion == generation
                            && $0.receivedAt >= inputStartedAt && $0.accepted
                    }
                }
            }

            func scrollStages(from startedAt: ContinuousClock.Instant, through endedAt: ContinuousClock.Instant) -> [Stage] {
                // A queued scroll from the prior generation may delay the current delta.
                // Keep its generation visible rather than filtering it out of this window.
                stages.filter {
                    $0.kind == .scrollChanged && $0.receivedAt >= startedAt && $0.receivedAt <= endedAt
                }
            }
        }

        private enum DiagnosticError: Error { case incompleteParser, foregroundUnavailable }

        private struct Fixture {
            let source: String
            let insertionHead: Int
            let lastCitationHead: Int
            let data: ZoteroCitationData
            let companionBytes: Data
            let snapshot: ZoteroCitationSnapshot

            init(requestedBytes: Int, citationCount: Int) throws {
                let prefix =
                    "\u{FEFF}---\r\nfixture_only: true\r\nunknown: 'keep' # literal\n---\r\n\r\n# Synthetic input\r\n\r\nOrdinary checkpoint e\u{301} 中文 🧭"
                let bodyStart = " continues in a plain paragraph.\r\n\r\n"
                let paragraph =
                    "Synthetic ordinary prose preserves exact source, selection and opaque citation data. 中文 e\u{301} 🧭.\r\n\r\n"
                let fields = (1...citationCount).map { index in
                    ZoteroCitationFieldData(
                        id: "c-perf-\(index)", kind: .citation,
                        code:
                            "ITEM CSL_CITATION {\"citationItems\":[{\"id\":\(index)}],\"opaque\":\"e\u{301} 中文 🧭\"}",
                        text: "Synthetic Citation \(index)")
                }
                let citations = fields.map { "[\($0.text)](cite:\($0.id))" }.joined(separator: "\r\n\r\n")
                let suffix = "\r\n\r\n" + citations + "\r\nTail without final newline e\u{301} 🧭"
                let fixedBytes = prefix.utf8.count + bodyStart.utf8.count + suffix.utf8.count
                let paragraphs = max(
                    1, (requestedBytes - fixedBytes + paragraph.utf8.count - 1) / paragraph.utf8.count)
                source = prefix + bodyStart + String(repeating: paragraph, count: paragraphs) + suffix
                insertionHead = prefix.utf16.count
                let last = try #require(fields.last)
                let lastRange = try #require(
                    source.range(of: "[\(last.text)](cite:\(last.id))", options: .backwards))
                lastCitationHead = source[..<lastRange.lowerBound].utf16.count + 3
                data = ZoteroCitationData(
                    fields: fields,
                    documentData: "<data>\r\n<prefs><pref name=\"noteType\" value=\"0\"/></prefs></data>",
                    // An explicitly pending signature also verifies that ordinary
                    // typing never accepts or clears the existing refresh state.
                    acceptedFields: [])
                try data.validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                companionBytes = try encoder.encode(data)
                snapshot = ZoteroCitationSnapshot(
                    noteID: UUID(), vaultID: UUID(), revision: DocumentFingerprint(data: companionBytes),
                    sourceFingerprint: DocumentFingerprint(content: source), data: data, status: .available)
            }

            func insertingCharacters(_ count: Int) -> String {
                let insertion = String.Index(utf16Offset: insertionHead, in: source)
                return String(source[..<insertion]) + String(repeating: "x", count: count)
                    + String(source[insertion...])
            }
        }
    }
#endif
