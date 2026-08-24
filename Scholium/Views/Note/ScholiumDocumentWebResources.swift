import Foundation

/// Resolves the same checked-in document resources in SwiftPM development and
/// the packaged app. Editor and Read surfaces share this lookup but retain
/// separate runtime ownership.
enum ScholiumDocumentWebResources {
    private static func url(named name: String, extension fileExtension: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourceURL
                .appendingPathComponent("Scholium_ScholiumApp.bundle", isDirectory: true)
            if let packagedBundle = Bundle(url: packagedBundleURL),
               let packagedURL = packagedBundle.url(
                forResource: name,
                withExtension: fileExtension
               ) {
                return packagedURL
            }
        }
        return Bundle.module.url(forResource: name, withExtension: fileExtension)
    }

    static func text(named name: String, extension fileExtension: String) -> String? {
        guard let url = url(named: name, extension: fileExtension) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
