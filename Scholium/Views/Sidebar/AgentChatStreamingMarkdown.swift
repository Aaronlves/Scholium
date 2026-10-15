import Foundation
import JavaScriptCore
import ScholiumContracts

/// One actor owns the standalone, locked Remend runtime. No Swift objects,
/// filesystem APIs, network APIs or user text are installed as executable code.
/// Completion is disposable presentation; callers retain the exact source.
actor AgentChatStreamingMarkdown {
    static let shared = AgentChatStreamingMarkdown()

    enum Failure: Error {
        case runtimeUnavailable
        case completionFailed
    }

    private var context: JSContext?
    private var completion: JSValue?

    func complete(_ source: String) throws -> String {
        try Task.checkCancellation()
        if context == nil {
            try loadRuntime()
        }
        guard let context, let completion else { throw Failure.runtimeUnavailable }
        context.exception = nil
        defer { context.exception = nil }
        let literals = try ProtectedLiterals(source)
        let result = completion.call(withArguments: [literals.projection])
        guard context.exception == nil, let result, result.isString,
            let completed = result.toString()
        else { throw Failure.completionFailed }
        try Task.checkCancellation()
        return literals.restore(in: completed)
    }

    /// Use the document dialect's exact spans instead of a second literal parser.
    /// The nonce cannot occur in the source and is never returned to a caller.
    private struct ProtectedLiterals {
        let projection: String
        private let replacements: [(token: String, source: String)]

        init(_ source: String) throws {
            let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
            let semantic = MarkdownSemanticDocument(parsing: document)
            let spans =
                semantic.mathExpressions.map(\.span)
                + semantic.blocks.filter { $0.kind == .code }.map(\.span)
            guard !spans.isEmpty else {
                projection = source
                replacements = []
                return
            }
            let raw = source as NSString
            var ranges: [Range<Int>] = []
            for span in spans {
                let lower = span.utf16LowerBound
                let upper = span.utf16UpperBound
                guard lower >= 0, upper >= lower, upper <= raw.length else {
                    throw Failure.completionFailed
                }
                if lower < upper { ranges.append(lower..<upper) }
            }
            // A display-math span may contain a Markdown code span. Merge in
            // original-source coordinates before any replacement changes size.
            var disjoint: [Range<Int>] = []
            for range in ranges.sorted(by: {
                $0.lowerBound == $1.lowerBound ? $0.upperBound < $1.upperBound : $0.lowerBound < $1.lowerBound
            }) {
                if let previous = disjoint.last, range.lowerBound < previous.upperBound {
                    disjoint[disjoint.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
                } else {
                    disjoint.append(range)
                }
            }
            var nonce: String
            repeat {
                nonce = "SCHOLIUMSTREAMLITERAL" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            } while source.contains(nonce)
            let projected = NSMutableString(string: source)
            var protected: [(token: String, source: String)] = []
            for (index, span) in disjoint.reversed().enumerated() {
                let range = NSRange(location: span.lowerBound, length: span.count)
                let token = nonce + "M\(index)END"
                protected.append((token, raw.substring(with: range)))
                projected.replaceCharacters(in: range, with: token)
            }
            projection = projected as String
            replacements = protected
        }

        func restore(in completed: String) -> String {
            replacements.reduce(completed) { value, literal in
                value.replacingOccurrences(of: literal.token, with: literal.source)
            }
        }
    }

    private func loadRuntime() throws {
        guard let script = ScholiumDocumentWebResources.text(named: "chat-streaming-markdown.bundle", extension: "js"),
            let candidate = JSContext()
        else { throw Failure.runtimeUnavailable }
        candidate.evaluateScript(script)
        guard candidate.exception == nil,
            let function = candidate.objectForKeyedSubscript("scholiumCompleteStreamingMarkdown"),
            function.isObject, !function.isUndefined
        else { throw Failure.runtimeUnavailable }
        context = candidate
        completion = function
    }
}
