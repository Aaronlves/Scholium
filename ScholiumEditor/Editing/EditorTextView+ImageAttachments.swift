// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit
import UniformTypeIdentifiers

// Paste/drop classification is local and side-effect free. The application
// alone owns attachment authorization, storage and source insertion.
extension EditorTextView {
    static func pasteboardHasImageContent(_ pasteboard: NSPasteboard) -> Bool {
        !Set(pasteboard.types ?? []).isDisjoint(with: [.png, .tiff, .fileURL, .URL])
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEditable, viewMode != .reading, !isComposingSource else { return [] }
        if Self.pasteboardHasImageContent(sender.draggingPasteboard) {
            return onNativePasteboard == nil ? [] : .copy
        }
        return super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEditable, viewMode != .reading, !isComposingSource else { return [] }
        if Self.pasteboardHasImageContent(sender.draggingPasteboard) {
            return onNativePasteboard == nil ? [] : .copy
        }
        return super.draggingUpdated(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable, viewMode != .reading, !isComposingSource else { return false }
        let pasteboard = sender.draggingPasteboard
        if Self.imageContentKind(of: pasteboard) != nil {
            guard let onNativePasteboard else { return false }
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            return onNativePasteboard(pasteboard)
        }
        return super.performDragOperation(sender)
    }

    enum ImageContentKind {
        case files([URL])
        case data(Data)  // PNG-encoded
        case remoteURL(URL)
    }

    /// Classifies the pasteboard's image content without mutating anything.
    /// Returns nil for non-image content (text, non-image files), which the
    /// caller then routes to the default paste/drop behavior.
    ///
    /// Order: image *files* first; then a web image's *URL* — a browser drag
    /// carries both a URL and a TIFF of the picture, and the documented
    /// behavior is to insert the URL as-is, not to copy the browser's bitmap
    /// into assets; then raw *bitmap* data (screenshots, copied images).
    /// A pasteboard carrying files but no image among them is a file gesture
    /// (e.g. a Finder copy of a .zip), never a bitmap gesture — it returns
    /// nil rather than falling through: Finder puts the file's *icon* on the
    /// pasteboard, and attaching that would be wrong.
    static func imageContentKind(of pasteboard: NSPasteboard) -> ImageContentKind? {
        let fileURLs =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let imageFiles = fileURLs.filter(isImageFile)
        if !imageFiles.isEmpty { return .files(imageFiles) }
        if !fileURLs.isEmpty { return nil }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            let remote = urls.first(where: {
                ($0.scheme == "https" || $0.scheme == "http") && isImagePath($0.path)
            })
        {
            return .remoteURL(remote)
        }
        if let png = pngData(from: pasteboard) { return .data(png) }
        return nil
    }

    @discardableResult
    func handleImageNewline(_ sel: NSRange) -> Bool {
        guard sel.length == 0,
            let blockIdx = blockIndexForRawOffset(sel.location),
            blockIdx < blocks.count
        else { return false }
        let base = blocks[blockIdx].range.location
        let inBlock = sel.location - base
        for span in SyntaxHighlighter.parse(
            blocks[blockIdx].content,
            features: markdownFeatures)
        {
            guard case .image = span.kind else { continue }
            let full = span.fullRange
            guard inBlock > full.location, inBlock < full.upperBound else { continue }
            insertText(
                "\n",
                replacementRange: NSRange(
                    location: base + full.upperBound,
                    length: 0))
            return true
        }
        return false
    }

    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), NSImage(data: png) != nil {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
            let rep = NSBitmapImageRep(data: tiff)
        {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    /// `nonisolated`: a pure UTType query, and it is passed as an unapplied
    /// reference to `filter` — under older Swift 6 toolchains an actor-isolated
    /// reference there both errors and makes the rethrows call "can throw".
    nonisolated static func isImageFile(_ url: URL) -> Bool {
        isImagePath(url.path)
    }

    private nonisolated static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty else { return false }
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }
}
