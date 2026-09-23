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

    @Test("Default document rhythm and native boxes share the approved appearance")
    @MainActor
    func defaultRhythmAndRoundedBoxes() throws {
        let settings = DocumentAppearanceSettings.defaultSettings
        #expect(settings.body.fontSizePoints == 14)
        #expect(settings.body.fontSizePoints > Double(NSFont.systemFontSize))
        #expect(settings.source.fontSizePoints == 12.5)
        #expect(settings.headings.level1.scale > settings.headings.level2.scale)
        #expect(settings.headings.level2.scale > settings.headings.level3.scale)
        _ = NSApplication.shared
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        editor.applyNativeAppearance(
            NativeDocumentStyle(settings: settings, scale: 1).configuration(identifier: 1))

        func check(_ source: String, radius: CGFloat) throws {
            let styled = editor.styleBlock(source, cursorPosition: nil)
            #expect(styled.string == source)
            let ns = source as NSString
            let firstLine = ns.lineRange(for: NSRange(location: 0, length: 0))
            let middleLine = ns.lineRange(for: NSRange(location: firstLine.upperBound, length: 0))
            let lastLine = ns.lineRange(for: NSRange(location: middleLine.upperBound, length: 0))
            let first = try #require(styled.attribute(.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration)
            let middle = try #require(styled.attribute(.blockDecoration, at: middleLine.location, effectiveRange: nil) as? BlockDecoration)
            let last = try #require(styled.attribute(.blockDecoration, at: lastLine.location, effectiveRange: nil) as? BlockDecoration)
            #expect(first.cornerRadius == radius && first.roundsTop && !first.roundsBottom)
            #expect(middle.cornerRadius == radius && !middle.roundsTop && !middle.roundsBottom)
            #expect(last.cornerRadius == radius && !last.roundsTop && last.roundsBottom)
        }
        try check("```swift\nlet x = 1\n```", radius: ScholiumCornerRole.documentCodeBlock.radius)
        try check("> [!note] Title\n> Body\n> End", radius: ScholiumCornerRole.documentCalloutSurface.radius)
    }

    @Test("Callout keeps its semantic surface and default title while editing its body")
    @MainActor
    func calloutProjectionSurvivesCaretActivation() throws {
        _ = NSApplication.shared
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        editor.applyNativeAppearance(
            NativeDocumentStyle(settings: .defaultSettings, scale: 1).configuration(identifier: 1))
        let source = "> [!note]\n> Body"
        let ns = source as NSString
        let marker = ns.range(of: "[!note]").location
        let body = ns.range(of: "Body").location

        let inactive = editor.styleBlock(source, cursorPosition: nil)
        #expect(inactive.string == source)
        #expect(inactive.attribute(.fragmentOverlay, at: marker, effectiveRange: nil) != nil)

        let activeBody = editor.styleBlock(source, cursorPosition: body)
        #expect(activeBody.string == source)
        #expect(activeBody.attribute(.fragmentOverlay, at: marker, effectiveRange: nil) != nil)
        let decoration = try #require(activeBody.attribute(.blockDecoration, at: body, effectiveRange: nil) as? BlockDecoration)
        #expect(decoration.roundsBottom)
        #expect(decoration.cornerRadius == ScholiumCornerRole.documentCalloutSurface.radius)

        let activeHeader = editor.styleBlock(source, cursorPosition: marker)
        #expect(activeHeader.string == source)
        #expect(activeHeader.attribute(.fragmentOverlay, at: marker, effectiveRange: nil) == nil)
        #expect(activeHeader.attribute(.editorSyntaxInk, at: marker, effectiveRange: nil) != nil)
        #expect(activeHeader.attribute(.blockDecoration, at: marker, effectiveRange: nil) != nil)
    }

    @Test("Callout source gutter preserves the content column and neutral surface")
    @MainActor
    func calloutContentDoesNotMoveWhenSyntaxAppears() throws {
        _ = NSApplication.shared
        let settings = DocumentAppearanceSettings.defaultSettings
        let style = NativeDocumentStyle(settings: settings, scale: 1)
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        editor.applyNativeAppearance(style.configuration(identifier: 2))
        let source = "> [!note] 提示\n> 中文 Body"
        let ns = source as NSString
        let prefix = ns.range(of: "> 中文")
        let body = ns.range(of: "Body")
        let block = Block(
            content: source,
            range: NSRange(location: 0, length: ns.length),
            kind: .quoteRun(isCallout: true))
        func presented(_ cursor: Int?) -> NSAttributedString {
            style.style(block, attributed: editor.styleBlock(source, cursorPosition: cursor))
        }
        let resting = presented(nil)
        let editing = presented(body.location)
        #expect(resting.string == source && editing.string == source)
        let restingPrefixFont = try #require(resting.attribute(.font, at: prefix.location, effectiveRange: nil) as? NSFont)
        let editingPrefixFont = try #require(editing.attribute(.font, at: prefix.location, effectiveRange: nil) as? NSFont)
        #expect(restingPrefixFont.pointSize == editingPrefixFont.pointSize)
        #expect(restingPrefixFont.pointSize > 1)
        let restingParagraph = try #require(resting.attribute(.paragraphStyle, at: body.location, effectiveRange: nil) as? NSParagraphStyle)
        let editingParagraph = try #require(editing.attribute(.paragraphStyle, at: body.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(restingParagraph.firstLineHeadIndent == editingParagraph.firstLineHeadIndent)
        #expect(restingParagraph.headIndent == editingParagraph.headIndent)
        let markerWidth = ("> " as NSString).size(withAttributes: [.font: restingPrefixFont]).width
        let expectedInset =
            CGFloat(settings.body.fontSizePoints)
            * CGFloat(
                settings.callout(.folded).resolvedPaddingInlineEm
                    + (settings.callout(.folded).contentIndentEm ?? 0))
        #expect(abs(restingParagraph.firstLineHeadIndent + markerWidth - expectedInset) < 1)

        let headerDecoration = try #require(resting.attribute(.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration)
        if case .box(_, _, _, _, let headerGap) = headerDecoration.kind {
            #expect(
                headerGap == CGFloat(settings.body.fontSizePoints)
                    * CGFloat(settings.callout(.folded).resolvedHeaderBodyGapEm))
        } else {
            Issue.record("The Callout header must carry a continuous box fill")
        }

        let appearance = style.configuration(identifier: 3)
        let callout = try #require(appearance.calloutStyles["note"])
        #expect(callout.explicitBackgroundHex(dark: false) != nil)
        #expect(callout.explicitBackgroundHex(dark: false) != callout.colorHex)
    }

    @Test("Selecting a Callout marker reveals only selected source syntax")
    @MainActor
    func calloutSelectionRevealsSource() throws {
        _ = NSApplication.shared
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        let source = "> [!WARNING]\n> Body\n> More"
        let ns = source as NSString
        let header = ns.range(of: "> [!WARNING]")
        let firstPrefix = ns.range(of: "> Body")
        let body = ns.range(of: "Body")
        let secondPrefix = ns.range(of: "> More")

        let projected = editor.styleBlock(source)
        #expect(projected.attribute(.fragmentOverlay, at: header.location + 2, effectiveRange: nil) != nil)

        let selectedHeader = editor.styleBlock(source, selectionRange: header)
        #expect(selectedHeader.string == source)
        #expect(selectedHeader.attribute(.fragmentOverlay, at: header.location + 2, effectiveRange: nil) == nil)
        #expect(selectedHeader.attribute(.editorSyntaxInk, at: header.location, effectiveRange: nil) != nil)
        #expect(selectedHeader.attribute(.editorSyntaxInk, at: header.location + 2, effectiveRange: nil) != nil)
        let bodyBox = try #require(selectedHeader.attribute(.blockDecoration, at: body.location, effectiveRange: nil) as? BlockDecoration)
        #expect(bodyBox.drawsBelowSelection)

        let selectedBody = editor.styleBlock(source, selectionRange: body)
        #expect(selectedBody.attribute(.fragmentOverlay, at: header.location + 2, effectiveRange: nil) != nil)
        #expect(selectedBody.attribute(.editorSyntaxInk, at: firstPrefix.location, effectiveRange: nil) == nil)

        let selectedPrefix = editor.styleBlock(
            source, selectionRange: NSRange(location: firstPrefix.location, length: 1))
        #expect(selectedPrefix.attribute(.editorSyntaxInk, at: firstPrefix.location, effectiveRange: nil) != nil)
        #expect(selectedPrefix.attribute(.editorSyntaxInk, at: secondPrefix.location, effectiveRange: nil) == nil)
    }

}
