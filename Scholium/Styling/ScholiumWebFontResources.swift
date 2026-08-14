import Foundation
import WebKit

/// Serves only packaged font bytes to Scholium-owned WebKit surfaces. The
/// custom scheme has no filesystem, network, research-content, or mutation
/// route; exact Markdown remains an in-memory value supplied separately.
enum ScholiumWebFontResources {
    static let scheme = "scholium-font"
    private static let host = "bundled"
    private static let allowedResources: [String: String] = [
        "Alegreya-Regular.ttf": "font/ttf",
        "Alegreya-Italic.ttf": "font/ttf",
        "Alegreya-Bold.ttf": "font/ttf",
        "Alegreya-BoldItalic.ttf": "font/ttf",
        "VictorMono-Regular.ttf": "font/ttf",
        "VictorMono-Italic.ttf": "font/ttf",
        "VictorMono-Bold.ttf": "font/ttf",
        "VictorMono-BoldItalic.ttf": "font/ttf",
        "KaTeX_AMS-Regular.woff2": "font/woff2",
        "KaTeX_Caligraphic-Bold.woff2": "font/woff2",
        "KaTeX_Caligraphic-Regular.woff2": "font/woff2",
        "KaTeX_Fraktur-Bold.woff2": "font/woff2",
        "KaTeX_Fraktur-Regular.woff2": "font/woff2",
        "KaTeX_Main-Bold.woff2": "font/woff2",
        "KaTeX_Main-BoldItalic.woff2": "font/woff2",
        "KaTeX_Main-Italic.woff2": "font/woff2",
        "KaTeX_Main-Regular.woff2": "font/woff2",
        "KaTeX_Math-BoldItalic.woff2": "font/woff2",
        "KaTeX_Math-Italic.woff2": "font/woff2",
        "KaTeX_SansSerif-Bold.woff2": "font/woff2",
        "KaTeX_SansSerif-Italic.woff2": "font/woff2",
        "KaTeX_SansSerif-Regular.woff2": "font/woff2",
        "KaTeX_Script-Regular.woff2": "font/woff2",
        "KaTeX_Size1-Regular.woff2": "font/woff2",
        "KaTeX_Size2-Regular.woff2": "font/woff2",
        "KaTeX_Size3-Regular.woff2": "font/woff2",
        "KaTeX_Size4-Regular.woff2": "font/woff2",
        "KaTeX_Typewriter-Regular.woff2": "font/woff2",
    ]

    struct Resource {
        let url: URL
        let data: Data
        let mimeType: String
    }

    static func url(for filename: String) -> String {
        "\(scheme)://\(host)/\(filename)"
    }

    @MainActor
    static func install(in configuration: WKWebViewConfiguration) {
        configuration.setURLSchemeHandler(Handler.shared, forURLScheme: scheme)
    }

    static func resource(for url: URL) -> Resource? {
        guard url.scheme == scheme,
              url.host == host,
              url.pathComponents.count == 2,
              let filename = url.pathComponents.last,
              let mimeType = allowedResources[filename] else { return nil }
        let resourceURL = URL(fileURLWithPath: filename)
        guard resourceURL.lastPathComponent == filename,
              let extensionSeparator = filename.lastIndex(of: ".") else { return nil }
        let name = String(filename[..<extensionSeparator])
        let fileExtension = String(filename[filename.index(after: extensionSeparator)...])
        guard let bundledURL = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension
        ), let data = try? Data(contentsOf: bundledURL, options: .mappedIfSafe) else {
            return nil
        }
        return Resource(url: url, data: data, mimeType: mimeType)
    }

    private final class Handler: NSObject, WKURLSchemeHandler {
        static let shared = Handler()
        private var cache: [URL: Resource] = [:]

        func webView(
            _ webView: WKWebView,
            start urlSchemeTask: any WKURLSchemeTask
        ) {
            guard let url = urlSchemeTask.request.url,
                  let resource = cache[url]
                    ?? ScholiumWebFontResources.resource(for: url) else {
                urlSchemeTask.didFailWithError(NSError(
                    domain: "ScholiumWebFontResources",
                    code: 1
                ))
                return
            }
            cache[url] = resource
            urlSchemeTask.didReceive(URLResponse(
                url: resource.url,
                mimeType: resource.mimeType,
                expectedContentLength: resource.data.count,
                textEncodingName: nil
            ))
            urlSchemeTask.didReceive(resource.data)
            urlSchemeTask.didFinish()
        }

        func webView(
            _ webView: WKWebView,
            stop urlSchemeTask: any WKURLSchemeTask
        ) {}
    }
}
