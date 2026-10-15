import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Related-content source attribution")
struct RelatedContentAttributionTests {
    @Test("Annotation priority and half-open boundaries preserve independent expected fields")
    func priorityAndBoundaries() {
        let links = [
            link(20..<22), link(18..<20, syntax: .markdown),
            link(8..<14, annotation: 14..<18),
        ]
        let mappings = [
            mapping(0..<1, to: 8..<9, kind: .linear),
            mapping(1..<2, to: 12..<16),
            mapping(2..<3, to: 6..<8),
            mapping(3..<4, to: 18..<20),
            mapping(4..<5, to: 21..<22),
        ]
        let value = segment("abcde", field: .body, mappings: mappings)
        let context = RelatedContentSourceAttribution(in: semantic(links))
        let actual = value.attributingRelatedContent(using: context)
        #expect(actual.relatedRankingText == ["link": " a e", "body": " cd"])
        expectLegacy(value, links: links, label: "annotation priority")
        let annotation = segment("abcde", field: .linkAnnotation, mappings: mappings)
        #expect(annotation.attributingRelatedContent(using: context).relatedRankingText == ["annotation": " abcde"])
        expectLegacy(annotation, links: links, label: "annotation owns its complete segment")
    }

    @Test("Unicode maps, holes, reverse source positions and overlapping intervals retain complete segments")
    func adversarialMappings() {
        let links = [
            link(32..<48, annotation: 12..<24),
            link(4..<8), link(4..<8), link(5..<7), link(8..<12),
            link(10..<20, annotation: 14..<18),
            link(40..<40, annotation: 22..<22),
            link(0..<50, syntax: .embed, annotation: 30..<34),
            link(36..<44, syntax: .markdown),
        ]
        let fixtures: [(String, [SearchSegmentOffset])] = [
            ("", []),
            (" \t\r\n", []),
            ("e\u{301}😀👩‍🔬中z", []),
            (
                "a😀b e\u{301}z",
                [
                    mapping(0..<1, to: 40..<41, kind: .linear),
                    mapping(2..<3, to: 14..<16),
                    mapping(3..<4, to: 6..<7, kind: .linear),
                    mapping(5..<7, to: 32..<34),
                    mapping(7..<8, to: 22..<22),
                ]
            ),
            (
                "ffi 中 e\u{301} 😀",
                [
                    mapping(0..<3, to: 18..<19),
                    mapping(3..<5, to: 8..<10, kind: .linear),
                    mapping(6..<8, to: 32..<34),
                    mapping(9..<11, to: 4..<6, kind: .linear),
                ]
            ),
        ]
        for (number, fixture) in fixtures.enumerated() {
            for field in fields {
                expectLegacy(segment(fixture.0, field: field, mappings: fixture.1), links: links, label: "adversarial \(number)")
            }
        }
    }

    @Test("Uniform fields retain their leading space and exact Unicode bytes")
    func uniformFields() {
        let nonWikilink = [link(0..<512, syntax: .markdown)]
        let linkOnly = [link(0..<512)]
        for text in ["", " ", "\u{301}e\u{301}\r\n😀", "ffi\t中文"] {
            let mappings = [mapping(0..<max(1, text.utf16.count), to: 0..<512)]
            for field in fields {
                // No applicable source ranges, and no source mappings, each
                // independently prove constant attribution without a character walk.
                expectLegacy(segment(text, field: field, mappings: mappings), links: [], label: "empty context")
                expectLegacy(segment(text, field: field, mappings: mappings), links: nonWikilink, label: "markdown links are not ranking links")
                expectLegacy(segment(text, field: field, mappings: []), links: linkOnly, label: "unmapped source")
            }
            for field in [SearchMatchedField.title, .summary, .heading, .tag, .linkAnnotation] {
                expectLegacy(segment(text, field: field, mappings: mappings), links: linkOnly, label: "link ranges do not affect this field")
            }
        }
    }

    @Test("Deterministic randomized attribution matches the former brute-force scan")
    func randomizedLegacyEquivalence() {
        var generator = Generator()
        let alphabet = ["a", " ", "中", "e\u{301}", "😀", "👩‍🔬", "ﬃ", "\t", "\r\n", "z"]
        for sample in 0..<192 {
            var text = ""
            for _ in 0..<generator.number(40) { text += alphabet[generator.number(alphabet.count)] }
            var mappings: [SearchSegmentOffset] = []
            var offset = generator.number(3)
            while offset < text.utf16.count {
                let end = min(text.utf16.count, offset + 1 + generator.number(5))
                let kind: SearchSegmentOffset.MappingKind = generator.number(2) == 0 ? .linear : .sourceSpan
                let sourceStart = generator.number(480)
                let sourceLength = kind == .linear ? end - offset : generator.number(20)
                mappings.append(mapping(offset..<end, to: sourceStart..<(sourceStart + sourceLength), kind: kind))
                offset = end + generator.number(4)
            }
            var links: [LinkOccurrence] = []
            for _ in 0..<generator.number(32) {
                let start = generator.number(480)
                let range = start..<(start + generator.number(32))
                let annotationStart = generator.number(480)
                let annotation: Range<Int>? = generator.number(2) == 0 ? nil : annotationStart..<(annotationStart + generator.number(32))
                let syntax: LinkSyntax = [.wikilink, .markdown, .embed][generator.number(3)]
                links.append(link(range, syntax: syntax, annotation: annotation))
                if generator.number(5) == 0 {
                    links.append(link(range, annotation: annotation))
                    links.append(link(range.lowerBound..<min(range.upperBound, range.lowerBound + 2)))
                }
            }
            for field in fields {
                expectLegacy(segment(text, field: field, mappings: mappings), links: links, label: "random \(sample)")
            }
        }
    }
}

