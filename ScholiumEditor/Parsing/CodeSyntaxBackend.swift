import Foundation

// MARK: - Code Syntax Backend
//
// The pluggable seam. `CodeHighlighter` (the facade) resolves the effective
// language, then hands (code, language) to whichever backend is active. The
// built-in backend scans JSON language definitions; an "Advanced Code" extension
// can register a Shiki/TextMate backend that folds its rich scopes down to the
// six `CodeHighlighter.TokenType` cases, keeping the palette the single source of
// truth so Edit mode and Read mode stay identical.
//
// `language` is the already-resolved id (an empty/absent fence has been replaced
// with the user's default). A backend returns tokens with ranges relative to
// `code`.

protocol CodeSyntaxBackend {
    func tokenize(_ code: String, language: String) -> [CodeHighlighter.Token]
}
