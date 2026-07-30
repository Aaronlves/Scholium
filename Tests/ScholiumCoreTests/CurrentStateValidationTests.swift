import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Current state validation")
struct CurrentStateValidationTests {
    @Test("A malformed present window field fails closed without rewriting its file")
    func malformedWindowField() async throws {
        let root = temporaryDirectory(named: "malformed-window")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let directory = root.appendingPathComponent("Window Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = Data(#"{"id":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","selectedDocument":"invalid"}"#.utf8)
        let target = directory.appendingPathComponent("\(id.uuidString).json")
        try source.write(to: target)
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)

        await #expect(throws: DecodingError.self) {
            _ = try await store.load(id: id)
        }
        #expect(try Data(contentsOf: target) == source)
    }

    @Test("An unknown persisted vault role fails closed")
    func unknownVaultRole() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VaultRole.self, from: Data(#""future_role""#.utf8))
        }
    }

    @Test("Retired replacement Practice fields fail closed")
    func retiredReplacementPractice() {
        let source = Data(#"{"package_id":"practices","practice_id":"reviewer","application":"replace"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ResearchPracticeSelection.self, from: source)
        }
    }

    @Test("Incomplete Citation Method documents fail closed")
    func incompleteCitationMethodDocument() {
        let source = Data(#"{"schema_version":1,"package_id":"citations"}"#.utf8)
        #expect(throws: ResearchSkillBindingError.self) {
            _ = try JSONDecoder().decode(
                ResearchCitationMethodDocument.self,
                from: source
            )
        }
    }

    @Test("Current capability Method documents reject unknown and future fields")
    func strictCapabilityMethodDocuments() {
        let unknownCitation = Data(
            #"{"schema_version":1,"package_id":null,"citation_style":null,"future":true}"#.utf8
        )
        #expect(throws: ResearchSkillBindingError.self) {
            _ = try JSONDecoder().decode(
                ResearchCitationMethodDocument.self,
                from: unknownCitation
            )
        }

        let futureBibliography = Data(
            #"{"schema_version":2,"package_id":null}"#.utf8
        )
        #expect(throws: ResearchSkillBindingError.self) {
            _ = try JSONDecoder().decode(
                ResearchBibliographyMethodDocument.self,
                from: futureBibliography
            )
        }
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
