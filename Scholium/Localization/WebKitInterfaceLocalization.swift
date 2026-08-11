import Foundation

/// App-authored interface copy shared by the Edit and Review WebKit surfaces.
///
/// Exact Markdown, rendered research prose, note titles, paths, citations, and
/// other researcher-owned text must never enter this payload. String catalogs
/// compile to ordinary `.strings` tables; loading the table as a property list
/// keeps WebKit copy under the same application-language choice as native UI
/// without creating a second localization owner in JavaScript.
struct WebKitInterfaceLocalization: Codable, Equatable, Sendable {
    let languageTag: String
    let strings: [String: String]

    static func current(bundle: Bundle = .module) -> Self {
        let preferred = bundle.preferredLocalizations.first
            ?? Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return localized(languageTag: preferred, bundle: bundle)
    }

    static func localized(
        languageTag requestedLanguageTag: String,
        bundle: Bundle = .module
    ) -> Self {
        let languageTag = supportedLanguageTag(for: requestedLanguageTag)
        let translated = loadTable(languageTag: "zh-Hans", bundle: bundle)
        let englishTable = loadTable(languageTag: "en", bundle: bundle)
        let englishKeys = Set(translated.keys).union(englishTable.keys)
        let english = Dictionary(uniqueKeysWithValues: englishKeys.map { key in
            (key, englishTable[key] ?? key)
        })
        let localized = languageTag == "en"
            ? english
            : english.merging(
                translated,
                uniquingKeysWith: { _, translated in translated }
            )
        return Self(languageTag: languageTag, strings: localized)
    }

    func base64JSON() -> String {
        (try? JSONEncoder().encode(self))?.base64EncodedString() ?? ""
    }

    func string(_ key: String) -> String {
        strings[key] ?? key
    }

    private static func supportedLanguageTag(for identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == "zh" || normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
            return "zh-Hans"
        }
        return "en"
    }

    private static func loadTable(
        languageTag: String,
        bundle: Bundle
    ) -> [String: String] {
        guard let url = bundle.url(
            forResource: "WebKitInterface",
            withExtension: "strings",
            subdirectory: nil,
            localization: languageTag
        ), let data = try? Data(contentsOf: url),
           let propertyList = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ), let table = propertyList as? [String: String] else { return [:] }
        return table
    }
}
