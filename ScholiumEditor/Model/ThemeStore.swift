// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import Foundation

/// Immutable bundled rendering themes. Application settings own appearance;
/// authored source never chooses a filesystem theme or changes preferences.
public final class ThemeStore {
    nonisolated(unsafe) public static let shared = ThemeStore()
    private let activeGeneralLight = "classic-light"
    private let activeGeneralDark = "classic-dark"
    private let activeSyntaxLight = "tomorrow"
    private let activeSyntaxDark = "one-dark"
    private let generalByName: [String: GeneralTheme]
    private let syntaxByName: [String: SyntaxTheme]
    private init() {
        generalByName = Dictionary(Self.load(GeneralTheme.self, bundled: "Themes/General").map { ($0.0.name, $0.0) }, uniquingKeysWith: { first, _ in first })
        syntaxByName = Dictionary(Self.load(SyntaxTheme.self, bundled: "Themes/Syntax").map { ($0.0.name, $0.0) }, uniquingKeysWith: { first, _ in first })
    }

    public func general(dark: Bool) -> GeneralTheme {
        let active = dark ? activeGeneralDark : activeGeneralLight
        return generalByName[active]
            ?? generalByName[dark ? "classic-dark" : "classic-light"]
            ?? .fallback(dark ? .dark : .light)
    }

    /// The syntax theme in force for an appearance, or `nil` if none can be
    /// loaded — `CodeSyntaxPalette` then falls back to its compiled-in palettes.
    ///
    /// An editor theme may pin a syntax theme of its own; that wins over the
    /// General row's choice, which is what makes the assignment an *override*
    /// rather than a second setting. A theme that assigns none — `nil`, the
    /// default — takes General's, so switching editor themes normally leaves
    /// code colors alone.
    func syntax(dark: Bool) -> SyntaxTheme? {
        let assigned = general(dark: dark).syntaxTheme
        let active = assigned ?? (dark ? activeSyntaxDark : activeSyntaxLight)
        return syntaxByName[active]
            ?? syntaxByName[dark ? activeSyntaxDark : activeSyntaxLight]
            ?? syntaxByName[dark ? "one-dark" : "tomorrow"]
    }

    private static func load<T: Decodable>(_ type: T.Type, bundled subdirectory: String) -> [(T, URL)] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
        return urls.compactMap { decode(type, $0) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ url: URL) -> (T, URL)? {
        guard let data = try? Data(contentsOf: url),
            let theme = try? JSONDecoder().decode(T.self, from: data)
        else { return nil }
        return (theme, url)
    }
}
