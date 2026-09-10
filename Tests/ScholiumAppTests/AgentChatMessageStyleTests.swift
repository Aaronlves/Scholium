import AppKit
import Testing

@testable import ScholiumApp

@Suite("Chat message style")
struct AgentChatMessageStyleTests {
  @Test("User and Agent body text share the native font and semantic ink")
  @MainActor
  func sharedBodyStyle() {
    let rendered = AgentChatSelectableText.renderReply("同一段正文。\n\n第二段。")
    let bodyFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let bodyColor = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let actualColor = bodyColor?.usingColorSpace(.sRGB)
    let expectedColor = ScholiumChatAppearance.messageNSForeground.usingColorSpace(.sRGB)

    #expect(bodyFont == ScholiumChatAppearance.messageNSFont)
    #expect(actualColor != nil && expectedColor != nil)
    #expect(abs((actualColor?.redComponent ?? 0) - (expectedColor?.redComponent ?? 0)) < 0.001)
    #expect(abs((actualColor?.greenComponent ?? 0) - (expectedColor?.greenComponent ?? 0)) < 0.001)
    #expect(abs((actualColor?.blueComponent ?? 0) - (expectedColor?.blueComponent ?? 0)) < 0.001)
    #expect(ScholiumChatAppearance.messageFont == .body)
  }

  @Test("Rich message surfaces use the same semantic ink in both appearances")
  @MainActor
  func sharedRichStyle() {
    for (dark, increasedContrast) in [(false, false), (true, false), (false, true), (true, true)] {
      let css = AgentChatDiagram.presentationCSS(dark: dark, increasedContrast: increasedContrast)
      for (role, key) in [(ScholiumColorRole.primaryText, "primary-text"), (.accent, "accent")] {
        let declaration = String(
          format: "--scholium-color-%@: #%06x;", key,
          role.resolvedRGBValue(isDark: dark, increasedContrast: increasedContrast))
        #expect(css.contains(declaration))
      }
    }
  }
}
