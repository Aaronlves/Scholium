import AppKit

/// The bounded set of standard SF Symbols shared by native Scholium controls
/// and the app-private WebKit document surfaces. This is not a second icon
/// library: each value remains the direct system symbol name used by AppKit or
/// SwiftUI, while `ScholiumWebSymbolAssets` is only a transport adapter for
/// DOM that cannot resolve `NSImage(systemSymbolName:)` itself.
enum ScholiumSystemSymbol: String, CaseIterable, Sendable {
    case textFormat = "textformat"
    case bold
    case italic
    case strikethrough
    case highlighter
    case link
    case ellipsis
    case chevronDown = "chevron.down"
    case checkmark
    case curlyBraces = "curlybraces"
    case curlyBracesSquare = "curlybraces.square"
    case eyeSlash = "eye.slash"
    case listBullet = "list.bullet"
    case listNumber = "list.number"
    case checklist
    case textQuote = "text.quote"
    case textBubble = "text.bubble"
    case docText = "doc.text"
    case calendar
    case function
    case flowchart
    case tablecells
    case textFormatSuperscript = "textformat.superscript"
    case minus
    case paperclip

    var systemName: String { rawValue }

    var webToken: String {
        rawValue.replacingOccurrences(of: ".", with: "-")
    }
}

@MainActor
enum ScholiumWebSymbolAssets {
    private static let rasterScale: CGFloat = 4
    private static let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 16,
        weight: .regular
    )

    private static let dataURIs = Dictionary(
        uniqueKeysWithValues: ScholiumSystemSymbol.allCases.map { symbol in
            (symbol, renderDataURI(for: symbol))
        }
    )

    static func dataURI(for symbol: ScholiumSystemSymbol) -> String {
        dataURIs[symbol] ?? ""
    }

    /// CSS variables let CodeMirror keep geometry, focus, and interaction
    /// ownership while displaying the same system symbols as native controls.
    static let cssVariables: String = {
        let declarations = ScholiumSystemSymbol.allCases.compactMap { symbol -> String? in
            let uri = dataURI(for: symbol)
            guard !uri.isEmpty else { return nil }
            return "  --scholium-system-symbol-\(symbol.webToken): url(\"\(uri)\");"
        }
        return ([":root {"] + declarations + ["}"]).joined(separator: "\n")
    }()

    private static func renderDataURI(for symbol: ScholiumSystemSymbol) -> String {
        guard let image = NSImage(
            systemSymbolName: symbol.systemName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration),
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(image.size.width * rasterScale)),
            pixelsHigh: Int(ceil(image.size.height * rasterScale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return ""
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        image.draw(
            in: NSRect(
                x: 0,
                y: 0,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh
            ),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard
        let data = bitmap.representation(using: .png, properties: [:]) else {
            return ""
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}
