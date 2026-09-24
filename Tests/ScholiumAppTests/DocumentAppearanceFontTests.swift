import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Installed document fonts")
struct DocumentAppearanceFontTests {
    @Test("Installed families reach shared Review and Edit typography with safe CSS quoting")
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
}
