import Foundation

enum ScholiumMermaidAssets {
    static let runtimeJavaScript: String = loadTextResource("mermaid.bundle", extension: "js")
    static let css: String = loadTextResource("mermaid", extension: "css")

    private static func loadTextResource(_ name: String, extension fileExtension: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }
}
