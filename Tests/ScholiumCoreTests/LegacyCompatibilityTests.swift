import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Legacy read compatibility fixtures")
struct LegacyCompatibilityTests {
    private struct RoleSpelling: Decodable {
        let spelling: String
        let canonical: String
    }

    @Test("A sparse pre-Triptych window snapshot decodes without rewriting its file")
    func sparseWindowSnapshot() async throws {
        let root = temporaryDirectory(named: "legacy-window")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let directory = root.appendingPathComponent("Window Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try fixtureData("window-session-v0", extension: "json")
        let target = directory.appendingPathComponent("\(id.uuidString).json")
        try source.write(to: target)

        let snapshot = try #require(try await WindowSessionSnapshotStore(
            applicationSupportURL: root
        ).load(id: id))

        #expect(snapshot.triptychID == nil)
        #expect(snapshot.selectedDocument == VaultQualifiedNoteID(
            vaultID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            relativePath: "Legacy Note.md"
        ))
        #expect(snapshot.documentModes.isEmpty)
        #expect(snapshot.scrollPositions.isEmpty)
        #expect(snapshot.inspectorMode == "incoming")
        #expect(snapshot.searchState == SearchWorkspaceState())
        #expect(snapshot.contentDestination == .document)
        #expect(try Data(contentsOf: target) == source)
    }

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

    @Test("Every retained legacy vault-role spelling decodes and re-encodes canonically")
    func vaultRoleSpellings() throws {
        let fixtures = try JSONDecoder().decode(
            [RoleSpelling].self,
            from: fixtureData("vault-role-spellings", extension: "json")
        )

        for fixture in fixtures {
            let quoted = try JSONEncoder().encode(fixture.spelling)
            let role = try JSONDecoder().decode(VaultRole.self, from: quoted)
            #expect(role.rawValue == fixture.canonical)
            #expect(try JSONDecoder().decode(
                String.self,
                from: JSONEncoder().encode(role)
            ) == fixture.canonical)
        }
    }

    @Test("A search state written before role filters receives additive defaults")
    func sparseSearchState() throws {
        let state = try JSONDecoder().decode(
            SearchWorkspaceState.self,
            from: Data(#"{"query":"legacy","scope":"currentVault"}"#.utf8)
        )

        #expect(state.query == "legacy")
        #expect(state.scope == .currentVault)
        #expect(state.scope.canonical == .currentVault)
        #expect(state.selectedRoles.isEmpty)
        #expect(state.selectedResultID == nil)
    }

    @Test("Every retired search scope remains readable and canonicalizes to a current scope")
    func retiredSearchScopes() throws {
        let expectations: [SearchPresentationScope: SearchPresentationScope] = [
            .currentNote: .thisNote,
            .currentVault: .currentVault,
            .allWorkspace: .triptych,
            .selectedRoles: .triptych,
        ]

        for (legacy, canonical) in expectations {
            let state = try JSONDecoder().decode(
                SearchWorkspaceState.self,
                from: Data(#"{"scope":"\#(legacy.rawValue)"}"#.utf8)
            )
            #expect(state.scope == legacy)
            #expect(state.scope.canonical == canonical)
        }
        #expect(SearchPresentationScope.visibleModes == [.thisNote, .currentVault, .triptych])
    }

    @Test("An unknown persisted vault role fails closed")
    func unknownVaultRole() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VaultRole.self, from: Data(#""future_role""#.utf8))
        }
    }

    @Test("A v0 Triptych receives deterministic identity defaults without rewriting input")
    func legacyTriptychDefaults() throws {
        let source = try fixtureData("triptych-v0", extension: "json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let triptych = try decoder.decode(ScholiumTriptych.self, from: source)

        #expect(triptych.id == triptych.outputVaultID)
        #expect(triptych.name == "Triptych")
        #expect(triptych.createdAt == .distantPast)
        #expect(triptych.updatedAt == .distantPast)
        #expect(try fixtureData("triptych-v0", extension: "json") == source)
    }

    @Test("Legacy schema aliases remain semantic projections over exact Markdown")
    func legacySchemaAliases() throws {
        let source = try fixtureData("analysis-legacy-aliases", extension: "md")
        let rawSource = try #require(String(data: source, encoding: .utf8))
        let document = NoteDocument(relativePath: "Imported/Legacy Analysis.md", rawContent: rawSource)

        #expect(document.rawContent == rawSource)
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .sourceCorpus,
            frontmatter: document.parsedFrontmatter,
            relativePath: document.relativePath
        ) == .paperAnalysisV1)
        #expect(TriptychProperty.value(for: "type", in: document.parsedFrontmatter) == .string("article"))
        #expect(TriptychProperty.value(for: "status", in: document.parsedFrontmatter) == .string("complete"))
        #expect(TriptychProperty.value(for: "updated", in: document.parsedFrontmatter) == .string("2025-02-03"))
        #expect(TriptychProperty.value(for: "relevance", in: document.parsedFrontmatter) == .integer(8))
        #expect(document.parsedFrontmatter["unknown_nested"] == .object(["keep": .boolean(true)]))
        #expect(Data(document.rawContent.utf8) == source)
    }

    @Test("Every retained property alias is readable while a canonical key takes precedence")
    func completePropertyAliasMatrix() {
        for (canonical, aliases) in TriptychProperty.legacyAliases {
            for alias in aliases {
                let legacyValue = YAMLValue.string("legacy-\(alias)")
                let legacyOnly = [alias: legacyValue]
                #expect(TriptychProperty.value(for: canonical, in: legacyOnly) == legacyValue)
                #expect(TriptychProperty.legacyKey(for: canonical, in: legacyOnly) == alias)

                let canonicalValue = YAMLValue.string("canonical-\(canonical)")
                let mixed = [canonical: canonicalValue, alias: legacyValue]
                #expect(TriptychProperty.value(for: canonical, in: mixed) == canonicalValue)
            }
        }
    }

    private func fixtureData(_ name: String, extension fileExtension: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LegacyCompatibility", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(fileExtension)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
