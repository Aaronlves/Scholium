import Foundation

// MARK: - Code Highlighter (facade)
//
// The public entry point for fenced-code-block highlighting and the pluggable
// seam. It owns the shared token model (`Token` / `TokenType`, keyed by
// `CodeSyntaxPalette`) and delegates the actual tokenizing to `activeBackend`.
// The default backend is the lightweight JSON-driven scanner
// (`BuiltinSyntaxBackend`); an "Advanced Code" extension can install a
// Shiki/TextMate backend by assigning `activeBackend` — as long as it maps its
// scopes onto these six `TokenType` cases, Edit mode and Read mode stay identical
// (both consumers call `tokenize` and color from the shared palette).

enum CodeHighlighter {

    /// The themeable color scopes, aligned with CotEditor's Appearance palette
    /// (Keywords, Commands, Types, Attributes, Variables, Values, Numbers,
    /// Strings, Comments) so a future Settings › Themes can map each to a color.
    /// The built-in scanner drives keyword/command/type/attribute/variable/value
    /// from a def's word-lists and number/string/comment lexically; function
    /// calls fold into `command` and character literals into `string` (the
    /// lightweight scanner can't separate them — a full backend can).
    enum TokenType: Equatable {
        case keyword, command, type, attribute, variable, value
        case number, string, comment
    }

    struct Token: Equatable {
        let range: NSRange
        let type: TokenType
    }

    /// The backend that turns code into tokens. Defaults to the built-in scanner;
    /// reassign to plug a different highlighter in behind the same API.
    /// ponytail: main-thread use (rendering / export), like the store it wraps.
    nonisolated(unsafe) static var activeBackend: CodeSyntaxBackend = BuiltinSyntaxBackend(store: .shared)

    /// Tokenize a code block. An empty/absent `language` (an untagged fence) is
    /// resolved to the user's configured default language before dispatch, so a
    /// bare ``` block highlights as whatever "Default code syntax" is set to.
    static func tokenize(_ code: String, language: String?) -> [Token] {
        let raw = language?.trimmingCharacters(in: .whitespaces) ?? ""
        let lang = raw.isEmpty ? SyntaxDefinitionStore.shared.defaultLanguage : raw
        return activeBackend.tokenize(code, language: lang)
    }
}
