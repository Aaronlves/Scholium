import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    /// Opt-in native feature diagnostics, not a paint or release-performance gate.
    /// The actual feature owns mode admission, clean-buffer flush and finalized
    /// reader readiness. Window navigation, hydration, dirty disk saves, native
    /// focus, visible paint and RSS are outside this hidden-window boundary.
    @MainActor
    @Suite("Native document mode switching diagnostics", .serialized)
    struct DocumentModeSwitchPerformanceDiagnosticTests {
        enum FixtureKind: String, CaseIterable, Sendable {
            case small, large, complex

            static var selected: [Self] {
                guard let value = ProcessInfo.processInfo.environment["SCHOLIUM_MODE_FIXTURE"],
                    let fixture = Self(rawValue: value)
                else { return allCases }
                return [fixture]
            }
        }

        @Test(
            "Measure all six native feature mode transitions with exact clean source",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_MODES"] == "1"),
            arguments: FixtureKind.selected)
        func sixDirectedTransitions(kind: FixtureKind) async throws {
            if let value = ProcessInfo.processInfo.environment["SCHOLIUM_MODE_FIXTURE"] {
                try #require(FixtureKind(rawValue: value) != nil, "SCHOLIUM_MODE_FIXTURE must be small, large or complex.")
            }
            let harness = Harness(kind: kind)
            do {
                try await harness.run()
                await harness.closeAndDrain()
            } catch {
                await harness.closeAndDrain()
                throw error
            }
        }

        private struct FixtureData {
            let kind: FixtureKind
            let source: String
            let viewportRange: NSRange
            let viewportText: String

            init(kind: FixtureKind) {
                self.kind = kind
                let paragraph = "Synthetic paragraph preserves ordinary manuscript layout, 中文, 😀 and e\u{301}; its exact source remains unchanged."
                let viewport = "Diagnostic viewport paragraph preserves a known source-bound position across all three document modes. 中文 😀 e\u{301}."
                let targetBytes = kind == .large ? 524_288 : 4_096
                let count = max(16, targetBytes / (paragraph.utf8.count + 16))
                var paragraphs = (0..<count).map { "\(paragraph) Item \($0)." }
                paragraphs.insert(viewport, at: paragraphs.count / 2)
                var source = "\u{FEFF}# Synthetic mode switching\r\n\r\n" + paragraphs.joined(separator: "\r\n\r\n") + "\r\n"
                if kind == .complex {
                    let constructs = (1...12).map { index in
                        """

                        > [!quote] Synthetic callout \(index)
                        > Source-backed **formatted prose** and [[Synthetic Target|visible alias]].

                        | Synthetic column | Other column |
                        | --- | --- |
                        | Exact cell \(index) | 中文 😀 |

                        A source-owned footnote[^diagnostic-\(index)] and inline math $x_{\(index)}^2$.

                        [^diagnostic-\(index)]: Synthetic definition with *emphasis*.

                        """.replacingOccurrences(of: "\n", with: "\r\n")
                    }.joined()
                    source += constructs + "\r\n$$\r\na^2 + b^2 = c^2\r\n$$\r\n\r\n```mermaid\r\nflowchart LR\r\n  A[Source] --> B[Projection]\r\n```\r\n"
                }
                self.source = source
                viewportRange = (source as NSString).range(of: viewport)
                viewportText = viewport
            }
        }

        private struct Endpoint {
            let layout: ContinuousClock.Instant
            let restored: ContinuousClock.Instant?
            let geometryReads: Int
            let restorationReads: Int
            let targetGeometry: [String: Double]
            let observedAnchor: [String: Double]
            let anchorOverlapsTarget: Bool
        }

        @MainActor
        private final class Projection: ObservableObject {
            private(set) var errorCount = 0
            func reportError() { errorCount += 1 }
        }

        private struct FeatureFixture: View {
            @ObservedObject var controller: DocumentController
            @ObservedObject var projection: Projection
            let note: WorkspaceNoteSnapshot

            var body: some View {
                let state = DocumentFeatureState(
                    activeNote: controller.activeSnapshot,
                    selectedDocumentPath: controller.selectedDocumentPath,
                    ordinarySearchScope: .triptych, currentVaultID: note.id.vaultID,
                    vaultRole: .sourceCorpus,
                    noteIdentityByPath: [note.id.relativePath: note.stableIdentity.resolvedID!],
                    workspaceCatalog: nil, canEdit: true, documentTextScale: 1,
                    documentAppearance: .defaultSettings, appearanceCSS: "", readCSS: "", livePreviewCSS: "",
                    initialScrollFraction: 0,
                    requestedPresentationMode: controller.requestedPresentationMode,
                    sourceLocationRequest: nil,
                    identityAmbiguity: nil, pendingIdentityRebinding: nil, identityMigrationFailureMessage: nil,
                    isResolvingIdentity: false)
                let actions = DocumentFeatureActions(
                    requestIdentityResolution: {}, retryIdentityRecovery: {}, beginSearch: { _ in },
                    clearRequestedPresentationMode: { controller.requestedPresentationMode = nil },
                    consumeSourceLocation: { _ in }, navigateToSourceLine: { _, _ in },
                    rememberScrollPosition: { _ in }, openInternalLink: { _ in }, openExternalURL: { _ in },
                    enterCSSSafeMode: { _ in projection.reportError() },
                    rememberPresentationMode: { controller.rememberPresentationMode($0) },
                    setSidebarVisible: { _ in }, setResearchInspectorVisible: { _ in },
                    openingDocumentPresentationDidComplete: {},
                    renameNote: { _, _, title in title },
                    notify: { _, kind in if case .error = kind { projection.reportError() } })
                DocumentFeatureView(controller: controller, state: state, actions: actions, hasShellNotices: false) {
                    EmptyView()
                }
            }
        }

        @MainActor
        private final class Harness {
            let data: FixtureData
            let note: WorkspaceNoteSnapshot
            let controller: DocumentController
            let projection = Projection()
            let session: DocumentSessionModel
            let window: NSWindow
            let viewportAnchor: EditorScrollAnchor
            private var hosting: NSHostingController<FeatureFixture>?
            private var closed = false
            private var expectedSelection: [MarkdownEditorSelectionRange]?
            private var editorIdentity: ObjectIdentifier?
            private var readerIdentities = Set<ObjectIdentifier>()

            init(kind: FixtureKind) {
                _ = NSApplication.shared
                let data = FixtureData(kind: kind)
                self.data = data
                let vaultID = UUID()
                let noteID = UUID()
                let document = NoteDocument(
                    relativePath: "Synthetic.md", rawContent: data.source,
                    citationSnapshot: ZoteroCitationSnapshot(noteID: noteID, vaultID: vaultID, status: .absent))
                let snapshot = WorkspaceNoteSnapshot(
                    id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath),
                    stableIdentity: .resolved(noteID), document: document,
                    fileMetadata: WorkspaceFileMetadata(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
                    graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
                note = snapshot
                let anchor = EditorScrollAnchor(
                    sourceFingerprint: snapshot.fingerprint.sha256,
                    sourceUTF16Offset: data.viewportRange.location,
                    blockUTF16LowerBound: data.viewportRange.location,
                    blockUTF16UpperBound: data.viewportRange.location + data.viewportRange.length,
                    relativeBlockPosition: 0.35, fallbackFraction: 0.5)
                viewportAnchor = anchor
                let owner = DocumentController()
                controller = owner
                owner.rememberPresentationMode(.read)
                owner.installOpenedDocument(snapshot, vaultName: "Synthetic", vaultRole: .sourceCorpus)
                let model = owner.session(for: .workspace(.init(vaultID: vaultID, noteID: noteID)))
                session = model
                model.requestReadScrollRestore(
                    fingerprint: snapshot.fingerprint.sha256, reason: .explicitNavigation,
                    position: ObservedScrollPosition(fraction: 0.5, anchor: anchor))
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let host = NSHostingController(rootView: FeatureFixture(controller: controller, projection: projection, note: note))
                host.sizingOptions = []
                hosting = host
                window.contentViewController = host
                host.view.frame = NSRect(x: 0, y: 0, width: 800, height: 620)
                host.view.autoresizingMask = [.width, .height]
                host.view.layoutSubtreeIfNeeded()
                #expect(!window.isVisible)
            }

            func run() async throws {
                _ = try await awaitDestination(.read)
                if ProcessInfo.processInfo.environment["SCHOLIUM_MODE_ROUNDTRIP_ONLY"] == "1" {
                    try await verifyRepeatedAndPendingModes()
                    return
                }
                // This Eulerian circuit covers each directed edge once. Cycle
                // zero includes first editor allocation; three warm cycles
                // retain that exact session, source and history.
                let route: [NotePresentationMode] = [.read, .livePreview, .source, .read, .source, .livePreview, .read]
                for cycle in 0..<4 {
                    for edge in 0..<(route.count - 1) {
                        let from = route[edge]
                        let to = route[edge + 1]
                        try await prepareViewport(in: from)
                        let before = try await performanceSamples()
                        try emitProgress("DocumentModeDiagnostic fixture=\(data.kind.rawValue) cycle=\(cycle) from=\(from.rawValue) to=\(to.rawValue)\n")
                        let start = ContinuousClock.now
                        // Published controller intent is consumed by the real
                        // NoteContentView selectPresentationMode route.
                        controller.requestedPresentationMode = to
                        let endpoint = try await awaitDestination(to)
                        let layout = Self.milliseconds(start.duration(to: endpoint.layout))
                        let restoration = endpoint.restored.map { Self.milliseconds(start.duration(to: $0)) }
                        let restoredMilliseconds: Any
                        if let restoration { restoredMilliseconds = restoration } else { restoredMilliseconds = NSNull() }
                        let after = try await performanceSamples()
                        try await verifyExactCleanState()
                        let stats = await controller.qaMemoryOwnerStats()
                        let metrics = Self.newSamples(before: before, after: after)
                        let grouped = Dictionary(grouping: metrics, by: \.name)
                        let web = grouped.mapValues { samples in
                            [
                                "count": Double(samples.count),
                                "totalMilliseconds": samples.reduce(0) { $0 + $1.durationMilliseconds },
                                "maximumMilliseconds": samples.map(\.durationMilliseconds).max() ?? 0,
                            ]
                        }
                        let record: [String: Any] = [
                            "metric": "native-feature-source-restored", "units": "milliseconds",
                            "fixture": data.kind.rawValue, "sourceUTF8Bytes": data.source.utf8.count,
                            "cycle": cycle, "phase": cycle == 0 ? "first" : "warm",
                            "from": from.rawValue, "to": to.rawValue, "milliseconds": restoredMilliseconds,
                            "sourceRestoredMilliseconds": restoredMilliseconds,
                            "readyLayoutMilliseconds": layout,
                            "restorationAcknowledged": endpoint.restored != nil,
                            "restorationAcknowledgmentMilliseconds": restoration.map { max(0, $0 - layout) } as Any? ?? NSNull(),
                            "geometryReads": endpoint.geometryReads, "restorationReads": endpoint.restorationReads,
                            "restorationEvidence": "known-exact-source-target-visible",
                            "targetGeometry": endpoint.targetGeometry, "observedAnchor": endpoint.observedAnchor,
                            "anchorOverlapsTarget": endpoint.anchorOverlapsTarget,
                            "webSamples": web, "webRingAtCapacity": after.count == 256,
                            "readerPagesObserved": readerIdentities.count,
                            "retainedSessions": stats.retainedSessions, "attachedEditors": stats.attachedWebViewSessions,
                            "readProjectionEntries": stats.readProjectionEntries,
                            "readProjectionHTMLUTF8Bytes": stats.readProjectionHTMLUTF8Bytes,
                        ]
                        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                        print(String(decoding: json, as: UTF8.self))
                        // Check the frame/font retry boundary independently of
                        // the initial native mode acknowledgement.
                        try await Task.sleep(for: .milliseconds(120))
                        _ = try await awaitDestination(to)
                    }
                }
                try await verifyRepeatedAndPendingModes()
            }

            private func verifyRepeatedAndPendingModes() async throws {
                controller.requestedPresentationMode = .source
                _ = try await awaitDestination(.source)
                try await prepareViewport(in: .source)
                let initial = try await awaitDestination(.source)
                let initialTop = try #require(initial.targetGeometry["targetTop"])
                for cycle in 0..<4 {
                    for mode in [NotePresentationMode.livePreview, .source] {
                        controller.requestedPresentationMode = mode
                        _ = try await awaitDestination(mode)
                        try await Task.sleep(for: .milliseconds(120))
                        let endpoint = try await awaitDestination(mode)
                        print(
                            "ModeRoundTrip fixture=\(data.kind.rawValue) cycle=\(cycle) mode=\(mode.rawValue) top=\(endpoint.targetGeometry["targetTop"] ?? 0) anchor=\(endpoint.observedAnchor)"
                        )
                        try await verifyExactCleanState()
                    }
                }
                let final = try await awaitDestination(.source)
                let finalTop = try #require(final.targetGeometry["targetTop"])
                #expect(abs(finalTop - initialTop) <= 2, "Source viewport drifted across repeated mode round trips: initial=\(initialTop), final=\(finalTop).")
                for mode in [NotePresentationMode.livePreview, .source] {
                    controller.requestedPresentationMode = .read
                    await Task.yield()
                    controller.requestedPresentationMode = mode
                    _ = try await awaitDestination(mode)
                    try await verifyExactCleanState()
                }
            }

            private func prepareViewport(in mode: NotePresentationMode) async throws {
                if mode == .read {
                    session.requestReadScrollRestore(
                        fingerprint: note.fingerprint.sha256, reason: .explicitNavigation,
                        position: ObservedScrollPosition(fraction: 0.5, anchor: viewportAnchor))
                } else {
                    let editor = session.editorSession
                    let web = try #require(editor.webView)
                    let caret = try #require(
                        EditorSourceOffsetMap(source: data.source).editorUTF16Offset(
                            forSourceUTF16Offset: data.viewportRange.location + 12))
                    _ = try await editor.send(.revealSourceRange(fromUTF16: caret, toUTF16: caret), in: web)
                    // Establish a measured starting viewport independently of
                    // queued restoration retries. Timed mode changes still use
                    // the complete native handoff and receive no scroll repair.
                    let aligned =
                        try await web.callAsyncJavaScript(
                            """
                            const line = Array.from(document.querySelectorAll('.cm-line')).find(line => line.textContent === text);
                            const scroller = document.querySelector('.cm-scroller');
                            if (!line || !scroller) return false;
                            scroller.scrollTop += line.getBoundingClientRect().top - scroller.getBoundingClientRect().top + 8;
                            return true;
                            """,
                            arguments: ["text": data.viewportText], in: nil, contentWorld: .page) as? Bool
                    try #require(aligned == true)
                }
                // Setup includes the coordinator's deferred restoration and
                // CodeMirror's measured viewport before the next action.
                // This is outside every measured transition.
                try await Task.sleep(for: .milliseconds(150))
                _ = try await awaitDestination(mode, requireTargetTopAnchor: true)
                if session.editorSession.isLoaded {
                    let ranges = try await selection()
                    if mode != .read {
                        let caret = try #require(
                            EditorSourceOffsetMap(source: data.source).editorUTF16Offset(
                                forSourceUTF16Offset: data.viewportRange.location + 12))
                        let expected = [MarkdownEditorSelectionRange(anchor: caret, head: caret)]
                        #expect(ranges == expected)
                        expectedSelection = expected
                    } else {
                        expectedSelection = ranges
                    }
                }
            }

            private func awaitDestination(_ mode: NotePresentationMode, requireTargetTopAnchor: Bool = false) async throws -> Endpoint {
                let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                var firstLayout: ContinuousClock.Instant?
                var geometryReads = 0
                var restorationReads = 0
                var lastGeometry: [String: Double] = [:]
                var lastAnchor: [String: Double] = [:]
                var lastTargetVisible = false
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    hosting?.view.layoutSubtreeIfNeeded()
                    let editor = session.editorSession
                    let ready =
                        mode == .read
                        ? !session.isEditing && session.renderedReadReadyFingerprint == note.fingerprint.sha256
                            && session.failedReadFingerprint == nil && session.scrollRestoreRequest == nil
                        : session.activeEditorMode == mode.editorMode && editor.isReady && editor.isLoaded
                            && editor.presentedMode == mode.editorMode && editor.errorMessage == nil
                            && editor.detachmentSuspensionID == nil
                    if ready, controller.currentPresentationMode == mode,
                        controller.requestedPresentationMode == nil, !session.returnToReadAfterSave,
                        let container = activeContainer(for: mode),
                        container.webView.window === window, !container.isHidden, !container.webView.isHidden
                    {
                        let web = container.webView
                        geometryReads += 1
                        let selector = mode == .read ? "#scholium-document" : ".cm-editor"
                        let geometry =
                            try await web.callAsyncJavaScript(
                                """
                                const node = document.querySelector(selector);
                                const rect = node?.getBoundingClientRect();
                                // Review has an exact source locator. The one
                                // unique plain fixture line is also recognizable
                                // within CodeMirror's mounted (bounded) line DOM.
                                const target = read
                                  ? node?.querySelector('p[data-source-utf16-start="' + from + '"]')
                                  : Array.from(node?.querySelectorAll('.cm-line') ?? []).find(line => line.textContent === text);
                                const targetIsExact = target?.textContent === text
                                  && (!read || Number(target.getAttribute('data-source-utf16-end')) >= to);
                                const targetRect = targetIsExact ? target.getBoundingClientRect() : null;
                                const scroller = read ? null : node?.querySelector('.cm-scroller')?.getBoundingClientRect();
                                const viewportTop = Math.max(0, scroller?.top ?? 0);
                                const viewportBottom = Math.min(innerHeight, scroller?.bottom ?? innerHeight);
                                const visibleHeight = targetRect
                                  ? Math.max(0, Math.min(targetRect.bottom, viewportBottom) - Math.max(targetRect.top, viewportTop)) : 0;
                                const targetVisible = !!targetRect && targetRect.height > 0
                                  && targetRect.right > 0 && targetRect.left < innerWidth
                                  && visibleHeight >= Math.min(12, targetRect.height);
                                return {
                                  nonzero: !!rect && rect.width > 0 && rect.height > 0 && !!node?.textContent?.length,
                                  targetVisible, targetFound: targetIsExact ? 1 : 0,
                                  targetTop: targetRect?.top ?? 0, targetBottom: targetRect?.bottom ?? 0,
                                  viewportTop, viewportBottom, visibleHeight,
                                };
                                """,
                                arguments: [
                                    "selector": selector, "read": mode == .read,
                                    "from": data.viewportRange.location, "to": data.viewportRange.location + data.viewportRange.length,
                                    "text": data.viewportText,
                                ],
                                in: nil, contentWorld: .page) as? [String: Any]
                        lastGeometry = Self.numericValues(geometry ?? [:])
                        lastTargetVisible = geometry?["targetVisible"] as? Bool == true
                        if geometry?["nonzero"] as? Bool == true {
                            if firstLayout == nil { firstLayout = .now }
                            restorationReads += 1
                            let validAnchor: Bool
                            if mode == .read {
                                let anchor =
                                    try await web.callAsyncJavaScript(
                                        "const extent = Math.max(0, document.documentElement.scrollHeight - innerHeight); return window.scholiumReadScroll?.current(extent ? scrollY / extent : 0) ?? null;",
                                        arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? [String: Any]
                                lastAnchor = Self.numericValues(anchor ?? [:])
                                if let lower = anchor?["blockUTF16LowerBound"] as? Int,
                                    let upper = anchor?["blockUTF16UpperBound"] as? Int,
                                    let offset = anchor?["sourceUTF16Offset"] as? Int
                                {
                                    validAnchor =
                                        lower >= 0 && upper >= lower && upper <= data.source.utf16.count
                                        && offset >= lower && offset <= upper
                                } else {
                                    validAnchor = false
                                }
                            } else {
                                let anchor = try await editor.currentScrollAnchor()
                                lastAnchor =
                                    anchor.map {
                                        [
                                            "blockUTF16LowerBound": Double($0.blockUTF16LowerBound),
                                            "blockUTF16UpperBound": Double($0.blockUTF16UpperBound),
                                            "sourceUTF16Offset": Double($0.sourceUTF16Offset),
                                            "relativeBlockPosition": $0.relativeBlockPosition,
                                            "fallbackFraction": $0.fallbackFraction,
                                        ]
                                    } ?? [:]
                                validAnchor =
                                    anchor?.sourceFingerprint == note.fingerprint.sha256
                                    && anchor?.isValid(forUTF16Length: data.source.utf16.count) == true
                            }
                            // The task-level oracle requires the exact target
                            // to remain visibly in context after reflow. The top
                            // block may differ; report that drift independently.
                            // No reveal or scroll mutation repairs the sample.
                            let anchorOverlapsTarget = anchorOverlapsViewport(
                                lower: lastAnchor["blockUTF16LowerBound"].map(Int.init),
                                upper: lastAnchor["blockUTF16UpperBound"].map(Int.init))
                            if validAnchor && lastTargetVisible && (!requireTargetTopAnchor || anchorOverlapsTarget) {
                                if mode == .read { readerIdentities.insert(ObjectIdentifier(web)) }
                                #expect(!window.isVisible)
                                return Endpoint(
                                    layout: firstLayout ?? .now, restored: .now,
                                    geometryReads: geometryReads, restorationReads: restorationReads,
                                    targetGeometry: lastGeometry, observedAnchor: lastAnchor,
                                    anchorOverlapsTarget: anchorOverlapsTarget)
                            }
                            if validAnchor, !requireTargetTopAnchor, let firstLayout,
                                firstLayout.duration(to: .now) >= .seconds(1)
                            {
                                Issue.record(
                                    Comment(
                                        rawValue:
                                            "Mode ready but source target was not restored fixture=\(data.kind.rawValue) target=\(mode.rawValue) geometry=\(lastGeometry) anchor=\(lastAnchor)"
                                    ))
                                return Endpoint(
                                    layout: firstLayout, restored: nil,
                                    geometryReads: geometryReads, restorationReads: restorationReads,
                                    targetGeometry: lastGeometry, observedAnchor: lastAnchor,
                                    anchorOverlapsTarget: anchorOverlapsTarget)
                            }
                        }
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                Issue.record(
                    Comment(
                        rawValue:
                            "Native mode diagnostic timed out fixture=\(data.kind.rawValue) target=\(mode.rawValue) requireTargetTopAnchor=\(requireTargetTopAnchor) editing=\(session.isEditing) loaded=\(session.editorSession.isLoaded) ready=\(session.editorSession.isReady) geometryReads=\(geometryReads) restorationReads=\(restorationReads) expectedLower=\(data.viewportRange.location) expectedUpper=\(data.viewportRange.location + data.viewportRange.length) targetVisible=\(lastTargetVisible) geometry=\(lastGeometry) anchor=\(lastAnchor) pendingReadRestore=\(session.scrollRestoreRequest != nil)"
                    ))
                throw MarkdownEditorSession.SessionError.unavailable
            }

            private func emitProgress(_ marker: String) throws {
                let data = Data(marker.utf8)
                FileHandle.standardError.write(data)
                guard let path = ProcessInfo.processInfo.environment["SCHOLIUM_MODE_PROGRESS_LOG"] else { return }
                let repository = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
                    .standardizedFileURL.resolvingSymlinksInPath()
                let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard output.path.hasPrefix(buildRoot.path + "/"), !output.hasDirectoryPath else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: output.path) {
                    try Data().write(to: output, options: .withoutOverwriting)
                }
                let file = try FileHandle(forWritingTo: output)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: data)
            }

            private static func numericValues(_ values: [String: Any]) -> [String: Double] {
                values.compactMapValues { value in
                    guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
                    return number.doubleValue
                }
            }

            private func anchorOverlapsViewport(lower: Int?, upper: Int?) -> Bool {
                guard let lower, let upper else { return false }
                return lower < data.viewportRange.location + data.viewportRange.length && upper > data.viewportRange.location
            }

            private func containers(in view: NSView) -> [DocumentWebViewContainer] {
                if let container = view as? DocumentWebViewContainer { return [container] }
                return view.subviews.flatMap { containers(in: $0) }
            }

            private func activeContainer(for mode: NotePresentationMode) -> DocumentWebViewContainer? {
                guard let root = window.contentView else { return nil }
                return containers(in: root).first {
                    $0.surfaceVisibility == .active
                        && (mode == .read ? $0.webView !== session.editorSession.webView : $0.webView === session.editorSession.webView)
                }
            }

            private func selection() async throws -> [MarkdownEditorSelectionRange] {
                let editor = session.editorSession
                let result = try await editor.send(.querySelection, in: #require(editor.webView))
                let selection = try #require(result.selection)
                #expect(selection.documentID == editor.bridgeDocumentID)
                #expect(selection.fingerprint == note.fingerprint.sha256)
                #expect(selection.generation == editor.generation)
                return selection.ranges
            }

            private func verifyExactCleanState() async throws {
                let editor = session.editorSession
                let snapshotMatches = controller.activeSnapshot?.fingerprint == note.fingerprint
                #expect(snapshotMatches && projection.errorCount == 0)
                #expect(!session.hasUnsavedChanges && session.conflict == nil && session.editError == nil)
                guard editor.isLoaded else { return }
                let web = try #require(editor.webView)
                let identity = ObjectIdentifier(web)
                if let editorIdentity { #expect(identity == editorIdentity) } else { editorIdentity = identity }
                // Verification must not clear native derived-source caches
                // through the normal persistence reconciliation path.
                let response = try await editor.send(.queryText, in: web, observingOnly: true)
                let source = try #require(response.text)
                let exact = source.utf8.elementsEqual(data.source.utf8)
                #expect(exact)
                #expect(editor.generation == 0 && !editor.isDirty)
                let ranges = try await selection()
                if let expectedSelection { #expect(ranges == expectedSelection) }
                let result = try await editor.send(.queryContext, in: web)
                let context = try #require(result.context)
                // Clean synthetic notes start with no history; a mode change
                // must not add text commands or discard source authority.
                #expect(context.undoLabel == nil && context.redoLabel == nil && !context.composing)
                #expect(!window.isVisible)
            }

            private func performanceSamples() async throws -> [MarkdownEditorPerformanceSample] {
                guard session.editorSession.isReady, session.editorSession.isLoaded else { return [] }
                return try await session.editorSession.queryPerformanceSamples()
            }

            private static func newSamples(
                before: [MarkdownEditorPerformanceSample], after: [MarkdownEditorPerformanceSample]
            ) -> [MarkdownEditorPerformanceSample] {
                // The production ring is bounded. Compare its retained overlap
                // instead of assuming that cumulative counts never wrap.
                for overlap in stride(from: min(before.count, after.count), through: 0, by: -1) {
                    if Array(before.suffix(overlap)) == Array(after.prefix(overlap)) {
                        return Array(after.dropFirst(overlap))
                    }
                }
                return after
            }

            private static func milliseconds(_ duration: Duration) -> Double {
                let value = duration.components
                return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1_000_000_000_000_000
            }

            func closeAndDrain() async {
                guard !closed else { return }
                closed = true
                session.cancelScheduledWork()
                controller.requestedPresentationMode = nil
                window.contentViewController = nil
                hosting = nil
                window.close()
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while session.editorSession.hasAttachedWebView, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                #expect(!session.editorSession.hasAttachedWebView && !window.isVisible)
                controller.removeAll()
                controller.unbind()
            }
        }
    }
#endif
