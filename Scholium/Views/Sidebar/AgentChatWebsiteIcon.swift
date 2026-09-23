import AppKit
import Foundation

/// Bundled site identity for links already visible in Chat. The favicon is the
/// site's own mark, not a source or trust indicator. The SVG comes from
/// https://cdn.oaistatic.com/assets/favicon-o20kmmos.svg (retrieved 2026-09-23).
@MainActor
enum AgentChatWebsiteIcon {
    static func image(for url: URL) -> NSImage? {
        guard isOpenAI(url) else { return nil }
        return openAIImage
    }

    static var presentationCSS: String {
        guard let data = openAIData else { return "" }
        return """
            .scholium-document a.scholium-chat-link[data-scholium-chat-website-icon="openai"]::before {
                background: url("data:image/svg+xml;base64,\(data.base64EncodedString())") center / contain no-repeat;
                -webkit-mask: none;
                mask: none;
            }
            """
    }

    private static let openAIData = Bundle.module.url(
        forResource: "openai", withExtension: "svg"
    ).flatMap { try? Data(contentsOf: $0) }

    private static let openAIImage = openAIData.flatMap(NSImage.init(data:))

    private static func isOpenAI(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host?.lowercased()
        else { return false }
        return host == "openai.com" || host.hasSuffix(".openai.com")
            || host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }
}
