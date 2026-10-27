import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related candidate row hydration")
struct RelatedContentRowHydrationTests {
    @Test("Batched cursors retain distinct metadata and lexical payloads across multiple batches")
    func metadataAndPayloadStayWithTheirSelectedRow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            isolatedDatabaseURL: fixture.root.appendingPathComponent("search.sqlite"),
            triptychID: UUID(), vaults: fixture.vaults)
        do {
            let rows = fixture.rows
            try #require(rows.count == 144)
            try #require(Set(rows.map(\.fingerprint)).count == rows.count)
            let expected = Dictionary(uniqueKeysWithValues: rows.map { ($0.note, $0) })
            // Input paths ascend, while their filename-owned titles descend.
            // Within each vault this also opposes publication's document-key order.
            #expect(rows[0].title == "Title144 – 書000")
            #expect(rows[143].title == "Title001 – 書143")
            let generation = try await index.synchronize(fixture.documents(rows: rows)).generation
            let request = fixture.request
            let response = try await index.relatedMaterialSourceCandidates(request)

            #expect(response.requestID == request.id)
            #expect(response.seedFingerprint == request.seed.fingerprint)
            #expect(response.freshnessToken == .triptych(generation))
            #expect(response.availability == .current(generation))
            #expect(response.state == .current)
            // Core supplies the complete lexical pool even with a small display limit.
            #expect(response.lexicalCandidates.count == 144)
            #expect(Set(response.lexicalCandidates.map(\.note)) == Set(expected.keys))
            #expect(response.lexicalHasMore)
            for candidate in response.lexicalCandidates {
                let row = try #require(expected[candidate.note])
                #expect(candidate.vaultRole == row.role)
                #expect(candidate.title == row.title)
                #expect(candidate.fingerprint == row.fingerprint)
                #expect(candidate.graphContext == nil)
                guard case .lexicalOverlap(let reason) = candidate.reason else {
                    Issue.record("An eligible row must retain its lexical reason")
                    continue
                }
                // Each row spells a different subset of eight explicit terms.
                // These expectations come from authored fixture tokens, not the
                // projection decoder, matcher, scorer, or a second query result.
                let fields: Set<SearchMatchedField> = row.identityAlias ? [.alias, .body] : [.body]
                #expect(Set(reason.matchedFields) == fields)
                #expect(reason.matchedFields.count == fields.count)
                #expect(reason.seedMatches.count == 2)
                let focused = try #require(reason.seedMatches.first { $0.seedKind == .researchRequest })
                #expect(Set(focused.terms) == Set(row.terms))
                #expect(focused.terms.count == row.terms.count)
                let background = try #require(reason.seedMatches.first { $0.seedKind == .sourceNote })
                #expect(background.terms == ["hydrationbackground"])
            }

            // Three explicitly authored aliases exercise the identity hydrator
            // after scanning the complete >128-row, three-role corpus. The
            // expected order is written out; no production comparator is reused.
            #expect(
                response.identityCandidates.map(\.title) == [
                    "Title001 – 書143", "Title073 – 書071", "Title144 – 書000",
                ])
            #expect(response.identityCandidates.map(\.note) == [rows[143].note, rows[71].note, rows[0].note])
            #expect(!response.identityHasMore)
            for candidate in response.identityCandidates {
                let row = try #require(expected[candidate.note])
                #expect(row.identityAlias)
                #expect(candidate.vaultRole == row.role)
                #expect(candidate.title == row.title)
                #expect(candidate.fingerprint == row.fingerprint)
                #expect(
                    candidate.reason
                        == .identityMention(
                            .init(mentions: [
                                .init(seedKind: .researchRequest, identityKind: .alias, matchedIdentity: row.alias)
                            ])))
                #expect(candidate.graphContext == nil)
            }
            // Reusing the hydrated rows must retain the independently checked
            // response when the lexical memo is now warm.
            #expect(try await index.relatedMaterialSourceCandidates(request) == response)
            await index.shutdown()
        } catch {
            await index.shutdown()
            throw error
        }
    }

    @Test("Unicode title ties and reversed paths preserve candidates across permuted publication")
    func publicationOrderDoesNotChangeCandidates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let canonicalURL = fixture.root.appendingPathComponent("canonical.sqlite")
        let permutedURL = fixture.root.appendingPathComponent("permuted.sqlite")
        let canonical = try TriptychSearchIndex(isolatedDatabaseURL: canonicalURL, triptychID: UUID(), vaults: fixture.vaults)
        let permuted: TriptychSearchIndex
        do {
            permuted = try TriptychSearchIndex(isolatedDatabaseURL: permutedURL, triptychID: UUID(), vaults: fixture.vaults)
        } catch {
            await canonical.shutdown()
            throw error
        }
        do {
            let titles = ["Zulu", "Élan", "E\u{301}lan", "書", "\u{E000}", "😀", "Alpha", "Ω"]
            let rows = fixture.rows.enumerated().map { ordinal, row in
                let title = titles[ordinal % titles.count]
                return Row(
                    note: .init(vaultID: row.note.vaultID, relativePath: "\(144 - ordinal)/\(title).md"),
                    role: row.role, title: title, alias: row.alias, identityAlias: row.identityAlias,
                    terms: row.terms, source: row.source, fingerprint: row.fingerprint)
            }
            let documents = fixture.documents(rows: rows)
            _ = try await canonical.synchronize(documents)
            // Retaining the first published half gives identical final sources
            // different row IDs. Reversing synchronize's array alone would not:
            // publication already canonicalizes its upserts.
            _ = try await permuted.synchronize(Array(documents.suffix(74)))
            _ = try await permuted.synchronize(documents)
            let canonicalReader = try SearchSQLiteDatabase(path: canonicalURL.path, readOnly: true)
            defer { canonicalReader.close() }
            let permutedReader = try SearchSQLiteDatabase(path: permutedURL.path, readOnly: true)
            defer { permutedReader.close() }
            func rowOrder(_ reader: SearchSQLiteDatabase) throws -> [String] {
                var result: [String] = []
                try reader.query("SELECT vault_id, relative_path FROM search_documents ORDER BY id;") { row in
                    result.append("\(row.text(at: 0) ?? "")/\(row.text(at: 1) ?? "")")
                }
                return result
            }
            #expect(try rowOrder(canonicalReader) != rowOrder(permutedReader))
            let expected = Dictionary(uniqueKeysWithValues: rows.map { ($0.note, $0) })
            let request = fixture.request
            let first = try await canonical.relatedMaterialSourceCandidates(request)
            let second = try await permuted.relatedMaterialSourceCandidates(request)
            #expect(first.lexicalCandidates == second.lexicalCandidates)
            #expect(first.identityCandidates == second.identityCandidates)
            #expect(first.lexicalHasMore == second.lexicalHasMore)
            #expect(first.identityHasMore == second.identityHasMore)
            for response in [first, second] {
                #expect(response.lexicalCandidates.count == 144)
                #expect(Set(response.lexicalCandidates.map(\.note)) == Set(expected.keys))
                for candidate in response.lexicalCandidates {
                    let row = try #require(expected[candidate.note])
                    #expect(candidate.title == row.title)
                    #expect(candidate.fingerprint == row.fingerprint)
                    #expect(candidate.vaultRole == row.role)
                    guard case .lexicalOverlap(let reason) = candidate.reason else {
                        Issue.record("A candidate lost its authored lexical explanation")
                        continue
                    }
                    let focused = try #require(reason.seedMatches.first { $0.seedKind == .researchRequest })
                    #expect(Set(focused.terms) == Set(row.terms))
                }
            }
            await canonical.shutdown()
            await permuted.shutdown()
        } catch {
            await canonical.shutdown()
            await permuted.shutdown()
            throw error
        }
    }

    private struct Row {
        let note: VaultQualifiedNoteID
        let role: VaultRole
        let title: String
        let alias: String
        let identityAlias: Bool
        let terms: [String]
        let source: String
        let fingerprint: DocumentFingerprint
    }

    private struct Fixture {
        let root: URL
        let analyses = RegisteredVault(name: "Hydration Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/hydration/analyses")
        let topics = RegisteredVault(name: "Hydration Topics", role: .topicKnowledge, canonicalPath: "/fixtures/hydration/topics")
        let works = RegisteredVault(name: "Hydration Works", role: .draftProject, canonicalPath: "/fixtures/hydration/works")
        let other = RegisteredVault(name: "Excluded", role: .other, canonicalPath: "/fixtures/hydration/excluded")
        let terms = ["hydramber", "hydrbronze", "hydrcobalt", "hydrdenim", "hydrember", "hydrfern", "hydrgranite", "hydrhazel"]

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/related-content-row-hydration/\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var vaults: [RegisteredVault] { [analyses, topics, works, other] }

        var rows: [Row] {
            let eligible = [analyses, topics, works]
            return (0..<144).map { ordinal in
                let vault = eligible[ordinal % eligible.count]
                let suffix = padded(ordinal)
                let title = "Title\(padded(144 - ordinal)) – 書\(suffix)"
                let path = "\(suffix)/\(title).md"
                // Nonzero eight-bit subsets give every row a distinct reason,
                // while staying inside the eight-term explanation limit.
                let mask = ordinal + 1
                let rowTerms = terms.enumerated().compactMap { bit, term in
                    mask & (1 << bit) == 0 ? nil : term
                }
                let identityAlias = ordinal == 0 || ordinal == 71 || ordinal == 143
                let alias: String
                switch ordinal {
                case 0: alias = "hydramber"
                case 71: alias = "hydrdenim"
                case 143: alias = "hydrember"
                default: alias = "RowAlias\(suffix)é"
                }
                let source = """
                    ---
                    aliases: ["\(alias)"]
                    hydration_marker: "metadata \(suffix)"
                    ---
                    hydrationbackground \(rowTerms.joined(separator: " "))

                    Exact source stamp \(suffix), café 書.

                    """
                return Row(
                    note: .init(vaultID: vault.id, relativePath: path), role: vault.role,
                    title: title, alias: alias, identityAlias: identityAlias, terms: rowTerms,
                    source: source, fingerprint: DocumentFingerprint(content: source))
            }
        }

        var request: RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: works.id, relativePath: "SeedHydration.md"),
                    source: "hydrationbackground",
                    focuses: [.init(kind: .researchRequest, text: "Explicit row terms", literalAlternatives: terms)]),
                identityLimit: 3, lexicalLimit: 1)
        }

        func documents(rows: [Row]) -> [SearchIndexDocument] {
            var documents = rows.map { row in
                let vault = vaults.first { $0.id == row.note.vaultID }!
                return SearchIndexDocument(
                    vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                    document: .init(relativePath: row.note.relativePath, rawContent: row.source))
            }
            documents.append(
                .init(
                    vaultID: works.id, vaultName: works.name, vaultRole: works.role,
                    document: .init(relativePath: "SeedHydration.md", rawContent: "hydrationbackground")))
            documents.append(
                .init(
                    vaultID: other.id, vaultName: other.name, vaultRole: other.role,
                    document: .init(relativePath: "Excluded.md", rawContent: "hydrationbackground \(terms.joined(separator: " "))")))
            return documents
        }

        private func padded(_ value: Int) -> String {
            let value = String(value)
            return String(repeating: "0", count: max(0, 3 - value.count)) + value
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
