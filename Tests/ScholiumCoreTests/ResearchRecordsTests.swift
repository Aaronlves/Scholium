import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Page anchors, Discuss, and Critique records")
struct ResearchRecordsTests {
    @Test("Comment anchors preserve full-file Unicode ranges and visible selection")
    func exactCommentAnchor() throws {
        let source = "---\r\ntitle: 測試\r\n---\r\n# Claim\r\nA 🧠 **reason** matters.\r\n"
        let document = NoteDocument(relativePath: "Note.md", rawContent: source)
        let selected = "reason"
        let range = try #require(source.range(of: selected))
        let lower = range.lowerBound.utf16Offset(in: source)
        let upper = range.upperBound.utf16Offset(in: source)
        let anchor = try #require(CommentAnchorBuilder.anchor(
            in: source,
            fingerprint: document.fingerprint,
            utf16Range: lower..<upper,
            selectedText: selected
        ))

        #expect(anchor.fingerprint == document.fingerprint)
        #expect(anchor.line == 5)
        #expect(anchor.endLine == 5)
        #expect(anchor.quotation == selected)
        #expect(anchor.utf16Range == lower..<upper)
        #expect(Data(source.utf8)[anchor.utf8Range] == Data(selected.utf8))
        #expect(anchor.contextBefore.hasSuffix("A 🧠 **"))
        #expect(anchor.contextAfter.hasPrefix("** matters."))
    }

    @Test("Read-mode selections map across Markdown punctuation to one exact source range")
    func renderedCommentAnchor() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "---\ntitle: Note\n---\nA **strong** claim matters.\n"
        )
        let anchor = try #require(CommentAnchorBuilder.anchor(
            forRenderedQuotation: "A strong claim matters.",
            in: document
        ))

        #expect(anchor.line == 4)
        #expect(anchor.quotation == "A **strong** claim matters.")
        #expect(anchor.selectedText == "A strong claim matters.")
        let bytes = Data(document.rawContent.utf8)[anchor.utf8Range]
        #expect(String(decoding: bytes, as: UTF8.self) == "A **strong** claim matters.")
    }

    @Test("Source comments derive visible marked-up text without global quotation guessing")
    func sourceCommentRenderedQuotation() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "**Repeated claim.**\n\nRepeated claim.\n"
        )
        let sourceSelection = try #require(document.rawContent.range(of: "**Repeated claim.**"))
        let sourceLower = sourceSelection.lowerBound.utf16Offset(in: document.rawContent)
        let sourceUpper = sourceSelection.upperBound.utf16Offset(in: document.rawContent)
        let anchor = try #require(CommentAnchorBuilder.anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: sourceLower..<sourceUpper
        ))

        #expect(anchor.quotation == "**Repeated claim.**")
        #expect(CommentAnchorBuilder.renderedQuotation(
            for: anchor,
            in: document
        ) == "Repeated claim.")
    }

    @Test("Read-mode context disambiguates repeated rendered quotations without guessing")
    func renderedCommentContextDisambiguation() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "First **claim** here.\n\nSecond **claim** there.\n"
        )
        #expect(CommentAnchorBuilder.anchor(
            forRenderedQuotation: "claim",
            in: document
        ) == nil)

        let anchor = try #require(CommentAnchorBuilder.anchor(
            forRenderedQuotation: "claim",
            contextBefore: "Second ",
            contextAfter: " there.",
            in: document
        ))
        #expect(anchor.line == 3)
        #expect(anchor.quotation == "claim")
    }

    @Test("Critique association is portable and remains bound to the Work revision")
    func critiqueAssociation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let registry = CritiqueRegistry(controlURL: control)
        let workID = UUID()
        let association = CritiqueAssociation(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: DocumentFingerprint(content: "draft"),
            critiqueRelativePath: "Critiques/Paper Critique.md"
        )
        try await registry.save(association)

        let reopened = CritiqueRegistry(controlURL: control)
        let loaded = try #require(await reopened.association(workNoteID: workID))
        #expect(loaded.critiqueRelativePath == "Critiques/Paper Critique.md")
        #expect(loaded.targetFingerprint == association.targetFingerprint)

        _ = try await reopened.movePath(
            noteID: workID,
            from: "Drafts/Paper.md",
            to: "Drafts/Renamed Paper.md"
        )
        _ = try await reopened.movePath(
            noteID: UUID(),
            from: "Critiques/Paper Critique.md",
            to: "Critiques/Renamed Critique.md"
        )
        let moved = try #require(await reopened.association(workNoteID: workID))
        #expect(moved.workRelativePath == "Drafts/Renamed Paper.md")
        #expect(moved.critiqueRelativePath == "Critiques/Renamed Critique.md")
        #expect(moved.targetFingerprint == association.targetFingerprint)
    }

    @Test("Critique Local-v3 handoff and findings reconciliation are idempotent")
    func critiqueLocalExecutionReconciliation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = CritiqueRegistry(
            controlURL: fixture.root.appendingPathComponent(".scholium")
        )
        let workID = UUID()
        let targetFingerprint = DocumentFingerprint(content: "# Work\n")
        let target = ResearchFunctionTarget(
            noteID: workID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Drafts/Paper.md"
            ),
            role: .work,
            fingerprint: targetFingerprint,
            title: "Paper"
        )
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(function: .critique, target: target),
            recordKind: .critique,
            preparedAt: Date(timeIntervalSince1970: 10)
        )
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: target.note.relativePath,
            targetFingerprint: targetFingerprint,
            critiqueRelativePath: "Critiques/Paper Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: snapshot.runID,
            functionSnapshot: snapshot,
            functionInstructions: "Prepared Critique instructions."
        )

        let detached = try await registry.detachFunctionEvidence(
            runID: snapshot.runID,
            matching: snapshot
        )
        let repeatedDetach = try await registry.detachFunctionEvidence(
            runID: snapshot.runID,
            matching: snapshot
        )
        #expect(detached == repeatedDetach)
        #expect(try await registry.functionRecord(runID: snapshot.runID) == nil)

        let finding = CritiqueFinding(
            judgment: .untraced,
            title: "State the suppressed premise",
            critiqueSourceLine: 5,
            targetLine: 3
        )
        let captured = try await registry.captureLocalExecutionFindings(
            runID: snapshot.runID,
            findings: [finding]
        )
        let repeatedCapture = try await registry.captureLocalExecutionFindings(
            runID: snapshot.runID,
            findings: [finding]
        )
        #expect(captured == repeatedCapture)
        await #expect(throws: CritiqueRegistryError.self) {
            _ = try await registry.captureLocalExecutionFindings(
                runID: snapshot.runID,
                findings: [CritiqueFinding(
                    judgment: .disputed,
                    title: "Different finding",
                    critiqueSourceLine: 6,
                    targetLine: 4
                )]
            )
        }
    }

    @Test("Critique round completes only after every actionable finding is disposed")
    func critiqueRoundDispositionAndCompletion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let registry = CritiqueRegistry(controlURL: control)
        let workID = UUID()
        let vaultID = UUID()
        let targetFingerprint = DocumentFingerprint(content: "# Original Work\n")
        let target = ResearchFunctionTarget(
            noteID: workID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Drafts/Paper.md"),
            role: .work,
            fingerprint: targetFingerprint,
            title: "Paper"
        )
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(function: .critique, target: target),
            recordKind: .critique
        )
        let completion = ResearchFunctionCompletion(
            runID: snapshot.runID,
            function: .critique,
            state: .complete,
            targetFingerprint: targetFingerprint,
            materialFingerprints: [:],
            summary: "Two actionable findings were recorded.",
            didModifyTarget: false,
            fidelityOutcomes: []
        )
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: targetFingerprint,
            critiqueRelativePath: "Critiques/Paper Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: snapshot.runID,
            functionSnapshot: snapshot,
            functionCompletion: completion
        )
        let first = CritiqueFinding(
            judgment: .traced,
            title: "Clarify the inference",
            critiqueSourceLine: 10,
            targetLine: 4
        )
        let second = CritiqueFinding(
            judgment: .disputed,
            title: "Answer the counterexample",
            critiqueSourceLine: 20,
            targetLine: 8
        )
        _ = try await registry.captureActionableFindings(
            runID: snapshot.runID,
            findings: [first, second]
        )

        await #expect(throws: CritiqueRegistryError.self) {
            _ = try await registry.setFindingDisposition(
                roundID: snapshot.runID,
                findingID: first.id,
                decision: .accept,
                currentWorkRevision: targetFingerprint,
                rationale: nil,
                noTextChangeRationale: nil
            )
        }
        _ = try await registry.setFindingDisposition(
            roundID: snapshot.runID,
            findingID: first.id,
            decision: .accept,
            currentWorkRevision: targetFingerprint,
            rationale: nil,
            noTextChangeRationale: "The clarification is already explicit in the cited paragraph."
        )
        await #expect(throws: CritiqueRegistryError.self) {
            _ = try await registry.completeRound(roundID: snapshot.runID)
        }
        _ = try await registry.setFindingDisposition(
            roundID: snapshot.runID,
            findingID: second.id,
            decision: .rebut,
            currentWorkRevision: targetFingerprint,
            rationale: "The counterexample assumes the conclusion it disputes.",
            noTextChangeRationale: nil
        )
        let completed = try await registry.completeRound(roundID: snapshot.runID)
        let retried = try await registry.completeRound(roundID: snapshot.runID)
        let round = try #require(completed.rounds.first)
        #expect(round.completedAt != nil)
        #expect(round.findingDispositions.count == 2)
        #expect(retried.rounds.first?.completedAt == round.completedAt)

        let reopened = CritiqueRegistry(controlURL: control)
        let persisted = try #require(await reopened.association(workNoteID: workID))
        #expect(persisted.rounds.first?.actionableFindings == [first, second])
        #expect(persisted.rounds.first?.findingDispositions.count == 2)
        #expect(persisted.rounds.first?.completedAt != nil)
    }

    @Test("Critique preparation rollback removes only its incomplete round")
    func critiqueFunctionPreparationRollback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = CritiqueRegistry(
            controlURL: fixture.support.appendingPathComponent("control", isDirectory: true)
        )
        let workID = UUID()
        let vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: "# Work\n")
        let target = ResearchFunctionTarget(
            noteID: workID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Drafts/Work.md"),
            role: .work,
            fingerprint: fingerprint,
            title: "Work"
        )
        let olderRoundID = UUID()
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Work.md",
            targetFingerprint: fingerprint,
            critiqueRelativePath: "Critiques/Work Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: olderRoundID
        )
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(
                function: .critique,
                target: target,
                scope: .whole
            ),
            recordKind: .critique,
            preparedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Work.md",
            targetFingerprint: fingerprint,
            critiqueRelativePath: "Critiques/Work Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: UUID(),
            functionSnapshot: snapshot
        )

        let preparedRecord = try await registry.functionRecord(runID: snapshot.runID)
        #expect(preparedRecord?.snapshot == snapshot)
        _ = try await registry.discardPreparedFunctionRecord(runID: snapshot.runID)
        #expect(try await registry.functionRecord(runID: snapshot.runID) == nil)
        let retained = try #require(await registry.association(workNoteID: workID))
        #expect(retained.rounds.map(\.id) == [olderRoundID])
    }

    @Test("Repeated Critique requests keep one association and bind each round to the current Work")
    func repeatedCritiqueRequests() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let registry = CritiqueRegistry(controlURL: control)
        let workID = UUID()
        let first = DocumentFingerprint(content: "first")
        let second = DocumentFingerprint(content: "second")
        let firstCheckpoint = UUID()
        let secondCheckpoint = UUID()

        let created = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: first,
            critiqueRelativePath: "Critiques/Paper Critique.md",
            checkpointID: firstCheckpoint,
            scope: .overall
        )
        let updated = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: second,
            critiqueRelativePath: created.critiqueRelativePath,
            checkpointID: secondCheckpoint,
            scope: .specific
        )

        #expect(updated.id == created.id)
        #expect(updated.targetFingerprint == second)
        #expect(updated.rounds.count == 2)
        #expect(updated.rounds.map(\.checkpointID) == [firstCheckpoint, secondCheckpoint])
        #expect(updated.rounds.map(\.scope) == [.overall, .specific])

        let reopened = CritiqueRegistry(controlURL: control)
        let persisted = try #require(await reopened.association(workNoteID: workID))
        #expect(persisted.id == created.id)
        #expect(persisted.targetFingerprint == second)
        #expect(persisted.rounds.count == 2)
        #expect(await reopened.association(critiqueRelativePath: created.critiqueRelativePath)?.id == created.id)
    }

    @Test("Critique scaffold exposes agent provenance and exact target metadata")
    func critiqueScaffoldAndTargetedMetadataUpdate() throws {
        let first = DocumentFingerprint(content: "first")
        let second = DocumentFingerprint(content: "second")
        let scaffold = CritiqueDocumentContract.scaffold(
            title: "Paper: A \"Test\"",
            targetRelativePath: "Drafts/Paper: A.md",
            targetFingerprint: first,
            scope: .overall,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let document = NoteDocument(relativePath: "Critiques/Paper Critique.md", rawContent: scaffold)
        let metadata = CritiqueDocumentContract.metadata(in: document)
        #expect(document.validationWarnings.isEmpty)
        #expect(metadata.isAgentAttributed)
        #expect(metadata.targetRelativePath == "Drafts/Paper: A.md")
        #expect(metadata.targetFingerprintSHA256 == first.sha256)
        #expect(metadata.scope == .overall)

        let updatedSource = try document.applying(
            .frontmatter(CritiqueDocumentContract.requestEdits(
                targetRelativePath: "Drafts/Paper: A.md",
                targetFingerprint: second,
                scope: .both,
                requestedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )),
            timestampKey: nil
        )
        let updated = NoteDocument(relativePath: document.relativePath, rawContent: updatedSource)
        #expect(updated.body == document.body)
        #expect(updated.rawFrontmatter?.contains("critique_target_fingerprint: \(second.sha256)") == true)
        #expect(CritiqueDocumentContract.metadata(in: updated).targetFingerprintSHA256 == second.sha256)
        #expect(CritiqueDocumentContract.metadata(in: updated).scope == .both)

        let customSource = scaffold.replacingOccurrences(
            of: "critique_authorship: agent\n",
            with: "# keep this comment\ncustom:\n  nested: \"a: b\"\ncritique_authorship: agent\n"
        )
        let custom = NoteDocument(relativePath: document.relativePath, rawContent: customSource)
        let customUpdated = try custom.applying(
            .frontmatter(CritiqueDocumentContract.requestEdits(
                targetRelativePath: "Drafts/Paper: A.md",
                targetFingerprint: second,
                scope: .both
            )),
            timestampKey: nil
        )
        #expect(customUpdated.contains("# keep this comment\ncustom:\n  nested: \"a: b\"\ncritique_authorship: agent\n"))
    }

    @Test("Adding Critique metadata to a legacy file preserves its exact existing bytes")
    func legacyCritiqueMetadataPrefix() throws {
        let existing = "\u{FEFF}# Legacy Critique\r\n\r\nKeep **all** of this.\r\n"
        let document = NoteDocument(relativePath: "Critiques/Legacy.md", rawContent: existing)
        let fingerprint = DocumentFingerprint(content: "target")
        let migrated = try CritiqueDocumentContract.sourceByAddingRequestMetadata(
            to: document,
            targetRelativePath: "Drafts/Target.md",
            targetFingerprint: fingerprint,
            scope: .specific,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(migrated.hasPrefix("\u{FEFF}---\r\n"))
        #expect(migrated.hasSuffix(String(existing.dropFirst())))
        let parsed = NoteDocument(relativePath: document.relativePath, rawContent: migrated)
        #expect(parsed.validationWarnings.isEmpty)
        #expect(parsed.body == String(existing.dropFirst()))
        #expect(CritiqueDocumentContract.metadata(in: parsed).targetFingerprintSHA256 == fingerprint.sha256)
    }

    @Test("Critique findings resolve explicit lines, headings, and unique quotations")
    func critiqueFindingNavigation() throws {
        let work = NoteDocument(
            relativePath: "Drafts/Paper.md",
            rawContent: "# Paper\n\n## Source Support\n\nA uniquely quoted claim appears here.\n"
        )
        let critiqueSource = """
        ---
        critique_authorship: agent
        critique_target_path: Drafts/Paper.md
        critique_target_fingerprint: \(work.fingerprint.sha256)
        critique_requested_at: "2026-07-13T00:00:00Z"
        critique_request_scope: "Both"
        ---
        # Critique

        ## Specific Findings

        ### Traced — Direct locator
        - Target Work: Drafts/Paper.md
        - Target fingerprint: \(work.fingerprint.sha256)
        - Target line: 5
        - Target quotation: "A uniquely quoted claim appears here."

        ### Disputed: Heading locator
        - Target heading: Source Support

        ### Beyond Sources — Quotation locator
        - Target quotation: A uniquely quoted claim appears here.

        ## Materials Consulted and Limitations
        """
        let critique = NoteDocument(relativePath: "Critiques/Paper Critique.md", rawContent: critiqueSource)
        let findings = CritiqueDocumentContract.findings(in: critique)

        #expect(findings.count == 3)
        #expect(findings.map(\.judgment) == [.traced, .disputed, .beyondSources])
        #expect(findings[0].targetRelativePath == work.relativePath)
        #expect(findings[0].targetFingerprintSHA256 == work.fingerprint.sha256)
        #expect(findings[0].resolvedTargetLine(in: work) == 5)
        #expect(findings[1].resolvedTargetLine(in: work) == 3)
        #expect(findings[2].resolvedTargetLine(in: work) == 5)

        let ambiguousWork = NoteDocument(
            relativePath: "Drafts/Ambiguous.md",
            rawContent: "Repeated quotation.\nRepeated quotation.\n"
        )
        let ambiguous = CritiqueFinding(
            judgment: .untraced,
            title: "Ambiguous quotation",
            critiqueSourceLine: 1,
            targetQuotation: "Repeated quotation."
        )
        let invalidLine = CritiqueFinding(
            judgment: .untraced,
            title: "Invalid line",
            critiqueSourceLine: 1,
            targetLine: 99
        )
        #expect(ambiguous.resolvedTargetLine(in: ambiguousWork) == nil)
        #expect(invalidLine.resolvedTargetLine(in: ambiguousWork) == nil)
    }

    @Test("Ordinary moves cannot cross the Critiques boundary")
    func critiquePlacement() throws {
        try CritiquePlacement.validateOrdinaryMove(
            from: "Critiques/Paper Critique.md",
            to: "Critiques/Renamed Critique.md"
        )
        try CritiquePlacement.validateOrdinaryMove(
            from: "Set Aside/Critiques/Paper Critique.md",
            to: "Critiques/Paper Critique.md"
        )
        #expect(throws: CritiquePlacementError.self) {
            try CritiquePlacement.validateOrdinaryMove(
                from: "Critiques/Paper Critique.md",
                to: "Drafts/Paper Critique.md"
            )
        }
        #expect(throws: CritiquePlacementError.self) {
            try CritiquePlacement.validateOrdinaryMove(
                from: "Drafts/Paper.md",
                to: "Critiques/Paper.md"
            )
        }
    }

    private func testCommentAnchor(
        fingerprint: DocumentFingerprint = DocumentFingerprint(content: "Test passage"),
        quotation: String = "Test passage"
    ) -> CommentAnchor {
        CommentAnchor(
            fingerprint: fingerprint,
            utf8Range: 0..<quotation.utf8.count,
            utf16Range: 0..<quotation.utf16.count,
            line: 1,
            endLine: 1,
            quotation: quotation
        )
    }


    private struct Fixture {
        let root: URL
        let support: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Research-Records-\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
