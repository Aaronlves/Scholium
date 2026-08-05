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

    @Test("Incomplete Citation Method documents fail closed")
    func incompleteCitationMethodDocument() {
        let source = Data(#"{"schemaVersion":1,"activeCitationStyle":"apa-7"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ResearchCitationMethodDocument.self,
                from: source
            )
        }
    }

    @Test("Current Citation Method documents reject unknown fields")
    func strictCitationMethodDocuments() {
        let id = UUID().uuidString
        let unknownCitation = Data(
            #"{"schemaVersion":1,"triptychID":"\#(id)","activeCitationStyle":null,"future":true}"#.utf8
        )
        #expect(throws: ResearchCitationMethodContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchCitationMethodDocument.self,
                from: unknownCitation
            )
        }
    }

    @Test("Unsupported citation styles fail closed")
    func unsupportedCitationStyle() {
        #expect(throws: ResearchCitationMethodContractError.self) {
            _ = try ResearchCitationMethodDocument(
                triptychID: UUID(),
                activeCitationStyle: "invented-style"
            )
        }
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
