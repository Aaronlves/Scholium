// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import Foundation

/// Syntax definitions are bundled resources, never paths resolved from Markdown.
public final class SyntaxDefinitionStore {
    nonisolated(unsafe) public static let shared = SyntaxDefinitionStore()
    enum Resolution: Equatable {
        case plain
        case definition(LanguageDefinition)
        case unknown
    }
    public var defaultLanguage = "plain"
    private let byName: [String: LanguageDefinition]
    private static let plainAliases: Set<String> = ["", "plain", "plaintext", "text", "none", "txt"]

    private init() {
        var definitions: [String: LanguageDefinition] = [:]
        for url in Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Syntaxes") ?? [] {
            guard let data = try? Data(contentsOf: url),
                let definition = try? JSONDecoder().decode(LanguageDefinition.self, from: data)
            else { continue }
            definitions[definition.name] = definition
            for alias in definition.aliases { definitions[alias] = definition }
        }
        byName = definitions
    }

    func resolve(_ language: String?) -> Resolution {
        let key = (language ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if Self.plainAliases.contains(key) { return .plain }
        if let def = byName[key] { return .definition(def) }
        return .unknown
    }

}
