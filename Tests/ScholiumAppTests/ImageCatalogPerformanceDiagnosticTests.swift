import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    /// Separates the generated gallery's bridge admission from live image layout.
    /// Uses the production size limits and deadline in a hidden, disposable editor.
    @MainActor
    @Suite(
        "Image catalog performance diagnostics", .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_GALLERY_DIAGNOSTIC_FIXTURE"] != nil))
    struct ImageCatalogPerformanceDiagnosticTests {
        @Test("Generated image catalog is admitted in Source before live layout")
        func galleryAdmissionAndLayout() async throws {
            let (source, resources, _) = try Self.fixture()

            let dispatcher = TimedDispatcher()
            let harness = MarkdownEditorWebViewIntegrationTests.EditorHarness(
                source: source, bridgeDispatcher: dispatcher, initialMode: .source, ordersWindowFront: false
            )
            do {
                try await harness.waitUntilReady()
                let selection = harness.session.context?.selections
                let generation = harness.session.generation
                let webView = try #require(harness.session.webView)
                dispatcher.begin("source-catalog")
                let start = ContinuousClock.now
                do {
                    _ = try await harness.session.send(
                        .setPresentation(.init(imageResources: resources)), in: webView)
                    try Self.report([
                        "metric": "gallery-probe-phase", "phase": "source-catalog", "accepted": true,
                        "milliseconds": Self.milliseconds(start.duration(to: .now)),
                    ])
                } catch {
                    try Self.report([
                        "metric": "gallery-probe-phase", "phase": "source-catalog", "accepted": false,
                        "milliseconds": Self.milliseconds(start.duration(to: .now)),
                        "error": String(describing: error),
                    ])
                    throw error
                }
                try await Self.reportWebPhases(in: webView)
                #expect(try await harness.session.currentText(for: harness.documentID) == source)
                #expect(harness.session.generation == generation)
                #expect(harness.session.context?.selections == selection)

                dispatcher.begin("live-layout")
                let layoutStart = ContinuousClock.now
                harness.session.setMode(.livePreview)
                try await harness.waitUntilPresentedMode(.livePreview)
                try Self.report([
                    "metric": "gallery-probe-phase", "phase": "live-layout", "accepted": true,
                    "milliseconds": Self.milliseconds(layoutStart.duration(to: .now)),
                ])
                try await Self.reportWebPhases(in: webView)
                #expect(try await harness.session.currentText(for: harness.documentID) == source)
                #expect(harness.session.generation == generation)
                #expect(harness.session.context?.selections == selection)
                await harness.closeAndDrain()
            } catch {
                if let webView = harness.session.webView {
                    do { try await Self.reportWebPhases(in: webView) } catch {
                        try Self.report([
                            "metric": "gallery-probe-web-error", "error": String(describing: error),
                        ])
                    }
                }
                await harness.closeAndDrain()
                throw error
            }
        }

        @Test("Generated image opening restores the large-image viewport")
        func galleryOpeningAtLargeImage() async throws {
            let (source, _, images) = try Self.fixture()
            let heading = (source as NSString).range(of: "### Large image 0001", options: .literal)
            try #require(heading.location != NSNotFound)
            let anchor = EditorScrollAnchor(
                sourceFingerprint: DocumentFingerprint(content: source).sha256,
                sourceUTF16Offset: heading.location, blockUTF16LowerBound: heading.location,
                blockUTF16UpperBound: NSMaxRange(heading), relativeBlockPosition: 0.35,
                fallbackFraction: 0.5)
            let dispatcher = TimedDispatcher()
            dispatcher.begin("opening-large-image")
            let start = ContinuousClock.now
            let harness = MarkdownEditorWebViewIntegrationTests.EditorHarness(
                source: source, bridgeDispatcher: dispatcher,
                initialScrollAnchor: anchor, initialWindowSize: NSSize(width: 800, height: 620),
                ordersWindowFront: false,
                imageResourcesQuery: { _ in
                    try? Self.report([
                        "metric": "gallery-probe-query", "phase": "return-admitted-images",
                        "images": images.count,
                    ])
                    return images
                })
            do {
                try await harness.waitUntilReady()
                try Self.report([
                    "metric": "gallery-probe-phase", "phase": "opening-large-image", "accepted": true,
                    "milliseconds": Self.milliseconds(start.duration(to: .now)),
                ])
                try await Self.reportWebPhases(in: #require(harness.session.webView))
                #expect(try await harness.session.currentText(for: harness.documentID) == source)
                #expect(harness.session.generation == 0)
                await harness.closeAndDrain()
            } catch {
                try Self.report([
                    "metric": "gallery-probe-phase", "phase": "opening-large-image", "accepted": false,
                    "milliseconds": Self.milliseconds(start.duration(to: .now)),
                    "error": harness.session.errorMessage ?? String(describing: error),
                ])
                if let webView = harness.session.webView {
                    do {
                        try await Self.reportWebPhases(in: webView)
                        let performance = try await harness.session.send(.queryPerformance, in: webView)
                        try Self.report([
                            "metric": "gallery-probe-performance",
                            "samples": (performance.performanceSamples ?? []).map {
                                ["name": $0.name, "milliseconds": $0.durationMilliseconds, "observed": $0.observed]
                                    as [String: Any]
                            },
                        ])
                    } catch {
                        try Self.report([
                            "metric": "gallery-probe-web-error", "error": String(describing: error),
                        ])
                    }
                }
                await harness.closeAndDrain()
                throw error
            }
        }

        @Test("Real workspace gallery preserves all six feature handoffs")
        func galleryNativeFeature() async throws {
            let fixture = try Self.fixtureURL()
            let sourceRelativePath = "02-topics/Stress/Stress Image Gallery.md"
            let original = try Data(contentsOf: fixture.appendingPathComponent(sourceRelativePath))
            let source = try #require(NoteDocument.decodeUTF8PreservingBOM(original))
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/gallery-feature-runtime/\(UUID().uuidString.lowercased())", isDirectory: true)
            let working = root.appendingPathComponent("fixture", isDirectory: true)
            let roles = ["01-analyses", "02-topics", "03-works"]
            let manager = FileManager.default
            try #require(!manager.fileExists(atPath: root.path))
            for role in roles { try manager.createDirectory(at: working.appendingPathComponent(role), withIntermediateDirectories: true) }
            defer {
                do { try manager.removeItem(at: root) } catch { Issue.record(error) }
            }
            let sourceFile = working.appendingPathComponent(sourceRelativePath)
            try manager.createDirectory(at: sourceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: fixture.appendingPathComponent(sourceRelativePath), to: sourceFile)
            let attachments = "02-topics/Attachments"
            try manager.copyItem(at: fixture.appendingPathComponent(attachments), to: working.appendingPathComponent(attachments))
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: root.appendingPathComponent("state/Application Support", isDirectory: true),
                        workspaceRegistryStorageURL: root.appendingPathComponent("state/Registry", isDirectory: true))))
            do {
                let handle = try await runtime.configureTriptych(
                    paperAnalysisURL: working.appendingPathComponent(roles[0]),
                    topicKnowledgeURL: working.appendingPathComponent(roles[1]),
                    outputURL: working.appendingPathComponent(roles[2]),
                    portableContainerURL: working, triptychName: "Gallery Feature Diagnostic")
                let workspace = try await handle.snapshot()
                try #require(workspace.phase.isComplete)
                let vault = try #require(
                    workspace.vaults.first {
                        $0.vault.canonicalPath == working.appendingPathComponent(roles[1]).path
                    })
                let summary = try #require(vault.documents.first { $0.id.relativePath == "Stress/Stress Image Gallery.md" })
                let note = try await handle.documents.hydrate(summary)
                let heading = "### Large image 0001"
                let visible = "Large image 0001"
                let destination = "../Attachments/stress/image-large-0001.png"
                let range = (source as NSString).range(of: heading, options: .literal)
                let imageRange = (source as NSString).range(of: "![Synthetic image 0001](\(destination))", options: .literal)
                try #require(range.location != NSNotFound && imageRange.location != NSNotFound)
                let data = DocumentModeSwitchPerformanceDiagnosticTests.FixtureData(
                    name: "gallery_minimal_workspace", source: source, viewportRange: range,
                    viewportText: visible, editorViewportTexts: [heading, visible], expectedVisibleImageWidth: 1600,
                    expectedVisibleImageDestination: destination, expectedVisibleImageSourceRange: imageRange)
                try Self.report([
                    "metric": "gallery-feature-setup", "notes": workspace.vaults.reduce(0) { $0 + $1.documents.count },
                    "scope": "Real three-root runtime with one exact generated gallery and original attachment copies; empty history, no 5000-note load.",
                ])
                let harness = try DocumentModeSwitchPerformanceDiagnosticTests.Harness(
                    data: data, note: note, workspace: workspace, documents: handle.documents, sourceFile: sourceFile)
                let trace = Self.traceGalleryOpening(harness)
                do {
                    try await harness.run()
                    trace.cancel()
                    await trace.value
                    await harness.closeAndDrain()
                } catch {
                    trace.cancel()
                    await trace.value
                    if ProcessInfo.processInfo.environment["SCHOLIUM_GALLERY_TRACE"] == "1",
                        let webView = harness.session.editorSession.webView
                    {
                        do {
                            let result = try await webView.callAsyncJavaScript(
                                "return window.__scholiumGalleryDOMTrace ?? null", arguments: [:], in: nil, contentWorld: .page)
                            try Self.report(["metric": "gallery-feature-dom-probe", "trace": result ?? NSNull()])
                        } catch { try Self.report(["metric": "gallery-feature-dom-probe-error", "error": String(describing: error)]) }
                    }
                    await harness.closeAndDrain()
                    throw error
                }
                await runtime.shutdown()
                #expect(try Data(contentsOf: sourceFile) == original)
                #expect(try Data(contentsOf: fixture.appendingPathComponent(sourceRelativePath)) == original)
            } catch {
                await runtime.shutdown()
                #expect(try Data(contentsOf: sourceFile) == original)
                #expect(try Data(contentsOf: fixture.appendingPathComponent(sourceRelativePath)) == original)
                throw error
            }
        }

        private static func traceGalleryOpening(
            _ harness: DocumentModeSwitchPerformanceDiagnosticTests.Harness
        ) -> Task<Void, Never> {
            Task { @MainActor in
                guard ProcessInfo.processInfo.environment["SCHOLIUM_GALLERY_TRACE"] == "1" else { return }
                do {
                    while !harness.session.editorSession.isReady || harness.session.editorSession.webView == nil {
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    let webView = try #require(harness.session.editorSession.webView)
                    _ = try await webView.callAsyncJavaScript(
                        """
                        const probe = window.__scholiumGalleryDOMTrace = {calls: 0, nodes: 0,
                          added: 0, removed: 0, first: [], last: [], requests: []};
                        const ids = new WeakMap();
                        const id = image => {
                          if (!ids.has(image)) ids.set(image, ++probe.nodes);
                          return ids.get(image);
                        };
                        const identity = image => {
                          const shell = image.closest('[data-scholium-source-from]');
                          return {id: id(image), from: shell?.getAttribute('data-scholium-source-from'),
                            to: shell?.getAttribute('data-scholium-source-to'), complete: image.complete,
                            width: image.naturalWidth, height: image.naturalHeight, connected: image.isConnected};
                        };
                        const record = (phase, image) => {
                          const row = {phase, ...identity(image)};
                          if (probe.first.length < 16) {
                            row.bounds = image.getBoundingClientRect().toJSON();
                            row.scrollTop = document.querySelector('.cm-scroller')?.scrollTop;
                            probe.first.push(row);
                          }
                          probe.last.push(row);
                          if (probe.last.length > 8) probe.last.shift();
                        };
                        const decode = HTMLImageElement.prototype.decode;
                        HTMLImageElement.prototype.decode = function() {
                          probe.calls++;
                          record('decode-start', this);
                          return decode.call(this).finally(() => record('decode-end', this));
                        };
                        const images = node => node.nodeType === Node.ELEMENT_NODE
                          ? [...(node.matches('img') ? [node] : []), ...node.querySelectorAll('img')] : [];
                        const observer = new MutationObserver(records => {
                          for (const record of records) {
                            for (const node of record.addedNodes) for (const image of images(node)) {
                              probe.added++; id(image);
                            }
                            for (const node of record.removedNodes) probe.removed += images(node).length;
                          }
                        });
                        observer.observe(document.querySelector('.cm-content'), {childList: true, subtree: true});
                        const dispatch = window.scholiumEditor.dispatch;
                        window.scholiumEditor.dispatch = request => {
                          if (request.operation.type === 'completePreparation') {
                            probe.requests.push({anchor: request.operation.anchor ?? null, fraction: request.operation.fraction ?? null});
                          }
                          return dispatch(request);
                        };
                        return true;
                        """, arguments: [:], in: nil, contentWorld: .page)
                } catch is CancellationError {
                } catch { Issue.record(error) }
            }
        }

        private static func fixture() throws -> (
            String, [String: String], [String: RenderedMarkdownImage]
        ) {
            let fixture = try fixtureURL()
            let sourceData = try Data(
                contentsOf: fixture.appendingPathComponent("02-topics/Stress/Stress Image Gallery.md"))
            let source = try #require(String(data: sourceData, encoding: .utf8))
            let directory = fixture.appendingPathComponent(
                "02-topics/Attachments/stress", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var resources: [String: String] = [:]
            var images: [String: RenderedMarkdownImage] = [:]
            var imageBytes = 0
            for file in files {
                let image = try RenderedMarkdownImage(data: Data(contentsOf: file), mimeType: "image/png")
                images["../Attachments/stress/" + file.lastPathComponent] = image
                resources["../Attachments/stress/" + file.lastPathComponent] =
                    "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
                imageBytes += image.data.count
            }
            try #require(resources.count == 244)
            try Self.report([
                "metric": "gallery-probe-fixture", "images": resources.count, "imageBytes": imageBytes,
            ])

            return (source, resources, images)
        }

        private static func fixtureURL() throws -> URL {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
                .resolvingSymlinksInPath()
            let fixture = URL(
                fileURLWithPath: try #require(
                    ProcessInfo.processInfo.environment["SCHOLIUM_GALLERY_DIAGNOSTIC_FIXTURE"])
            )
            .resolvingSymlinksInPath()
            try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
            return fixture
        }

        private static func reportWebPhases(in webView: WKWebView) async throws {
            var phases: Any?
            try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: .seconds(8)) {
                phases = try await webView.callAsyncJavaScript(
                    "return window.__scholiumGalleryProbe ?? []", arguments: [:], in: nil, contentWorld: .page
                )
            }
            try report(["metric": "gallery-probe-web", "phases": phases ?? []])
        }

        fileprivate static func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds)
                / 1_000_000_000_000_000
        }

        fileprivate static func report(_ value: [String: Any]) throws {
            let data = try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            FileHandle.standardOutput.write(data + Data([10]))
        }

        @MainActor
        private final class TimedDispatcher: MarkdownEditorBridgeDispatching {
            private var phase = "opening-source"
            private var phaseStart = ContinuousClock.now

            func begin(_ phase: String) {
                self.phase = phase
                phaseStart = .now
            }

            func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
                let start = ContinuousClock.now
                let beforeDispatch = ImageCatalogPerformanceDiagnosticTests.milliseconds(
                    phaseStart.duration(to: start))
                defer {
                    try? ImageCatalogPerformanceDiagnosticTests.report([
                        "metric": "gallery-probe-native-dispatch", "phase": phase,
                        "beforeDispatchMilliseconds": beforeDispatch, "requestBytes": requestJSON.utf8.count,
                        "dispatchMilliseconds": ImageCatalogPerformanceDiagnosticTests.milliseconds(
                            start.duration(to: .now)),
                    ])
                }
                return try await webView.callAsyncJavaScript(
                    """
                    const samples = window.__scholiumGalleryProbe ??= [];
                    const sample = {phase, stage: 'parse', length: requestJSON.length};
                    samples.push(sample);
                    const start = performance.now();
                    try {
                      const request = JSON.parse(requestJSON);
                      sample.operation = request.operation?.type;
                      sample.parseMilliseconds = performance.now() - start;
                      sample.stage = 'dispatch';
                      const dispatchStart = performance.now();
                      const result = await window.scholiumEditor.dispatch(request);
                      sample.dispatchMilliseconds = performance.now() - dispatchStart;
                      sample.accepted = result.accepted;
                      sample.error = result.error ?? null;
                      sample.stage = 'complete';
                      return result;
                    } catch (error) {
                      sample.error = String(error);
                      throw error;
                    } finally { sample.totalMilliseconds = performance.now() - start; }
                    """,
                    arguments: ["requestJSON": requestJSON, "phase": phase], in: nil, contentWorld: .page)
            }
        }
    }
#endif
