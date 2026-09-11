import CoreGraphics
import Foundation
import ImageIO
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded attachment extraction")
struct AgentAttachmentContentReaderTests {
    @Test("Detailed images are reduced to fit the response while keeping original fingerprints")
    func boundedImageDerivative() throws {
        var seed: UInt64 = 0x12345678
        var pixels = Data(count: 1_024 * 1_024 * 4)
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in bytes.indices {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                bytes[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 32)
            }
        }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(
            CGImage(
                width: 1_024, height: 1_024, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 4_096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        #expect(encoded.length > 512 * 1_024)
        let result = try AgentAttachmentContentReader.read(encoded as Data, filename: "Detailed.png", request: .init(mode: .image))
        #expect(try #require(result.imagePNG?.count) <= 512 * 1_024)
        #expect(try #require(result.pixelWidth) < 1_024)
        #expect(result.fingerprint == DocumentFingerprint(data: encoded as Data) && result.text == nil)
    }

    @Test("Text extraction rejects invalid encoding, split scalars and unbound continuations")
    func invalidTextSlices() throws {
        let bytes = Data("α研究".utf8)
        let fingerprint = DocumentFingerprint(data: bytes)
        #expect(throws: ScholiumMCPFailure.self) { try AgentAttachmentContentReader.read(Data([255]), filename: "Source.txt", request: .init(mode: .text)) }
        #expect(throws: ScholiumMCPFailure.self) {
            try AgentAttachmentContentReader.read(bytes, filename: "Source.txt", request: .init(mode: .text, maximumUTF8: 1))
        }
        #expect(throws: ScholiumMCPFailure.self) {
            try AgentAttachmentContentReader.read(bytes, filename: "Source.txt", request: .init(mode: .text, startUTF8: 1, expectedFingerprint: fingerprint))
        }
        #expect(throws: ScholiumMCPFailure.self) {
            try AgentAttachmentContentReader.read(bytes, filename: "Source.txt", request: .init(mode: .text, startUTF8: 2))
        }
        let empty = try AgentAttachmentContentReader.read(
            bytes, filename: "Source.txt", request: .init(mode: .text, startUTF8: bytes.count, expectedFingerprint: fingerprint))
        #expect(empty.text == "" && empty.endUTF8 == bytes.count && empty.totalUTF8 == bytes.count)
    }

    @Test("A PDF with no text returns empty extraction and can separately render its selected page")
    func blankPDF() throws {
        let bytes = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let data = bytes as Data
        let text = try AgentAttachmentContentReader.read(data, filename: "Blank.pdf", request: .init(mode: .text, page: 1))
        #expect(text.kind == "pdf_text" && text.text == "" && text.totalUTF8 == 0 && text.imagePNG == nil)
        let image = try AgentAttachmentContentReader.read(data, filename: "Blank.pdf", request: .init(mode: .image, page: 1))
        #expect(image.kind == "pdf_page_image" && image.text == nil && image.imagePNG != nil)
        #expect(throws: ScholiumMCPFailure.self) { try AgentAttachmentContentReader.read(data, filename: "Blank.pdf", request: .init(mode: .text, page: 2)) }
    }
}
