import ScholiumContracts
import Foundation

enum ScholiumCalloutStyles {
    static let css: String = {
        guard let url = Bundle.module.url(forResource: "callouts", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }()
}
