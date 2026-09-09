import Foundation
import ImageIO
import PDFKit
import ScholiumContracts
import UniformTypeIdentifiers

/// Stateless extraction from one verified file snapshot. No file access or material archive.
public enum AgentAttachmentContentReader {
    public static func read(_ data: Data, filename: String, request: AgentAttachmentRead) throws -> AgentAttachmentContent {
        func invalid(_ message: String) -> ScholiumMCPFailure {
            .init(code: .invalidRequest, message: message, recovery: "Choose an available text/image file or one valid PDF page and read its exact current revision.")
        }
        guard data.count <= 20 * 1_024 * 1_024, request.startUTF8 >= 0, (1...65_536).contains(request.maximumUTF8),
              request.startUTF8 == 0 || request.expectedFingerprint != nil else { throw invalid("The attachment read or continuation exceeds its permitted bounds.") }
        let fingerprint = DocumentFingerprint(data: data)
        if let expected = request.expectedFingerprint, expected != fingerprint {
            throw AgentCollaborationError.staleRevision(expected: expected, current: fingerprint)
        }
        let type = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
        let isPDF = type == .pdf
        var pdf: PDFDocument?
        var page: PDFPage?
        if isPDF {
            guard let document = PDFDocument(data: data) else { throw invalid("The PDF is unreadable.") }
            guard !document.isLocked else { throw invalid("The PDF is locked.") }
            guard let number = request.page, (1...max(1, document.pageCount)).contains(number), let selected = document.page(at: number - 1) else {
                throw invalid("Choose one existing one-based PDF page.")
            }
            pdf = document; page = selected
        } else if request.page != nil { throw invalid("A page locator applies only to a PDF.") }
        switch request.mode {
        case .text:
            let source: Data
            if let page { source = Data((page.string ?? "").utf8) }
            else {
                guard type?.conforms(to: .text) == true || URL(fileURLWithPath: filename).pathExtension.lowercased() == "md" else {
                    throw invalid("This attachment has no supported text extraction; image mode does not perform OCR.")
                }
                source = data
            }
            guard NoteDocument.decodeUTF8PreservingBOM(source) != nil, request.startUTF8 <= source.count else {
                throw invalid("The text is not valid UTF-8 or the requested offset is outside its coverage.")
            }
            guard request.startUTF8 == source.count || source[request.startUTF8] & 0xC0 != 0x80 else { throw invalid("The text offset splits a UTF-8 scalar.") }
            var end = request.startUTF8 + min(request.maximumUTF8, source.count - request.startUTF8)
            while end < source.count && end > request.startUTF8 && source[end] & 0xC0 == 0x80 { end -= 1 }
            guard end > request.startUTF8 || end == source.count else { throw invalid("The requested byte limit cannot contain the next UTF-8 scalar.") }
            guard let text = NoteDocument.decodeUTF8PreservingBOM(source.subdata(in: request.startUTF8..<end)) else { throw invalid("The text slice is unreadable.") }
            return .init(filename: filename, fingerprint: fingerprint, kind: isPDF ? "pdf_text" : "utf8_text", page: request.page,
                         totalPages: pdf?.pageCount, text: text, startUTF8: request.startUTF8, endUTF8: end, totalUTF8: source.count)
        case .image:
            guard request.startUTF8 == 0 else { throw invalid("Image rendering has no text offset.") }
            var image: CGImage
            if let page {
                let bounds = page.bounds(for: .cropBox)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
                      let rendered = page.thumbnail(of: CGSize(width: 1_024, height: 1_024), for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil),
                      rendered.width <= 1_024, rendered.height <= 1_024 else { throw invalid("The PDF page cannot be rendered within image bounds.") }
                image = rendered
            } else {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                      width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 40_000_000,
                      let rendered = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1_024,
                          kCGImageSourceShouldCache: false] as CFDictionary) else { throw invalid("The image is unreadable, multi-frame or outside supported image bounds.") }
                image = rendered
            }
            var bytes = Data()
            while true {
                let encoded = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { throw invalid("Image encoding is unavailable.") }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw invalid("Image encoding failed.") }
                bytes = encoded as Data
                if bytes.count <= 512 * 1_024 { break }
                try Task.checkCancellation()
                let edge = max(image.width, image.height) / 2
                guard edge > 0, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let reduced = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceShouldCache: false] as CFDictionary) else {
                    throw invalid("The rendered image cannot fit the bounded response size.")
                }
                image = reduced
            }
            return .init(filename: filename, fingerprint: fingerprint, kind: isPDF ? "pdf_page_image" : "image", page: request.page,
                         totalPages: pdf?.pageCount, imagePNG: bytes, pixelWidth: image.width, pixelHeight: image.height)
        }
    }
}
