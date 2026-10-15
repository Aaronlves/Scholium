import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Safe Markdown inline marker replacement")
struct SafeMarkdownInlineTokenTests {
    private let nonce = "0123456789ABCDEF0123456789ABCDEF"

    @Test("Forward scanning is byte-equivalent to the former search for unambiguous render markers")
    func legacyOracle() {
        let components = ["Z0", "Z10", "M1", "M100", "F1R1", "F1R10", "F10R100", "L1", "L10", "L100", "H0", "H10"]
        let keys = components.map { marker($0) }
        let replacements = Dictionary(uniqueKeysWithValues: zip(keys, components.map { "<span data-test=\"\($0)\">🦉 &amp; \($0)</span>" }))
        let values = [
            "", "ordinary 中文 e\u{301} 🦉 & < > \" '\r\n",
            keys.joined(), keys.reversed().joined(separator: "e\u{301} & 中🦉\r\n"),
            keys[9] + keys[7] + keys[8] + keys[9] + " & <script>bad()</script>",
            marker("L999") + " & " + keys[1],
            "SCHOLIUMINLINETOKENbad<" + keys[0] + ">",
            "SCHOLIUMINLINETOKEN" + nonce + "F10R" + keys[4],
            String(keys[2].dropLast()) + keys[10],
        ]
        for value in values {
            var actual = ""
            SafeMarkdownInlineTokens(replacements: replacements).appendEscapedText(value, to: &actual)
            #expect(Data(actual.utf8) == Data(legacyReplace(value, replacements: replacements).utf8))
        }
    }

    @Test("Unknown and incomplete candidates retain literal bytes and do not consume a following valid marker")
    func malformedRecovery() {
        let valid = marker("L10")
        let unknown = marker("L100")
        let otherNonce = "SCHOLIUMINLINETOKENFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFL10END"
        let replacements = [valid: "<a>known &amp; safe</a>"]
        let badPrefixes = [
            "SCHOLIUMINLINETOKEN", "SCHOLIUMINLINETOKEN<untrusted>&",
            "SCHOLIUMINLINETOKEN" + nonce + "L",
            "SCHOLIUMINLINETOKEN" + nonce + "L10EN",
            "SCHOLIUMINLINETOKEN" + nonce + "L100000000000000000000000000000000000",
            "SCHOLIUMINLINETOKEN" + nonce + "F1R",
            "SCHOLIUMINLINETOKEN" + nonce + "F1R10EN",
            "SCHOLIUMINLINETOKEN" + nonce + "C1END",
            "SCHOLIUMINLINETOKEN" + nonce.lowercased() + "L10END",
            unknown, otherNonce,
        ]
        for prefix in badPrefixes {
            let value = "<中🦉>" + prefix + valid + "& e\u{301}"
            var actual = "already appended: "
            SafeMarkdownInlineTokens(replacements: replacements).appendEscapedText(value, to: &actual)
            let expected = "already appended: " + escape("<中🦉>" + prefix) + "<a>known &amp; safe</a>&amp; e\u{301}"
            #expect(Data(actual.utf8) == Data(expected.utf8))

            var literal = ""
            SafeMarkdownInlineTokens(replacements: replacements).appendEscapedText(prefix, to: &literal)
            #expect(Data(literal.utf8) == Data(escape(prefix).utf8))
        }
    }

    @Test("Inserted trusted HTML is never recursively scanned and an empty dictionary only escapes source")
    func nonrecursiveReplacement() {
        let first = marker("H1")
        let second = marker("M10")
        let html = "<mark>" + second + " &amp; 🦉</mark>"
        var result = ""
        SafeMarkdownInlineTokens(replacements: [first: html, second: "<math>second</math>"])
            .appendEscapedText(first + second, to: &result)
        #expect(Data(result.utf8) == Data((html + "<math>second</math>").utf8))

        var literal = ""
        let value = "<script>&\"'" + first
        SafeMarkdownInlineTokens(replacements: [:]).appendEscapedText(value, to: &literal)
        #expect(Data(literal.utf8) == Data(escape(value).utf8))
    }