private extension RelatedContentAttributionTests {
    var fields: [SearchMatchedField] {
        [.title, .alias, .heading, .summary, .author, .body, .callout, .footnote, .path, .tag, .publicationDate, .brokenLink, .linkAnnotation]
    }

    struct Generator {
        private var state: UInt64 = 0x8D31_92AE_4C70_1F65

        mutating func number(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(bound))
        }
    }

    func mapping(_ normalized: Range<Int>, to source: Range<Int>, kind: SearchSegmentOffset.MappingKind = .sourceSpan) -> SearchSegmentOffset {
        .init(
            normalizedUTF16LowerBound: normalized.lowerBound, normalizedUTF16UpperBound: normalized.upperBound,
            sourceUTF16LowerBound: source.lowerBound, sourceUTF16UpperBound: source.upperBound, mappingKind: kind)
    }

    func span(_ range: Range<Int>) -> SourceSpan {
        .init(
            utf8LowerBound: range.lowerBound, utf8UpperBound: range.upperBound,
            utf16LowerBound: range.lowerBound, utf16UpperBound: range.upperBound,
            start: .init(line: 1, utf8Column: range.lowerBound + 1, utf16Column: range.lowerBound + 1),
            end: .init(line: 1, utf8Column: range.upperBound + 1, utf16Column: range.upperBound + 1))
    }

    func link(_ range: Range<Int>, syntax: LinkSyntax = .wikilink, annotation: Range<Int>? = nil) -> LinkOccurrence {
        .init(
            syntax: syntax, target: "Target", alias: nil, fragment: nil,
            annotation: annotation.map { .init(markdown: "annotation", text: "annotation", span: span($0), contentSpan: span($0)) },
            isExternal: false, span: span(range), linkSpan: span(range))
    }

    func semantic(_ links: [LinkOccurrence]) -> MarkdownSemanticDocument {
        .init(
            fingerprint: DocumentFingerprint(content: String(repeating: "x", count: 512)),
            blocks: [], headings: [], callouts: [], footnoteDefinitions: [], footnoteReferences: [], mathExpressions: [], links: links, diagnostics: [])
    }

    func segment(_ text: String, field: SearchMatchedField, mappings: [SearchSegmentOffset]) -> SearchTextSegment {
        .init(
            field: field, ordinal: 17, text: "Original source-facing segment", normalizedText: text,
            sourceRange: .init(utf16LowerBound: 0, utf16UpperBound: 512, line: 1, column: 1, endLine: 1, endColumn: 513),
            offsetMap: mappings, relatedRankingText: ["untouched": "Existing unsupported field material"])
    }

    func expectLegacy(_ segment: SearchTextSegment, links: [LinkOccurrence], label: String) {
        let semantic = semantic(links)
        let actual = segment.attributingRelatedContent(using: RelatedContentSourceAttribution(in: semantic))
        let expected = legacyAttribution(segment, in: semantic)
        #expect(actual == expected, "\(label), \(segment.field)")
        for key in Set(actual.relatedRankingText.keys).union(expected.relatedRankingText.keys) {
            // String equality admits canonically equivalent spellings; ranking
            // material and its persisted digest must retain the same exact bytes.
            #expect(actual.relatedRankingText[key].map { Data($0.utf8) } == expected.relatedRankingText[key].map { Data($0.utf8) })
        }
    }

    /// Independent reference copied from the prior linear scan. Keep this
    /// character/map/overlap rule separate from the production interval lookup.
    func legacyAttribution(_ segment: SearchTextSegment, in semantic: MarkdownSemanticDocument) -> SearchTextSegment {
        let base: RelatedContentRankingField
        switch segment.field {
        case .linkAnnotation: base = .annotation
        case .title, .alias: base = .title
        case .tag: base = .keyword
        case .summary: base = .summary
        case .heading: base = .heading
        case .body, .footnote, .callout: base = .body
        default: return segment
        }
        let links = semantic.links.filter { $0.syntax == .wikilink }
        let annotations = semantic.links.compactMap(\.annotation)
        var fields: [String: String] = [:]
        var previous: RelatedContentRankingField?
        var offset = 0
        var mapIndex = 0
        for character in segment.normalizedText {
            let end = offset + String(character).utf16.count
            while mapIndex < segment.offsetMap.count && segment.offsetMap[mapIndex].normalizedUTF16UpperBound <= offset {
                mapIndex += 1
            }
            let mapping = mapIndex < segment.offsetMap.count ? segment.offsetMap[mapIndex] : nil
            var attributed: RelatedContentRankingField? = base
            if let mapping, let source = mapping.sourceUTF16Range(forNormalizedUTF16Range: offset..<end) {
                if base != .annotation && annotations.contains(where: { $0.span.utf16Range.overlaps(source) }) {
                    attributed = nil
                } else if base == .body && links.contains(where: { $0.linkSpan.utf16Range.overlaps(source) }) {
                    attributed = .link
                }
            }
            if let attributed {
                if previous != attributed { fields[attributed.rawValue, default: ""] += " " }
                fields[attributed.rawValue, default: ""].append(character)
            }
            previous = attributed
            offset = end
        }
        return .init(
            field: segment.field, ordinal: segment.ordinal, text: segment.text, normalizedText: segment.normalizedText,
            sourceRange: segment.sourceRange, offsetMap: segment.offsetMap, relatedRankingText: fields)
    }
}
