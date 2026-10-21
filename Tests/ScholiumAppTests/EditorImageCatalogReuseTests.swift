import AppKit
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    @MainActor
    @Suite("Editor image catalog reuse", .serialized)
    struct EditorImageCatalogReuseTests {
        @Test("Unchanged images are revalidated after input without a new catalog transfer")
        func unchangedCatalogAndAppearance() async throws {
            try await Self.withFixture { fixture in
                let session = fixture.harness.session
                let startQueries = fixture.querySources.count
                let startTransfers = fixture.dispatcher.presentations.count
                try await fixture.edit(" Exact e\u{301} 中文 🦉.")
                try #require(fixture.querySources.count == startQueries + 1)
                #expect(fixture.querySources.last == session.checkedSource)
                #expect(fixture.dispatcher.presentations.count == startTransfers)

                // Another presentation channel must not accidentally carry the
                // already admitted, older-generation image bytes with it.
                let selection = session.context?.selections
                let undo = session.context?.undoLabel
                session.setPresentationCSS(":root { --image-reuse-probe: 1; }")
                try await session.testingAwaitImageResourceRefreshAndPresentation()
                let appearance = try #require(fixture.dispatcher.presentations.last)
                #expect(appearance.imageResources.isEmpty)
                #expect(appearance.imageResourceGeneration < session.generation)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == fixture.resourceURLs)
                #expect(session.context?.selections == selection)
                #expect(session.context?.undoLabel == undo)
                try await fixture.expectVisibleImage()
                try await fixture.undoAndExpectOriginal()
            }
        }

        @Test("Changed bytes, MIME, additions and removals replace the admitted catalog")
        func changedCatalog() async throws {
            try await Self.withFixture { fixture in
                let session = fixture.harness.session
                let source = session.checkedSource
                let selection = session.context?.selections
                let originalURL = fixture.resourceURLs[fixture.destination]
                fixture.images[fixture.destination] = try Self.image(color: .blue)
                try await fixture.refresh("changed-bytes")
                #expect(fixture.resourceURLs[fixture.destination] != originalURL)
                #expect(fixture.dispatcher.presentations.last?.imageResources == fixture.resourceURLs)

                fixture.images[fixture.destination] = try Self.image(color: .blue, type: .jpeg)
                try await fixture.refresh("changed-mime")
                #expect(fixture.dispatcher.presentations.last?.imageResources[fixture.destination]?.hasPrefix("data:image/jpeg;") == true)
                fixture.images["Attachments/second.png"] = try Self.image(color: .green)
                try await fixture.refresh("added")
                #expect(fixture.dispatcher.presentations.last?.imageResources.count == 2)
                fixture.images.removeValue(forKey: fixture.destination)
                try await fixture.refresh("removed")
                #expect(fixture.dispatcher.presentations.last?.imageResources == fixture.resourceURLs)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]).isEmpty)
                fixture.images = [:]
                try await fixture.refresh("empty")
                #expect(fixture.dispatcher.presentations.last?.imageResources.isEmpty == true)
                #expect(Data(try await session.currentText().utf8) == Data(source.utf8))
                #expect(session.context?.selections == selection)
                #expect(session.context?.undoLabel == nil)
            }
        }

        @Test("An unacknowledged catalog retries even when its returned bytes are unchanged")
        func failedDeliveryRetries() async throws {
            try await Self.withFixture { fixture in
                let session = fixture.harness.session
                let original = session.deliveredPreviewImageResources(for: [fixture.destination])
                fixture.images[fixture.destination] = try Self.image(color: .blue)
                fixture.dispatcher.failsPresentations = true
                do {
                    try await fixture.refresh("failed-delivery")
                    Issue.record("The injected presentation failure was not observed.")
                } catch {}
                fixture.dispatcher.failsPresentations = false
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == original)
                let attempts = fixture.dispatcher.presentations.count
                try await fixture.refresh("retry-delivery")
                #expect(fixture.dispatcher.presentations.count == attempts + 1)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == fixture.resourceURLs)
                try await fixture.expectVisibleImage()
            }
        }

        @Test("Input racing a catalog dispatch still admits the latest generation and replays on reconstruction")
        func generationRaceAndReconstruction() async throws {
            try await Self.withFixture { fixture in
                let session = fixture.harness.session
                fixture.images[fixture.destination] = try Self.image(color: .blue)
                fixture.dispatcher.holdsNextPresentation = true
                fixture.installQuery("held-catalog")
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !fixture.dispatcher.isHoldingPresentation {
                    try #require(ContinuousClock.now < deadline)
                    try await Task.sleep(for: .milliseconds(2))
                }
                let oldGeneration = session.generation
                // Presentation is outside the mutation lane; a real source
                // transaction may advance while its bridge operation is held.
                try await session.perform(.pastePlain, argument: " race")
                try #require(session.generation > oldGeneration)
                fixture.dispatcher.releasePresentation()
                try await session.testingAwaitImageResourceRefreshAndPresentation()
                #expect(fixture.dispatcher.presentations.last?.imageResourceGeneration == session.generation)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == fixture.resourceURLs)
                try await fixture.expectVisibleImage()

                try await fixture.edit(" retained")
                let exactSource = session.checkedSource
                let selection = session.context?.selections
                let undo = session.context?.undoLabel
                let initializations = fixture.dispatcher.initializations.count
                try await session.captureStateForViewReconstruction(suspendForDetachment: true)
                try await fixture.harness.reconstructEditorView()
                try await fixture.harness.waitUntilReady()
                try await session.testingAwaitImageResourceRefreshAndPresentation()
                #expect(fixture.dispatcher.initializations.count == initializations + 1)
                #expect(fixture.dispatcher.initializations.last?.imageResources.isEmpty == false)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == fixture.resourceURLs)
                #expect(Data(try await session.currentText().utf8) == Data(exactSource.utf8))
                #expect(session.context?.selections == selection)
                #expect(session.context?.undoLabel == undo)
                try await fixture.expectVisibleImage()
            }
        }

        @Test("Wrong document and generation cannot replace or reuse the current catalog")
        func staleCatalogRejected() async throws {
            try await Self.withFixture { fixture in
                let session = fixture.harness.session
                let original = fixture.resourceURLs
                let transfers = fixture.dispatcher.presentations.count
                let changed = [fixture.destination: try Self.image(color: .blue)]
                session.setImageResources(changed, documentID: "Other.md", generation: session.generation)
                session.setImageResources(changed, documentID: session.bridgeDocumentID, generation: session.generation + 1)
                try await session.testingAwaitImageResourceRefreshAndPresentation()
                #expect(fixture.dispatcher.presentations.count == transfers)
                #expect(session.deliveredPreviewImageResources(for: [fixture.destination]) == original)
                try await fixture.expectVisibleImage()
            }
        }

        @Test("Canonical-equivalent image paths still replace their exact Web catalog keys")
        func exactDestinationBytes() async throws {
            let nfc = "Attachments/caf\u{E9}.png"
            let nfd = "Attachments/cafe\u{301}.png"
            try #require(nfc == nfd && Data(nfc.utf8) != Data(nfd.utf8))
            try await Self.withFixture(destination: nfc) { fixture in
                let session = fixture.harness.session
                let image = try #require(fixture.images[nfc])
                fixture.images = [nfd: image]
                let exactSource = fixture.source.replacingOccurrences(of: nfc, with: nfd)
                let end = EditorSourceOffsetMap(source: fixture.source).editorUTF16Length
                fixture.harness.revealEditorRange(fromUTF16: 0, toUTF16: end)
                try await fixture.harness.waitUntilSelection(anchor: 0, head: end)
                try await session.perform(.pastePlain, argument: exactSource)
                try await session.testingAwaitImageResourceRefreshAndPresentation()
                let catalog = try #require(fixture.dispatcher.presentations.last?.imageResources)
                #expect(catalog.keys.map { Data($0.utf8) } == [Data(nfd.utf8)])
                #expect(!catalog.keys.contains { Data($0.utf8) == Data(nfc.utf8) })
                #expect(Data(try await session.currentText().utf8) == Data(exactSource.utf8))
                try await fixture.expectVisibleImage()
                try await fixture.undoAndExpectOriginal()
            }
        }

        private static func withFixture(
            destination: String = "Attachments/image.png",
            _ body: @MainActor (Fixture) async throws -> Void
        ) async throws {
            let fixture = try Fixture(destination: destination)
            do {
                try await fixture.harness.waitUntilReady()
                try await fixture.harness.session.testingAwaitImageResourceRefreshAndPresentation()
                try await body(fixture)
                await fixture.harness.closeAndDrain()
            } catch {
                fixture.dispatcher.releasePresentation()
                await fixture.harness.closeAndDrain()
                throw error
            }
        }

        private static func image(
            color: NSColor, type: NSBitmapImageRep.FileType = .png
        ) throws -> RenderedMarkdownImage {
            let bitmap = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                    samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let rgb = try #require(color.usingColorSpace(.deviceRGB))
            let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                UInt8(($0 * 255).rounded())
            }
            let pixels = try #require(bitmap.bitmapData)
            pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            for y in 0..<2 {
                for x in 0..<2 {
                    for component in 0..<3 { pixels[y * bitmap.bytesPerRow + x * 3 + component] = components[component] }
                }
            }
            let bytes = try #require(bitmap.representation(using: type, properties: [:]))
            return try RenderedMarkdownImage(data: bytes, mimeType: type == .jpeg ? "image/jpeg" : "image/png")
        }

        @MainActor
        private final class Fixture {
            let destination: String
            let source: String
            let dispatcher = Dispatcher()
            var images: [String: RenderedMarkdownImage]
            var querySources: [String] = []
            var harness: MarkdownEditorWebViewIntegrationTests.EditorHarness!

            init(destination: String) throws {
                self.destination = destination
                source = "Synthetic exact e\u{301} 中文 🦉.\r\n\r\n![Synthetic](\(destination))\r\n"
                images = [destination: try EditorImageCatalogReuseTests.image(color: .red)]
                harness = MarkdownEditorWebViewIntegrationTests.EditorHarness(
                    source: source, bridgeDispatcher: dispatcher, ordersWindowFront: false,
                    imageResourcesQuery: { [weak self] source in self?.query(source) ?? [:] })
            }

            var resourceURLs: [String: String] {
                images.mapValues { "data:\($0.mimeType);base64,\($0.data.base64EncodedString())" }
            }

            func query(_ source: String) -> [String: RenderedMarkdownImage] {
                querySources.append(source)
                return images
            }

            func installQuery(_ key: String) {
                harness.session.installImageResourceQuery({ [weak self] source in self?.query(source) ?? [:] }, contextKey: key)
            }

            func refresh(_ key: String) async throws {
                installQuery(key)
                try await harness.session.testingAwaitImageResourceRefreshAndPresentation()
            }

            func edit(_ text: String) async throws {
                let end = EditorSourceOffsetMap(source: harness.session.checkedSource).editorUTF16Length
                harness.revealEditorRange(fromUTF16: end, toUTF16: end)
                try await harness.waitUntilSelection(anchor: end, head: end)
                try await harness.session.perform(.pastePlain, argument: text)
                try await harness.session.testingAwaitImageResourceRefreshAndPresentation()
            }

            func expectVisibleImage() async throws {
                #expect(
                    try await harness.callPageJavaScript(
                        "return document.querySelector('.cm-content img')?.getAttribute('src') === expected;",
                        arguments: ["expected": try #require(resourceURLs[destination])]) as? Bool == true)
            }

            func undoAndExpectOriginal() async throws {
                _ = try await harness.callPageJavaScript(
                    "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key:'z', code:'KeyZ', keyCode:90, which:90, metaKey:true, bubbles:true, cancelable:true}));"
                )
                #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
                #expect(harness.session.context?.undoLabel == nil)
                #expect(harness.session.context?.redoLabel != nil)
            }
        }

        @MainActor
        private final class Dispatcher: MarkdownEditorBridgeDispatching {
            var presentations: [MarkdownEditorPresentationConfiguration] = []
            var initializations: [MarkdownEditorPresentationConfiguration] = []
            var failsPresentations = false
            var holdsNextPresentation = false
            private var heldPresentation: CheckedContinuation<Void, Never>?
            var isHoldingPresentation: Bool { heldPresentation != nil }

            func releasePresentation() {
                heldPresentation?.resume()
                heldPresentation = nil
            }

            func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
                let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
                switch request.operation {
                case .setPresentation(let value):
                    presentations.append(value)
                    if failsPresentations {
                        throw MarkdownEditorSession.SessionError.unavailable
                    }
                    if holdsNextPresentation {
                        holdsNextPresentation = false
                        await withCheckedContinuation { heldPresentation = $0 }
                    }
                case .initialize(_, _, _, _, _, _, let presentation):
                    initializations.append(presentation)
                default: break
                }
                return try await webView.callAsyncJavaScript(
                    "return await window.scholiumEditor.dispatch(JSON.parse(requestJSON));",
                    arguments: ["requestJSON": requestJSON], in: nil, contentWorld: .page)
            }
        }
    }
#endif
