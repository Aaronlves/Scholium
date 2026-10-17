import AppKit
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Deferred gallery images converge at a fractional source anchor without changing editor state")
    func deferredGalleryPreparationPreservesSourceViewport() async throws {
        // Match the generated gallery's block structure and intrinsic image
        // sizes without its distinct attachments or large transfer payload.
        let smallDestination = "../Attachments/stress/image-small.png"
        let largeDestination = "../Attachments/stress/image-large.png"
        let images = [
            smallDestination: try Self.galleryPreparationPNG(width: 320, height: 224),
            largeDestination: try Self.galleryPreparationPNG(width: 1_600, height: 1_200),
        ]
        let source = Self.galleryPreparationSource(small: smallDestination, large: largeDestination)
        let heading = "### Large image 0001"
        let headingRange = (source as NSString).range(of: heading, options: .literal)
        try #require(headingRange.location != NSNotFound)
        let imageSource = "![Synthetic image 0001](\(largeDestination))"
        let imageRange = (source as NSString).range(of: imageSource, options: .literal)
        try #require(imageRange.location != NSNotFound)
        let anchor = EditorScrollAnchor(
            sourceFingerprint: DocumentFingerprint(content: source).sha256,
            sourceUTF16Offset: headingRange.location + 7,
            blockUTF16LowerBound: headingRange.location,
            blockUTF16UpperBound: NSMaxRange(headingRange),
            relativeBlockPosition: 0.32985121874010764,
            fallbackFraction: 0.9906483790523691)
        let gate = GalleryPreparationImageGate(images: images)
        let bridge = GalleryPreparationBridgeProbe()
        let harness = EditorHarness(
            documentTitle: "Stress Image Gallery", source: source, bridgeDispatcher: bridge,
            initialPresentationCSS: ScholiumDocumentPresentationConfiguration(textScale: 1).css,
            initialScrollAnchor: anchor, initialWindowSize: NSSize(width: 800, height: 620),
            ordersWindowFront: false, imageResourcesQuery: gate.query)
        defer {
            gate.release()
            harness.close()
        }
        do {
            let initializationDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while bridge.initialized == nil || !harness.session.isReady || !gate.hasRequest {
                try #require(ContinuousClock.now < initializationDeadline, "The gallery did not reach its empty-catalog initialization.")
                try await Task.sleep(for: .milliseconds(10))
            }
            let initialized = try #require(bridge.initialized)
            #expect(bridge.initialImageCount == 0)
            #expect(!harness.session.isLoaded)
            // Make the catalog arrive on a later native turn, as it does when
            // the real feature queries its admitted local attachments.
            try await Task.sleep(for: .milliseconds(100))
            gate.release()
            try await harness.waitUntilReady()
            #expect(bridge.catalogImageCounts == [2])
            #expect(bridge.preparationRequestCount >= 1)
            #expect(bridge.preparationDeadlineMilliseconds.allSatisfy { $0 > 0 && $0 <= 8_000 })
            #expect(harness.session.generation == 0)
            #expect(harness.session.checkedSource.utf8.elementsEqual(source.utf8))
            #expect(try await harness.session.currentText(for: harness.documentID).utf8.elementsEqual(source.utf8))
            #expect(!harness.session.isDirty)
            let web = try #require(harness.session.webView)
            let context = try #require(try await harness.session.send(.queryContext, in: web).context)
            #expect(context.selections == initialized.selections)
            #expect(context.undoLabel == nil && context.redoLabel == nil)
            let geometry =
                try await web.callAsyncJavaScript(
                    """
                    const scroller = document.querySelector('.cm-scroller');
                    const viewport = scroller.getBoundingClientRect();
                    const heading = Array.from(document.querySelectorAll('.cm-line'))
                      .find(line => line.textContent === headingText || line.textContent === visibleHeading);
                    const shell = document.querySelector('[data-scholium-source-from="' + imageFrom + '"]');
                    const image = shell?.querySelector('img');
                    const visible = element => {
                      const rect = element?.getBoundingClientRect();
                      return !!rect && rect.width > 0 && rect.height > 0
                        && rect.bottom > viewport.top && rect.top < viewport.bottom
                        && rect.right > viewport.left && rect.left < viewport.right;
                    };
                    return {headingVisible: visible(heading), imageVisible: visible(image),
                      imageDecoded: !!image && image.complete && image.naturalWidth === 1600 && image.naturalHeight === 1200,
                      imageSourceTo: shell?.getAttribute('data-scholium-source-to')};
                    """,
                    arguments: ["headingText": heading, "visibleHeading": "Large image 0001", "imageFrom": imageRange.location],
                    in: nil, contentWorld: .page) as? [String: Any]
            let observed = try #require(geometry)
            #expect(observed["headingVisible"] as? Bool == true, "Fractional restoration must retain the source heading: \(observed)")
            #expect(observed["imageVisible"] as? Bool == true)
            #expect(observed["imageDecoded"] as? Bool == true)
            #expect(observed["imageSourceTo"] as? String == String(NSMaxRange(imageRange)))
            await harness.closeAndDrain()
        } catch {
            gate.release()
            await harness.closeAndDrain()
            throw error
        }
    }

    private static func galleryPreparationSource(small: String, large: String) -> String {
        var source = """
            ---
            summary: Synthetic nonprivate stress fixture; no scholarly claims.
            keywords: [stress-fixture, 压力测试, stress-800005]
            stress_sequence: 800005
            fixture_only: true
            ---

            # Stress Image Gallery

            全部内容为合成测试材料，不是引文、文献分析或研究结论。

            ## Distinct local images


            """
        for index in 0..<240 {
            let number = String(format: "%04d", index)
            source += "### Image \(number)\n\n![Synthetic image \(number)](\(small))\n\n"
        }
        source += "## Larger local images\n\n"
        for index in 0..<4 {
            let number = String(format: "%04d", index)
            source += "### Large image \(number)\n\n![Synthetic image \(number)](\(large))\n\n"
        }
        return source
    }

    private static func galleryPreparationPNG(width: Int, height: Int) throws -> RenderedMarkdownImage {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(bitmap.bitmapData).initialize(repeating: 180, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return try RenderedMarkdownImage(
            data: #require(bitmap.representation(using: .png, properties: [:])), mimeType: "image/png")
    }
}

@MainActor
private final class GalleryPreparationImageGate {
    private let images: [String: RenderedMarkdownImage]
    private var released = false
    private var replies: [CheckedContinuation<[String: RenderedMarkdownImage], Never>] = []
    private(set) var hasRequest = false

    init(images: [String: RenderedMarkdownImage]) { self.images = images }

    func query(_ source: String) async -> [String: RenderedMarkdownImage] {
        hasRequest = true
        if released { return images }
        return await withCheckedContinuation { replies.append($0) }
    }

    func release() {
        released = true
        let pending = replies
        replies.removeAll()
        for reply in pending { reply.resume(returning: images) }
    }
}

@MainActor
private final class GalleryPreparationBridgeProbe: MarkdownEditorBridgeDispatching {
    private let production = WKWebViewMarkdownEditorBridgeDispatcher()
    private(set) var initialized: MarkdownEditorCommandResult?
    private(set) var initialImageCount: Int?
    private(set) var catalogImageCounts: [Int] = []
    private(set) var preparationRequestCount = 0
    private(set) var preparationDeadlineMilliseconds: [Int64] = []

    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
        if case .completePreparation = request.operation {
            preparationRequestCount += 1
            preparationDeadlineMilliseconds.append(request.expiresAt - Int64(Date().timeIntervalSince1970 * 1_000))
        }
        let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
        switch request.operation {
        case .initialize(_, _, _, _, _, let presentation):
            initialImageCount = presentation.imageResources.count
            initialized = try JSONDecoder().decode(
                MarkdownEditorCommandResult.self,
                from: JSONSerialization.data(withJSONObject: #require(result)))
        case .setPresentation(let presentation) where !presentation.imageResources.isEmpty:
            catalogImageCounts.append(presentation.imageResources.count)
        default: break
        }
        return result
    }
}
