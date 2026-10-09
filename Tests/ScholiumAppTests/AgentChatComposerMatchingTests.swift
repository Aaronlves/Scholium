import Foundation
import Testing

@testable import ScholiumApp

@Suite("Composer matching Foundation parity") @MainActor
struct AgentChatComposerMatchingTests {
    @Test("Each field preserves exact, prefix and substring tiers and original order")
    func tiersAndFields() {
        let candidates = [
            candidate("contains-title", title: "Prior needle context"),
            candidate("prefix-title", title: "Needle title"),
            candidate("exact-title", title: "Needle"),
            candidate("prefix-detail", title: "Other", detail: "Needle detail"),
            candidate("exact-detail", title: "Other", detail: "Needle"),
            candidate("needle", title: "Other"),
            candidate("needle-prefix-id", title: "Other"),
            candidate("contains-detail", title: "Other", detail: "Prior needle detail"),
            candidate("last-exact-title", title: "Needle"),
            candidate("absent", title: "Unrelated"),
        ]
        let expected = [
            "exact-title", "exact-detail", "needle", "last-exact-title", "prefix-title",
            "prefix-detail", "needle-prefix-id", "contains-title", "contains-detail",
        ]
        #expect(AgentChatComposerCatalog.matching(candidates, query: " NEEDLE ").map(\.id) == expected)
        #expect(AgentChatComposerCatalog.matching(candidates, query: " \r\n\t ").map(\.id) == candidates.map(\.id))
        #expect(AgentChatComposerCatalog.matching(candidates, query: "unmatchedfixtureterm").isEmpty)
    }

    @Test(
        "Unicode matching retains the previous compare and anchored-search semantics",
        arguments: [
            ("café", ["café", "CAFÉ", "cafe\u{301}", "cafe"]),
            ("cafe\u{301}", ["café", "CAFÉ", "cafe\u{301}"]),
            ("İstanbul", ["İstanbul", "istanbul", "ISTANBUL", "i\u{307}stanbul"]),
            ("ıstanbul", ["ıstanbul", "istanbul", "ISTANBUL"]),
            ("ΟΣ", ["ΟΣ", "ος", "οσ", "ο"]),
            ("ς", ["ς", "σ", "Σ"]),
            ("Straße", ["Straße", "STRASSE", "strasse", "STRAẞE"]),
            ("ﬀ", ["ﬀ", "ff", "FF", "f"]),
            ("Kelvin", ["Kelvin", "Kelvin", "KELVIN", "k"]),
            ("自由agency", ["自由agency", "自由AGENCY", "自由", "agency"]),
            ("理由与行动", ["理由与行动", "理由", "行动"]),
            ("👩‍🔬 research", ["👩‍🔬 research", "👩‍🔬", "👩", "research"]),
            ("😀 agency", ["😀 agency", "😀", "agency"]),
            ("co\u{00AD}operate", ["co\u{00AD}operate", "cooperate", "COOPERATE", "\u{00AD}"]),
            ("co\u{200B}operate", ["co\u{200B}operate", "cooperate", "operate", "\u{200B}"]),
            ("\u{FEFF}agency", ["\u{FEFF}agency", "agency", "AGENCY", "\u{FEFF}"]),
            ("\u{301}agency", ["\u{301}agency", "agency", "AGENCY", "\u{301}"]),
            ("a\u{20DD}gency", ["a\u{20DD}gency", "agency", "a", "gency"]),
            ("a\u{200D}b", ["a\u{200D}b", "ab", "a", "b"]),
            ("\u{00AD}agency\u{200B}", ["\u{00AD}agency\u{200B}", "agency", "\u{00AD}agency"]),
        ])
    func unicodeParity(_ fixture: (source: String, queries: [String])) {
        // Mixed field placement and deliberately unsorted match tiers expose
        // promotion differences as well as missed matches. IDs remain distinct.
        let candidates = [
            candidate("contains", title: "Before " + fixture.source + " after"),
            candidate("prefix", title: fixture.source + " suffix"),
            candidate("exact", title: fixture.source),
            candidate("detail", title: "Other", detail: fixture.source),
            candidate(fixture.source, title: "Other"),
            candidate("later-exact", title: fixture.source),
            candidate("unmatched", title: "Unrelated"),
        ]
        for query in fixture.queries + [" \r\n\t ", "missingfixtureterm"] {
            let expected = frozenMatching(candidates, query: query).map(\.id)
            let actual = AgentChatComposerCatalog.matching(candidates, query: query).map(\.id)
            #expect(actual == expected, "Source \(fixture.source.debugDescription), query \(query.debugDescription)")
        }
    }

    private func candidate(_ id: String, title: String, detail: String = "") -> AgentChatComposerCandidate {
        .init(id: id, title: title, detail: detail, symbol: "doc.text", action: .file)
    }

    /// Frozen pre-optimization Foundation operations. This oracle does not use
    /// AgentChatSearch or infer exact/prefix status from an unanchored range.
    private func frozenMatching(_ candidates: [AgentChatComposerCandidate], query: String) -> [AgentChatComposerCandidate] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return candidates }
        var exact: [AgentChatComposerCandidate] = []
        var prefix: [AgentChatComposerCandidate] = []
        var other: [AgentChatComposerCandidate] = []
        for candidate in candidates {
            let fields = [candidate.title, candidate.id, candidate.detail]
            if fields.contains(where: { $0.compare(needle, options: .caseInsensitive) == .orderedSame }) {
                exact.append(candidate)
            } else if fields.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .anchored]) != nil }) {
                prefix.append(candidate)
            } else if fields.contains(where: { $0.range(of: needle, options: .caseInsensitive) != nil }) {
                other.append(candidate)
            }
        }
        return exact + prefix + other
    }
}
