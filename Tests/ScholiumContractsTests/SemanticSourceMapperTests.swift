import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Semantic source mapping storage representations")
struct SemanticSourceMapperTests {
    @Test("NSString-backed source keeps exact bytes and scalar-boundary byte ranges")
    func bridgedSourceRanges() throws {
        let sources = [
            "",
            "\u{FEFF}---\r\nunknown: 'keep' # literal\n---\r\n# 中文 e\u{301} 🧭\r\nTail\rEnd\n",
            "NFC é\nNFD e\u{301}\r\n\u{301}🧑🏽‍💻\r\n",
        ]
        for original in sources {
            let foreign = NSMutableString(string: original).copy() as! NSString as String
            // Empty NSString can be a native small string; the nonempty
            // Unicode fixtures exercise the actual exact-buffer snapshot form.
            if !original.isEmpty { try #require(!foreign.isContiguousUTF8) }
            let mapper = SemanticSourceMapper(foreign)
            #expect(mapper.source.isContiguousUTF8)
            #expect(Data(mapper.source.utf8) == Data(original.utf8))
            #expect(Data((mapper.nsSource as String).utf8) == Data(original.utf8))
            var boundaries = [0]
            var offset = 0
            for scalar in original.unicodeScalars {
                offset += scalar.value > 0xFFFF ? 2 : 1
                boundaries.append(offset)
            }
            let units = Array(original.utf16)
            let characterBoundaries = Set(original.indices.map { $0.utf16Offset(in: original) } + [units.count])
            for (index, lower) in boundaries.enumerated() {
                let upper = boundaries[min(index + 1, boundaries.count - 1)]
                let range = NSRange(location: lower, length: upper - lower)
                let span = try #require(mapper.span(for: range))
                let expectedLower = String(decoding: units[..<lower], as: UTF16.self).utf8.count
                let expectedUpper = String(decoding: units[..<upper], as: UTF16.self).utf8.count
                #expect(span.utf16LowerBound == lower && span.utf16UpperBound == upper)
                #expect(span.utf8LowerBound == expectedLower && span.utf8UpperBound == expectedUpper)
                if characterBoundaries.contains(lower) {
                    #expect(mapper.utf16Offset(forUTF8Offset: expectedLower) == lower)
                }
            }
            #expect(mapper.span(for: NSRange(location: NSNotFound, length: 0)) == nil)
            #expect(mapper.span(for: NSRange(location: units.count + 1, length: 0)) == nil)
        }
    }

    @Test("Bridged Markdown has the same path, body offsets, semantic spans, and exact revision")
    func bridgedSemanticDocumentMatchesNative() throws {
        let source =
            "\u{FEFF}---\r\nunknown: 'keep' # literal\ntitle: Mapper\r\n---\r\n\r\n"
            + "# 范围 e\u{301} 🧭\r\n\r\n"
            + "**证据 e\u{301} 🧭** [Visible](Target.md) [[Topic|中文]]{{Reason.}}\n\n"
            + "- Nested e\u{301}\r\n  - Detail 🧭\r\n\r\n"
            + "`[[Literal]]` %% hidden %%\r\nTail without final newline"
        let foreign = NSMutableString(string: source).copy() as! NSString as String
        try #require(!foreign.isContiguousUTF8)
        let path = "Topics/源 e\u{301}.md"
        let expectedDocument = NoteDocument(relativePath: path, rawContent: source)
        let actualDocument = NoteDocument(relativePath: path, rawContent: foreign)
        let expected = MarkdownSemanticDocument(parsing: expectedDocument)
        let actual = MarkdownSemanticDocument(parsing: actualDocument)
        #expect(actual == expected)
        #expect(actualDocument.sourceBytes == Data(source.utf8))
        #expect(actualDocument.bodyByteRange == expectedDocument.bodyByteRange)
        #expect(actualDocument.relativePath.utf8.elementsEqual(path.utf8))
        #expect(actual.fingerprint == DocumentFingerprint(data: Data(source.utf8)))
        let heading = try #require(actual.headings.first)
        #expect(heading.span.start.line == 6 && heading.span.start.utf16Column == 1)
        for span in actual.blocks.map(\.span) + actual.inlines.map(\.span) + actual.links.map(\.span) {
            let exact = (source as NSString).substring(with: span.nsRange)
            #expect(Data(source.utf8)[span.utf8Range] == Data(exact.utf8))
        }
    }
}
