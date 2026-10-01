import Foundation
import ScholiumContracts
import Testing

struct SearchDiagnosticContractTests {
    @Test("Diagnostic transport preserves typed parameters, original text, and source span")
    func transportRoundTrip() throws {
        let diagnostic = SearchQueryDiagnostic(
            reason: .ambiguousLinkIdentity(
                identity: "Review", candidates: ["Analyses/Review.md", "Topics/审阅.md"]),
            message: "Original protocol diagnostic, not an interface key.",
            utf16LowerBound: 3, utf16UpperBound: 24)
        let encoded = try JSONEncoder().encode(diagnostic)
        #expect(try JSONDecoder().decode(SearchQueryDiagnostic.self, from: encoded) == diagnostic)
        let payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(payload["code"] as? String == "ambiguousIdentity")
        #expect(payload["message"] as? String == diagnostic.message)

        var inconsistent = payload
        inconsistent["code"] = "unsupportedSyntax"
        let malformed = try JSONSerialization.data(withJSONObject: inconsistent)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SearchQueryDiagnostic.self, from: malformed)
        }
    }

    @Test("Distinct syntax failures sharing one code retain their specific reason")
    func distinctReasons() throws {
        let property = try #require(SearchQueryParser.parse("property:key=value*").diagnostics.first)
        let regex = try #require(SearchQueryParser.parse("/value/").diagnostics.first)
        let nestedField = try #require(SearchQueryParser.parse("title:(author:Smith)").diagnostics.first)
        #expect(property.code == .unsupportedSyntax && regex.code == .unsupportedSyntax)
        #expect(property.reason == .propertyPrefixUnsupported)
        #expect(regex.reason == .unsupportedPatternSyntax)
        #expect(nestedField.reason == .inheritedFieldOverride)
        #expect(property.message == "Property equality is exact and does not support prefixes.")
        #expect(regex.message == "Regular-expression, fuzzy, and range syntax are not supported.")
    }
}
