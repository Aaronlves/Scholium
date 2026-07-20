import Foundation

enum ScholiumPreviewStyles {
    static let css: String = {
        guard let url = Bundle.module.url(forResource: "previews", withExtension: "css"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }()
}
