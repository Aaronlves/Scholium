import Foundation
import ScholiumContracts
import Testing

@MainActor
@Suite("Exact Review renderer lifecycle diagnostic", .serialized)
struct ReviewRendererLifecycleDiagnosticTests {
    @Test(
        "Separate exact foreground source parsing and HTML rendering",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_REVIEW_RENDERER"] == "1"))
    func exactForegroundSource() throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath().path + "/"
        let input = URL(fileURLWithPath: try #require(environment["SCHOLIUM_REVIEW_RENDER_SOURCE"])).resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: try #require(environment["SCHOLIUM_REVIEW_RENDER_RESULT"])).resolvingSymlinksInPath()
        try #require(input.path.hasPrefix(build) && output.path.hasPrefix(build))
        let bytes = try Data(contentsOf: input)
        let source = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: source)
        var parseTimes: [Double] = []
        var renderTimes: [Double] = []
        var htmlDigest: String?
        var objectDigest: String?
        for _ in 0..<3 {
            let parseStarted = ContinuousClock.now
            let semantic = MarkdownSemanticDocument(parsing: document)
            parseTimes.append(milliseconds(parseStarted.duration(to: .now)))
            let renderStarted = ContinuousClock.now
            let rendered = SafeMarkdownRenderer.render(document, semantic: semantic)
            renderTimes.append(milliseconds(renderStarted.duration(to: .now)))
            let nextHTML = DocumentFingerprint(data: Data(rendered.htmlBody.utf8)).sha256
            let objectMaterial = rendered.objects.map {
                ["id": $0.id, "kind": $0.kind.rawValue, "copy_text": $0.copyText, "html": $0.html]
            }
            let nextObjects = DocumentFingerprint(data: try JSONSerialization.data(withJSONObject: objectMaterial, options: [.sortedKeys])).sha256
            if let htmlDigest { #expect(nextHTML == htmlDigest) }
            if let objectDigest { #expect(nextObjects == objectDigest) }
            htmlDigest = nextHTML
            objectDigest = nextObjects
            #expect(rendered.semanticDocument == semantic)
            #expect(document.sourceBytes == bytes)
        }
        #expect(try Data(contentsOf: input) == bytes)
        let record: [String: Any] = [
            "source_sha256": DocumentFingerprint(data: bytes).sha256, "source_bytes": bytes.count,
            "parse_ms": parseTimes, "render_ms": renderTimes,
            "html_sha256": try #require(htmlDigest), "objects_sha256": try #require(objectDigest),
            "boundary": "Synchronous semantic parse and complete HTML rendering, separately; three samples; excludes IO, WebKit and display",
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("ReviewRendererLifecycle parse_ms=\(parseTimes), render_ms=\(renderTimes)")
    }

    @Test(
        "Measure both supported image delivery contexts on the real synthetic gallery",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_REVIEW_IMAGES"] == "1"))
    func galleryImageDelivery() throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath().path + "/"
        let input = URL(fileURLWithPath: try #require(environment["SCHOLIUM_REVIEW_IMAGE_SOURCE"])).resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: try #require(environment["SCHOLIUM_REVIEW_IMAGE_RESULT"])).resolvingSymlinksInPath()
        try #require(input.path.hasPrefix(build) && output.path.hasPrefix(build))
        let bytes = try Data(contentsOf: input)
        let source = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
        let document = NoteDocument(relativePath: "Stress/Stress Image Gallery.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let expression = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^\)]+)\)"#)
        let body = source as NSString
        var images: [String: RenderedMarkdownImage] = [:]
        for match in expression.matches(in: source, range: NSRange(location: 0, length: body.length)) {
            let target = body.substring(with: match.range(at: 1))
            let imageURL = input.deletingLastPathComponent().appendingPathComponent(target).resolvingSymlinksInPath()
            try #require(imageURL.path.hasPrefix(build))
            images[target] = try RenderedMarkdownImage(data: Data(contentsOf: imageURL), mimeType: "image/png")
        }
        try #require(images.count == 52)
        var samples: [[String: Any]] = []
        for delivery in [SafeMarkdownRenderer.ImageDelivery.inlineData, .resourceCatalog] {
            var durations: [Double] = []
            var html = ""
            for _ in 0..<3 {
                let started = ContinuousClock.now
                html = SafeMarkdownRenderer.render(document, semantic: semantic, embeddedImages: images, imageDelivery: delivery).htmlBody
                durations.append(milliseconds(started.duration(to: .now)))
                #expect(html.components(separatedBy: "<img ").count - 1 == images.count)
            }
            let catalog = delivery == .resourceCatalog
            #expect(html.contains("base64,") != catalog)
            #expect(html.contains("data-scholium-image-resource=") == catalog)
            if catalog { #expect(html.utf16.count < 100_000) }
            samples.append([
                "delivery": catalog ? "resourceCatalog" : "inlineData", "render_ms": durations,
                "html_utf8_bytes": html.utf8.count, "html_utf16_units": html.utf16.count,
            ])
        }
        #expect(document.sourceBytes == bytes)
        #expect(try Data(contentsOf: input) == bytes)
        let record: [String: Any] = [
            "source_sha256": DocumentFingerprint(data: bytes).sha256, "source_bytes": bytes.count,
            "image_count": images.count, "image_bytes": images.values.reduce(0) { $0 + $1.data.count },
            "samples": samples,
            "boundary":
                "Three synchronous renders per supported output context, same prepared semantic source and 52 actual synthetic PNGs; excludes IO, catalog encoding, WebKit and display",
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("ReviewImageDelivery \(samples)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