    @Test("All 9600 distinct markers render in authored order with exact independently constructed output")
    func denseMarkerCorpus() {
        var replacements: [String: String] = [:]
        var source = ""
        var expected = ""
        for ordinal in 0..<9600 {
            // A permutation exercises decimal boundaries independently of key insertion order.
            let index = ordinal * 7919 % 9600
            let key = marker("L\(index)")
            let html = "<a data-target=\"\(index)\">目标 \(index)</a>"
            replacements[key] = html
            source += "中 & 🦉 " + key + " e\u{301}\r\n"
            expected += "中 &amp; 🦉 " + html + " e\u{301}\r\n"
        }
        var actual = ""
        SafeMarkdownInlineTokens(replacements: replacements).appendEscapedText(source, to: &actual)
        #expect(Data(actual.utf8) == Data(expected.utf8))
        #expect(!actual.contains("SCHOLIUMINLINETOKEN"))

        // Keep the former quadratic search bounded while retaining the full dictionary.
        for indices in [[1, 10, 100, 1000], [9599, 0, 999, 99]] {
            let fragment = indices.map { marker("L\($0)") }.joined(separator: " & 🦉 ")
            var rendered = ""
            SafeMarkdownInlineTokens(replacements: replacements).appendEscapedText(fragment, to: &rendered)
            #expect(Data(rendered.utf8) == Data(legacyReplace(fragment, replacements: replacements).utf8))
        }
    }

