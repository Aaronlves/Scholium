import Foundation

// MARK: - Built-in Syntax Backend
//
// The lightweight default backend: a single-pass O(n) char scanner — the same
// one that used to live in CodeHighlighter — now driven by a LanguageDefinition
// instead of hardcoded sets. It is not a full parser; it recognizes the lexical
// tokens that carry most of the visual signal (comments, strings, numbers,
// keywords, types, function calls). Comment/string/keyword data come from the
// def; numbers, identifiers, the Uppercase→type and `ident(`→function heuristics
// are universal and stay in code.

struct BuiltinSyntaxBackend: CodeSyntaxBackend {
    let store: SyntaxDefinitionStore

    func tokenize(_ code: String, language: String) -> [CodeHighlighter.Token] {
        switch store.resolve(language) {
        case .plain: return []
        case .definition(let d): return Self.scan(code, d)
        case .unknown: return Self.scan(code, .cFamilyFallback)
        }
    }

    // MARK: Scanner

    static func scan(_ code: String, _ def: LanguageDefinition) -> [CodeHighlighter.Token] {
        let ns = code as NSString
        let n = ns.length
        guard n > 0 else { return [] }

        let lineComment = def.lineComment.map { Array($0.utf16) }
        let blockOpen = def.blockComment.flatMap { $0.count == 2 ? Array($0[0].utf16) : nil }
        let blockClose = def.blockComment.flatMap { $0.count == 2 ? Array($0[1].utf16) : nil }
        // String delimiters as single characters (first unit of each entry).
        let stringDelims = Set(def.strings.compactMap { $0.utf16.first })
        // One word → scope lookup across all of the def's word-lists. Built in
        // this order so a word in several lists takes the most specific scope
        // (values/variables/attributes override commands override types over
        // keywords) — the same precedence as CotEditor's scope ordering.
        var wordType: [String: CodeHighlighter.TokenType] = [:]
        for w in def.keywords { wordType[w] = .keyword }
        for w in def.types { wordType[w] = .type }
        for w in def.commands { wordType[w] = .command }
        for w in def.attributes { wordType[w] = .attribute }
        for w in def.variables { wordType[w] = .variable }
        for w in def.values { wordType[w] = .value }

        func matches(_ lit: [unichar], at i: Int) -> Bool {
            guard i + lit.count <= n else { return false }
            for k in 0..<lit.count where ns.character(at: i + k) != lit[k] { return false }
            return true
        }
        func isIdentStart(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
        }
        func isIdentChar(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
        func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

        var tokens: [CodeHighlighter.Token] = []
        var i = 0
        while i < n {
            let c = ns.character(at: i)

            // Line comment → to end of line.
            if let lc = lineComment, !lc.isEmpty, matches(lc, at: i) {
                let start = i
                while i < n && ns.character(at: i) != 0x0A { i += 1 }
                tokens.append(.init(range: NSRange(location: start, length: i - start), type: .comment))
                continue
            }
            // Block comment → until close delimiter (or EOF).
            if let open = blockOpen, let close = blockClose, matches(open, at: i) {
                let start = i
                i += open.count
                while i < n && !matches(close, at: i) { i += 1 }
                i = min(n, i + close.count)
                tokens.append(.init(range: NSRange(location: start, length: i - start), type: .comment))
                continue
            }
            // String with backslash escapes; stops at end of line.
            if stringDelims.contains(c) {
                let quote = c
                let start = i
                i += 1
                while i < n {
                    let d = ns.character(at: i)
                    if d == 0x5C {
                        i += 2
                        continue
                    }  // escape
                    if d == quote {
                        i += 1
                        break
                    }
                    if d == 0x0A { break }
                    i += 1
                }
                tokens.append(.init(range: NSRange(location: start, length: min(i, n) - start), type: .string))
                continue
            }
            // Number (incl. trailing hex / exponent / dot chars).
            if isDigit(c) {
                let start = i
                i += 1
                while i < n {
                    let d = ns.character(at: i)
                    if isIdentChar(d) || d == 0x2E { i += 1 } else { break }
                }
                tokens.append(.init(range: NSRange(location: start, length: i - start), type: .number))
                continue
            }
            // Identifier → keyword / type / function call / plain.
            if isIdentStart(c) {
                let start = i
                i += 1
                while i < n && isIdentChar(ns.character(at: i)) { i += 1 }
                let range = NSRange(location: start, length: i - start)
                let word = ns.substring(with: range)
                if let t = wordType[word] {
                    tokens.append(.init(range: range, type: t))
                } else if let first = word.unicodeScalars.first, first.properties.isUppercase {
                    tokens.append(.init(range: range, type: .type))
                } else {
                    // Function call: identifier immediately followed by `(`.
                    // Folds into `command` (CotEditor colors calls as Commands).
                    var j = i
                    while j < n && ns.character(at: j) == 0x20 { j += 1 }
                    if j < n && ns.character(at: j) == 0x28 {
                        tokens.append(.init(range: range, type: .command))
                    }
                }
                continue
            }
            i += 1
        }
        return tokens
    }
}
