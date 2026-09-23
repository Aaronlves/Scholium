import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumEditor

@Suite("Installed document fonts")
struct DocumentAppearanceFontTests {
    @Test("Installed families reach shared HTML typography with safe CSS quoting")
    func installedFamiliesReachTypography() {
        var settings = DocumentAppearanceSettings()
        settings.body.fontFamily = .init(rawValue: "Helvetica Neue")
        settings.headings.fontFamily = .init(rawValue: "Font\";}</style>中文")
        let css = DocumentAppearanceStyles.css(for: settings)
        let transport = DocumentAppearanceStyles.documentTypographyTransportDeclarations(for: settings)
        #expect(css.contains("font-family: \"Helvetica Neue\","))
        #expect(transport.contains("--scholium-document-body-font-family: \"Helvetica Neue\","))
        let escaped = #""Font\22 \3b \7d \3c \2f style\3e \4e2d \6587 ""#
        #expect(css.contains("font-family: \(escaped),"))
        #expect(transport.contains("--scholium-document-heading-font-family: \(escaped),"))
        #expect(!css.contains("</style>"))
        settings.headings.fontFamily = .body
        let inherited = DocumentAppearanceStyles.documentTypographyTransportDeclarations(for: settings)
        #expect(inherited.contains("--scholium-document-heading-font-family: \"Helvetica Neue\","))
    }

    @Test("Native heading typography preserves hidden syntax and technical fonts")
    @MainActor
    func nativeHeadingPreservesPresentationBoundaries() throws {
        var settings = DocumentAppearanceSettings()
        settings.body.fontSizePoints = 12
        settings.headings.level2.scale = 2
        let source = "## Title `code`"
        let text = source as NSString
        let attributed = NSMutableAttributedString(string: source, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let hidden = NSRange(location: 0, length: 3)
        attributed.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: hidden)
        let code = text.range(of: "code")
        let codeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        attributed.addAttribute(.font, value: codeFont, range: code)
        let block = Block(content: source, range: NSRange(location: 0, length: text.length), kind: .heading(level: 2))
        let result = NativeDocumentStyle(settings: settings, scale: 1).style(block, attributed: attributed)
        #expect(result.string == source)
        #expect((result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 0.1)
        #expect((result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.alphaComponent == 0)
        #expect((result.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize == 24)
        #expect((result.attribute(.font, at: code.location, effectiveRange: nil) as? NSFont) == codeFont)
    }

    @Test("Native callout headings retain the configured heading hierarchy")
    @MainActor
    func nativeNestedHeadingKeepsItsRole() throws {
        var settings = DocumentAppearanceSettings()
        settings.body.fontSizePoints = 12
        settings.headings.level2.scale = 2
        let source = "> [!note]\n> ## Heading\n> Body"
        let text = source as NSString
        _ = NSApplication.shared
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        let attributed = editor.styleBlock(source, cursorPosition: nil)
        let block = Block(content: source, range: NSRange(location: 0, length: text.length), kind: .quoteRun(isCallout: true))
        let result = NativeDocumentStyle(settings: settings, scale: 1).style(block, attributed: attributed)
        #expect(result.string == source)
        #expect((result.attribute(.font, at: text.range(of: "Heading").location, effectiveRange: nil) as? NSFont)?.pointSize == 24)
    }

}