    @Test("Full renderer keeps labels, targets and source locators distinct across 1, 10 and 100")
    func rendererDecimalBoundaries() throws {
        let source =
            "\u{FEFF}---\r\nunknown: 'preserved'\r\n---\r\n# 索引 🦉\r\n\r\n"
            + (0..<125).map { "[[Target\($0)|标签\($0)]]" }.joined(separator: " 中 & ") + "\r\n"
        let document = NoteDocument(relativePath: "Decimal Boundaries.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let anchors = try noteAnchors(in: rendered.htmlBody)
        #expect(anchors.count == 125)
        #expect(rendered.semanticDocument.links.count == 125)
        for (index, anchor) in anchors.enumerated() {
            #expect(anchor.target == "Target\(index)")
            #expect(anchor.label == "标签\(index)")
            let link = try #require(rendered.semanticDocument.links.first { $0.target == "Target\(index)" })
            #expect(anchor.html.contains("data-source-utf16-start=\"\(link.linkSpan.utf16LowerBound)\""))
            #expect(anchor.html.contains("data-source-utf16-end=\"\(link.linkSpan.utf16UpperBound)\""))
            #expect(anchor.html.contains("data-source-utf8-start=\"\(link.linkSpan.utf8LowerBound)\""))
            #expect(anchor.html.contains("data-source-utf8-end=\"\(link.linkSpan.utf8UpperBound)\""))
        }
        #expect(!rendered.htmlBody.contains("SCHOLIUMINLINETOKEN"))
        #expect(document.sourceBytes == Data(source.utf8))
    }

    private func marker(_ component: String) -> String {
        "SCHOLIUMINLINETOKEN" + nonce + component + "END"
    }

    /// The previous algorithm, deliberately independent of the production scanner.
    private func legacyReplace(_ value: String, replacements: [String: String]) -> String {
        var remaining = value[...]
        var result = ""
        while !remaining.isEmpty {
            let candidate = replacements.compactMap { key, html -> (String.Index, String, String)? in
                guard let range = remaining.range(of: key) else { return nil }
                return (range.lowerBound, key, html)
            }.min { $0.0 < $1.0 }
            guard let candidate, let range = remaining.range(of: candidate.1) else {
                result += escape(String(remaining))
                break
            }
            result += escape(String(remaining[..<range.lowerBound]))
            result += candidate.2
            remaining = remaining[range.upperBound...]
        }
        return result
    }
}

@Suite(
    "Dense Links render diagnostic",
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DENSE_RENDER"] == "1"))
struct DenseLinksRenderDiagnosticTests {
    @Test("Render the exact generated Dense Links source; report semantic and renderer work separately")
    func exactDenseLinksFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath().path + "/"
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"]))
            .standardizedFileURL.resolvingSymlinksInPath()
        try #require(fixture.path.hasPrefix(buildRoot), "Only a disposable repository-local .build fixture is admitted")
        let manifest = try JSONDecoder().decode(DenseRenderManifest.self, from: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json")))
        let relativePath = try #require(manifest.scenarios["dense_links"])
        let inventory = try #require(manifest.files[relativePath])
        let file = fixture.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        try #require(file.path.hasPrefix(fixture.path + "/"))
        let bytes = try Data(contentsOf: file)
        let fingerprint = DocumentFingerprint(data: bytes)
        try #require(fingerprint.sha256 == inventory.sha256 && bytes.count == inventory.bytes)
        let source = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        try #require(document.sourceBytes == bytes)

        let parseStart = ContinuousClock.now
        let semantic = MarkdownSemanticDocument(parsing: document)
        let parseDuration = parseStart.duration(to: .now)
        try #require(semantic.links.count == 9600, "This diagnostic requires the complete generated Dense Links scenario")
        let renderStart = ContinuousClock.now
        let rendered = SafeMarkdownRenderer.render(document, semantic: semantic)
        let renderDuration = renderStart.duration(to: .now)

        // Validation and disk reread are outside both measured intervals.
        let anchors = try noteAnchors(in: rendered.htmlBody)
        #expect(anchors.count == semantic.links.count)
        for (anchor, link) in zip(anchors, semantic.links) {
            let destination = link.target + (link.fragment.map { "#" + $0 } ?? "")
            let decoded = destination.removingPercentEncoding ?? destination
            #expect(anchor.target == escape(decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decoded))
            #expect(anchor.label == escape(link.alias ?? link.target))
            #expect(anchor.html.contains("data-source-utf16-start=\"\(link.linkSpan.utf16LowerBound)\""))
            #expect(anchor.html.contains("data-source-utf16-end=\"\(link.linkSpan.utf16UpperBound)\""))
        }
        #expect(!rendered.htmlBody.contains("SCHOLIUMINLINETOKEN"))
        #expect(try Data(contentsOf: file) == bytes)
        #expect(rendered.semanticDocument.fingerprint == fingerprint)
        let record: [String: Any] = [
            "scenario": "dense_links", "source_sha256": fingerprint.sha256, "source_bytes": bytes.count,
            "semantic_links": semantic.links.count, "rendered_note_anchors": anchors.count,
            "semantic_ms": milliseconds(parseDuration), "render_ms": milliseconds(renderDuration),
            "html_utf8_bytes": rendered.htmlBody.utf8.count,
            "marker_leak": rendered.htmlBody.contains("SCHOLIUMINLINETOKEN"),
            "measurement_boundary": "semantic parse and synchronous renderer separately; excludes source IO, validation, DOM and display",
        ]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        FileHandle.standardOutput.write(Data("DENSE_RENDER_DIAGNOSTIC ".utf8) + json + Data("\n".utf8))
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

private struct DenseRenderManifest: Decodable {
    struct File: Decodable {
        let bytes: Int
        let sha256: String
    }
    let scenarios: [String: String]
    let files: [String: File]
}

private struct NoteAnchor {
    let target: String
    let label: String
    let html: String
}

private func noteAnchors(in html: String) throws -> [NoteAnchor] {
    let expression = try NSRegularExpression(pattern: #"<a\b[^>]*href="scholium-note:([^"]*)"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators])
    let source = html as NSString
    return expression.matches(in: html, range: NSRange(location: 0, length: source.length)).map { match in
        NoteAnchor(
            target: source.substring(with: match.range(at: 1)), label: source.substring(with: match.range(at: 2)), html: source.substring(with: match.range))
    }
}

private func escape(_ source: String) -> String {
    var result = ""
    for scalar in source.unicodeScalars {
        switch scalar {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        case "'": result += "&#39;"
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result
}
