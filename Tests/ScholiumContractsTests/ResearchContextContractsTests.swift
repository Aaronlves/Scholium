import Foundation
import ScholiumContracts
import Testing

@Suite("Research Context source-preserving contracts")
struct ResearchContextContractsTests {
    @Test("Closed clauses carry no Run or Triptych authority and old free arrays fail closed")
    func closedClauseRequest() throws {
        let clause = try ResearchContextClause(
            kind: .readNote,
            query: "path:Inheritance.md",
            sectionHeading: "Objections"
        )
        let request = try ResearchContextRequest(clauses: [clause])
        let query = try ResearchContextQuery(
            request: request,
            runID: UUID(),
            triptychID: UUID()
        )

        #expect(try roundTrip(request) == request)
        #expect(try roundTrip(query) == query)
        #expect(query.clauses == [clause])
        let object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any])
        #expect(object["runID"] == nil)
        #expect(object["triptychID"] == nil)
        #expect(object["sourceKinds"] == nil)
        #expect(object["purposes"] == nil)
        #expect(object["schema_version"] as? Int
            == ResearchContextRequest.currentSchemaVersion)
        #expect(object["schemaVersion"] == nil)
        let encodedClause = try #require(
            (object["clauses"] as? [[String: Any]])?.first
        )
        #expect(encodedClause["schema_version"] as? Int
            == ResearchContextClause.currentSchemaVersion)
        #expect(encodedClause["section_heading"] as? String == "Objections")
        #expect(encodedClause["use_eligibility"] == nil)
        #expect(encodedClause["schemaVersion"] == nil)

        var obsolete = object
        obsolete.removeValue(forKey: "clauses")
        obsolete["sourceKinds"] = ["note"]
        obsolete["purposes"] = ["read"]
        obsolete["query"] = "path:Inheritance.md"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                ResearchContextRequest.self,
                from: JSONSerialization.data(withJSONObject: obsolete)
            )
        }
    }

    @Test("Clause shapes, scopes, and continuations are closed")
    func clausesFailClosed() throws {
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextClause(
                kind: .inspectResearcherState,
                query: "invented query"
            )
        }
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextClause(
                kind: .discoverNote
            )
        }
        let material = try ResearchContextClause(kind: .inspectMaterials)
        let materialBytes = try JSONEncoder().encode(material)
        var retiredMaterial = try #require(
            JSONSerialization.jsonObject(with: materialBytes) as? [String: Any]
        )
        #expect(retiredMaterial["schema_version"] as? Int
            == ResearchContextClause.currentSchemaVersion)
        retiredMaterial["schema_version"] =
            ResearchContextClause.currentSchemaVersion - 1
        #expect(throws: ResearchContextContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContextClause.self,
                from: JSONSerialization.data(withJSONObject: retiredMaterial)
            )
        }
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextClause(
                kind: .inspectMaterials,
                query: "generic material search is forbidden"
            )
        }
        let clause = try ResearchContextClause(
            kind: .readNote,
            query: "path:Inheritance.md"
        )
        let cursor = try ResearchContextPageCursor(
            clauseID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Inheritance.md"),
            fingerprint: DocumentFingerprint(content: "source"),
            sourceRange: SearchSourceRange(
                utf16LowerBound: 0,
                utf16UpperBound: 6,
                line: 1,
                column: 1,
                endLine: 1,
                endColumn: 7
            ),
            pageStartUTF8Offset: 0,
            nextUTF8Offset: 1,
            binding: DocumentFingerprint(content: "binding"),
            pageDigest: DocumentFingerprint(content: "page")
        )
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextClause(
                id: clause.id,
                kind: .readNote,
                query: clause.query,
                cursor: cursor
            )
        }
    }

    @Test("Exact source preserves BOM, CRLF, whitespace, final newlines, and mixed scripts")
    func exactSourceRoundTrip() throws {
        let source = "\u{FEFF}  标题\r\nemoji 😀\r\nRTL العربية\r\n\r\n"
        let exact = try ResearchContextExactSource(content: source)
        let decoded = try roundTrip(exact)
        #expect(decoded.content == source)
        #expect(Data(decoded.content.utf8) == Data(source.utf8))
        #expect(decoded.pageDigest == DocumentFingerprint(content: source))
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextExactSource(content: "a\0b")
        }
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextExactSource(
                content: String(repeating: "x", count: ResearchContextExactSource.maximumUTF8Count + 1)
            )
        }
    }

    @Test("A response preserves independent clause outcomes and stays within its page budget")
    func responseCarriesClauseOutcomes() throws {
        let fixture = Fixture()
        let discover = try ResearchContextClause(
            kind: .discoverNote,
            query: "inheritance"
        )
        let read = try ResearchContextClause(
            kind: .readNote,
            query: "path:Inheritance.md"
        )
        let query = try ResearchContextQuery(
            request: ResearchContextRequest(clauses: [discover, read]),
            runID: fixture.runID,
            triptychID: fixture.triptychID
        )
        let semantic = try ResearchContextResponseItem(
            clauseID: discover.id,
            sourceReference: try fixture.noteEnvelope(locator: .wholeObject),
            title: "Inheritance",
            contentKind: .searchSnippet,
            semanticContent: "A discovery lead."
        )
        let range = SearchSourceRange(
            utf16LowerBound: 0,
            utf16UpperBound: 8,
            line: 1,
            column: 1,
            endLine: 1,
            endColumn: 9
        )
        let exact = try ResearchContextResponseItem(
            clauseID: read.id,
            sourceReference: try fixture.noteEnvelope(locator: .sourceRange(range)),
            title: "Inheritance",
            contentKind: .noteDocument,
            exactSource: try ResearchContextExactSource(content: "current\n")
        )
        let response = try ResearchContextResponse(
            query: query,
            outcomes: [
                try ResearchContextClauseOutcome(
                    clause: discover,
                    availability: .current,
                    items: [semantic]
                ),
                try ResearchContextClauseOutcome(
                    clause: read,
                    availability: .partial,
                    items: [exact],
                    limitations: ["The exact source continues on a later page."],
                    hasMore: true,
                    nextCursor: try ResearchContextPageCursor(
                        clauseID: read.id,
                        note: VaultQualifiedNoteID(
                            vaultID: fixture.vaultID,
                            relativePath: "Inheritance.md"
                        ),
                        fingerprint: exact.sourceReference.fingerprint!,
                        sourceRange: range,
                        pageStartUTF8Offset: 0,
                        nextUTF8Offset: 8,
                        binding: query.paginationBinding(for: read),
                        pageDigest: exact.exactSource!.pageDigest
                    )
                ),
            ]
        )
        #expect(response.availability == .partial)
        #expect(response.items == [semantic, exact])
        #expect(semantic.evidenceEligibility == .referenceOnly)
        #expect(exact.evidenceEligibility == .researchEvidence)
        let encoded = try JSONEncoder().encode(response)
        #expect(encoded.count <= ResearchContextResponse.maximumEncodedByteCount)
        #expect(try roundTrip(response) == response)

        var tamperedExact = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(exact))
                as? [String: Any]
        )
        tamperedExact["evidence_eligibility"] = "reference_only"
        #expect(throws: ResearchContextContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContextResponseItem.self,
                from: JSONSerialization.data(withJSONObject: tamperedExact)
            )
        }
    }

    @Test("Invalid Query remains visible in global availability")
    func invalidQueryAvailabilityIsPreserved() throws {
        let fixture = Fixture()
        let clause = try ResearchContextClause(
            kind: .discoverNote,
            query: "malformed:"
        )
        let query = try ResearchContextQuery(
            request: ResearchContextRequest(clauses: [clause]),
            runID: fixture.runID,
            triptychID: fixture.triptychID
        )
        let response = try ResearchContextResponse(
            query: query,
            outcomes: [try ResearchContextClauseOutcome(
                clause: clause,
                availability: .invalidQuery,
                items: [],
                limitations: ["The query is not valid."]
            )]
        )
        #expect(response.availability == .invalidQuery)
        #expect(try roundTrip(response).availability == .invalidQuery)
    }

    @Test("Research Context schema 6 rejects Search structured match reasons")
    func structuredSearchReasonsFailClosed() throws {
        let fixture = Fixture()
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextResponseItem(
                clauseID: UUID(),
                sourceReference: fixture.noteEnvelope(locator: .wholeObject),
                title: "Inheritance",
                contentKind: .searchSnippet,
                semanticContent: "A structured discovery lead.",
                noteMatchReasons: [.structured(SearchStructuredMatch(
                    field: .has,
                    value: "broken-link",
                    excluded: false
                ))]
            )
        }
    }

    @Test("Material content is path-free typed Run evidence and matches its source envelope")
    func sourceMaterialContentRoundTrips() throws {
        let fixture = Fixture()
        let source = try ResearchSourceReference(
            identity: .zoteroAttachment(
                itemKey: "PARENT01",
                attachmentKey: "ATTACH02"
            ),
            displayName: "Bound Source.pdf",
            fingerprint: DocumentFingerprint(content: "source bytes")
        )
        let clause = try ResearchContextClause(kind: .inspectMaterials)
        let query = try ResearchContextQuery(
            request: ResearchContextRequest(clauses: [clause]),
            runID: fixture.runID,
            triptychID: fixture.triptychID
        )
        let envelope = try SourceReferenceEnvelope(
            sourceKind: .material,
            owner: .material(
                triptychID: fixture.triptychID,
                materialID: source.identity.id
            ),
            actorClass: .unknown,
            objectRole: .sourceMaterial,
            fingerprint: source.fingerprint,
            locator: .materialSource(source),
            authorizedScope: .triptych(
                runID: fixture.runID,
                triptychID: fixture.triptychID
            ),
            currentness: .current,
            evidentialLayer: .sourceMaterial,
            retrievalReason: .explicitSelection,
            materialLimitations: [
                "Source Material is evidence and its content author is not inferred."
            ]
        )
        let item = try ResearchContextResponseItem(
            clauseID: clause.id,
            sourceReference: envelope,
            title: source.displayName,
            contentKind: .sourceMaterial,
            materialContent: try ResearchContextMaterialContent(source: source)
        )
        let response = try ResearchContextResponse(
            query: query,
            outcomes: [try ResearchContextClauseOutcome(
                clause: clause,
                availability: .current,
                items: [item]
            )]
        )

        #expect(try roundTrip(response) == response)
        let encoded = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        #expect(encoded.contains("PARENT01"))
        #expect(encoded.contains("ATTACH02"))
        #expect(encoded.contains("\"evidence_eligibility\":\"research_evidence\""))
        #expect(!encoded.contains("file://"))
        #expect(!encoded.contains("bookmark"))

        let mismatched = try ResearchSourceReference(
            identity: .localFile(),
            displayName: "Different Source.pdf",
            fingerprint: source.fingerprint
        )
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextResponseItem(
                clauseID: clause.id,
                sourceReference: envelope,
                title: mismatched.displayName,
                contentKind: .sourceMaterial,
                materialContent: try ResearchContextMaterialContent(source: mismatched)
            )
        }
    }

    @Test("Wire responses reject clause and item overflows")
    func wireResponseLimitsFailClosed() throws {
        let fixture = Fixture()
        let clause = try ResearchContextClause(
            kind: .discoverNote,
            query: "inheritance",
            limit: ResearchContextClause.maximumLimit
        )
        let query = try ResearchContextQuery(
            request: ResearchContextRequest(clauses: [clause]),
            runID: fixture.runID,
            triptychID: fixture.triptychID
        )
        let baseItem = try ResearchContextResponseItem(
            clauseID: clause.id,
            sourceReference: try fixture.noteEnvelope(locator: .wholeObject),
            title: "Inheritance",
            contentKind: .searchSnippet,
            semanticContent: "A discovery lead."
        )
        let response = try ResearchContextResponse(
            query: query,
            outcomes: [try ResearchContextClauseOutcome(
                clause: clause,
                availability: .current,
                items: [baseItem]
            )]
        )
        var responseObject = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(response)
        ) as? [String: Any])
        let outcomeObject = try #require(responseObject["outcomes"] as? [[String: Any]])

        var tooManyOutcomes: [[String: Any]] = []
        for _ in 0...(ResearchContextRequest.maximumClauses) {
            var copy = outcomeObject[0]
            copy["clauseID"] = UUID().uuidString
            tooManyOutcomes.append(copy)
        }
        responseObject["outcomes"] = tooManyOutcomes
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                ResearchContextResponse.self,
                from: JSONSerialization.data(withJSONObject: responseObject)
            )
        }

        let itemObjects = try (0...ResearchContextClause.maximumLimit).map { _ in
            let item = try ResearchContextResponseItem(
                clauseID: clause.id,
                sourceReference: try fixture.noteEnvelope(locator: .wholeObject),
                title: "Inheritance",
                contentKind: .searchSnippet,
                semanticContent: "A discovery lead."
            )
            return try #require(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(item)
            ) as? [String: Any])
        }
        responseObject["outcomes"] = outcomeObject
        var itemOverflowOutcome = outcomeObject[0]
        itemOverflowOutcome["items"] = itemObjects
        responseObject["outcomes"] = [itemOverflowOutcome]
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                ResearchContextResponse.self,
                from: JSONSerialization.data(withJSONObject: responseObject)
            )
        }
    }

    @Test("Source-range locators validate exact UTF-16 positions including EOF")
    func locatorPositionsAreReversible() throws {
        let source = "\u{FEFF}A\r\n😀\n"
        let eof = try ResearchContextSourceLocator.sourceRange(SearchSourceRange(
            utf16LowerBound: source.utf16.count,
            utf16UpperBound: source.utf16.count,
            line: 3,
            column: 1,
            endLine: 3,
            endColumn: 1
        ))
        #expect(eof.isValid(in: source))
        let wrong = try ResearchContextSourceLocator.sourceRange(SearchSourceRange(
            utf16LowerBound: source.utf16.count,
            utf16UpperBound: source.utf16.count,
            line: 2,
            column: 1,
            endLine: 2,
            endColumn: 1
        ))
        #expect(!wrong.isValid(in: source))

        let surrogateInterior = try ResearchContextSourceLocator.sourceRange(
            SearchSourceRange(
                utf16LowerBound: 5,
                utf16UpperBound: 5,
                line: 2,
                column: 2,
                endLine: 2,
                endColumn: 2
            )
        )
        #expect(!surrogateInterior.isValid(in: source))
    }

    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private struct Fixture {
        let runID = UUID()
        let triptychID = UUID()
        let vaultID = UUID()

        func noteEnvelope(locator: ResearchContextSourceLocator) throws -> SourceReferenceEnvelope {
            try SourceReferenceEnvelope(
                sourceKind: .note,
                owner: .note(
                    triptychID: triptychID,
                    note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Inheritance.md"),
                    stableObjectIdentity: "note-inheritance"
                ),
                actorClass: .researcher,
                objectRole: .topic,
                vaultRole: .topicKnowledge,
                fingerprint: DocumentFingerprint(content: "current Topic bytes"),
                locator: locator,
                authorizedScope: .triptych(runID: runID, triptychID: triptychID),
                currentness: .current,
                evidentialLayer: .topicNote,
                retrievalReason: locator.kind == .wholeObject ? .canonicalSummary : .exactRead
            )
        }
    }
}
