import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ScholiumApplication
import ScholiumContracts
import Testing
import UniformTypeIdentifiers

@Suite("Local research material snapshots")
struct AgentChatMaterialStoreTests {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/agent-chat-evolution/local-material-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Clipboard TIFF becomes oriented PNG while retaining its captured encoding")
    func clipboardImage() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentChatMaterialStore(root: root.appendingPathComponent("Materials"))
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let writer = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(writer))
        let material = try await store.stageImageCapture(data as Data, origin: .clipboard)
        #expect(material.source == .imageCapture(.clipboard) && material.kind == .image && material.issue == nil)
        #expect(material.capturedFingerprint == DocumentFingerprint(data: data as Data))
        let captured = try #require(material.capturedFileName)
        let capturedURL = root.appendingPathComponent("Materials").appendingPathComponent(captured)
        #expect(try Data(contentsOf: capturedURL) == data as Data)
        let url = try await store.validatedURL(for: material)
        let rendered = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(rendered, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 3)
        #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 2)
        let png = try Data(contentsOf: url)
        let direct = try await store.stageImageCapture(png, origin: .drop)
        #expect(direct.source == .imageCapture(.drop))
        #expect(direct.capturedFileName == nil && direct.fingerprint == DocumentFingerprint(data: png))
        let directURL = try await store.validatedURL(for: direct)
        #expect(try Data(contentsOf: directURL) == png)
        try await store.discard(material)
        #expect(!FileManager.default.fileExists(atPath: capturedURL.path) && !FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: directURL.path))
    }

    @Test("Staged UTF-8 stays exact after the original changes and corrupted copies cannot send")
    func exactText() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.md")
        let bytes = Data("\u{FEFF}---\r\nunknown: 'unchanged'\r\n---\r\n源文 **literal** 😀\r\n".utf8)
        try bytes.write(to: file)
        let store = AgentChatMaterialStore(root: root.appendingPathComponent("Materials"))
        let material = try await store.stage(file)
        #expect(material.issue == nil && material.kind == .text && Data(material.text.utf8) == bytes)
        #expect(material.fingerprint == DocumentFingerprint(data: bytes))
        try Data("externally replaced".utf8).write(to: file)
        let copy = try await store.validatedURL(for: material)
        #expect(try Data(contentsOf: copy) == bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
        try Data("altered staged file".utf8).write(to: copy)
        await #expect(throws: CocoaError.self) { try await store.validatedURL(for: material) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "externally replaced")
    }

    @Test("PDF extraction retains page indices and empty-page limits")
    func pdfPages() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentChatMaterialStore(root: root.appendingPathComponent("Materials"))
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let text = NSAttributedString(string: "Synthetic source passage.", attributes: [.init(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 20, y: 240)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let file = root.appendingPathComponent("paper.pdf")
        try (data as Data).write(to: file)
        let material = try await store.stage(file)
        #expect(material.kind == .pdf && material.issue == nil)
        #expect(material.pages.map(\.number) == [1, 2] && material.pagesWithoutText == [2])
        #expect(material.pages.first?.text.contains("Synthetic source passage.") == true)
        #expect(material.text.isEmpty)
        #expect(try await store.validatedURL(for: material).pathExtension == "pdf")
        let rendered = try await store.renderPDFPages("2, 1", from: material)
        #expect(rendered.id != material.id && rendered.fingerprint == material.fingerprint)
        #expect(rendered.pages.isEmpty && rendered.pageImages.map(\.number) == [1, 2] && rendered.requiresImageInput)
        let images = try await store.validatedPageImageURLs(for: rendered)
        #expect(images.count == 2)
        if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1" {
            let output = root.deletingLastPathComponent().appendingPathComponent("renders")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data(contentsOf: images[0]).write(to: output.appendingPathComponent("pdf-rendered-page.png"))
        }
        for image in images { #expect(try Data(contentsOf: image).starts(with: [137, 80, 78, 71, 13, 10, 26, 10])) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: images[0].path)
        try Data("changed page image".utf8).write(to: images[0])
        await #expect(throws: CocoaError.self) { try await store.validatedPageImageURLs(for: rendered) }
        try await store.discard(rendered)
        #expect(images.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try Data(contentsOf: file) == data as Data)
        #expect(try await store.validatedURL(for: material).pathExtension == "pdf")
    }

    @Test("Page selection rejects invalid ranges and never silently truncates a request")
    func pageSelection() throws {
        #expect(try AgentChatPDFPageSelection.parse(" 1–3, 5, 2 ", pageCount: 12) == [1, 2, 3, 5])
        #expect(try AgentChatPDFPageSelection.parse("1–3、5，8", pageCount: 12) == [1, 2, 3, 5, 8])
        for value in ["", "0", "-1", "3-1", "1,", "1,,2", "13", "1-13", "all", "1/2"] {
            #expect(throws: AgentChatPDFPageSelectionFailure.self) { try AgentChatPDFPageSelection.parse(value, pageCount: 12) }
        }
        #expect(throws: AgentChatPDFPageSelectionFailure.self) { try AgentChatPDFPageSelection.parse("1-21", pageCount: 40) }
    }

    @Test("Unsupported, missing and oversized inputs remain visible failures")
    func failures() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentChatMaterialStore(root: root.appendingPathComponent("Materials"))
        let missing = try await store.stage(root.appendingPathComponent("missing.pdf"))
        #expect(missing.issue == .unreadable && missing.storedFileName == nil)
        let invalid = root.appendingPathComponent("invalid.pdf")
        try Data("not a PDF".utf8).write(to: invalid)
        let retained = try await store.stage(invalid)
        #expect(retained.issue == .unreadable && retained.storedFileName != nil)
        let large = root.appendingPathComponent("large.txt")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 21 * 1_024 * 1_024)
        try handle.close()
        let oversized = try await store.stage(large)
        #expect(oversized.issue == .tooLarge && oversized.storedFileName == nil)
    }
}
