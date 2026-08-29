import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchActionRunOperationsTests {
    @Test("Analyze requires one current explicit source while Synthesize does not")
    func analyzeSourceRequirement() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )

        try await handle.research.removeSourceAccess(for: analysis)
        let status = try await handle.research.sourceAccess(for: analysis)
        #expect(status.state == .repairRequired)
        #expect(status.failure?.code == .missingBinding)
        let analyzeAvailability = try #require(
            try await handle.research.availableActionOperations(for: analysis).first {
                $0.actionID == .analyze
            }
        )
        #expect(!analyzeAvailability.isEnabled)
        #expect(
            analyzeAvailability.repairReasons.first?.sourceAccessFailure?.code
                == .missingBinding
        )
        do {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: ResearchAgentStartRequest(
                    actionID: .analyze,
                    target: fixture.analysisID
                ),
                sessionValidity: 300
            )
            Issue.record("Expected direct Agent start to require source evidence.")
        } catch let error as ResearchActionRunContractError {
            guard case .sourceAccessUnavailable(let failure) = error else {
                Issue.record("Unexpected direct Agent start error: \(error)")
                return
            }
            #expect(failure.code == .missingBinding)
        }
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await handle.research.prepareActionRun(
                ResearchActionRunRequest(actionID: .analyze, target: analysis)
            )
        }

        let synthesis = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .synthesize, target: topic)
        )
        #expect(synthesis.snapshot.sourceReference == nil)

        let reference = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: analysis,
                selection: .localFile(fixture.analysisSourceURL)
            )
        )
        let analyze = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(analyze.snapshot.sourceReference == reference)
        #expect(analyze.instructions.contains(fixture.analysisSourceURL.path))
        let snapshotJSON = String(
            decoding: try JSONEncoder().encode(analyze.snapshot),
            as: UTF8.self
        )
        #expect(!snapshotJSON.contains(fixture.analysisSourceURL.path))
        #expect(!snapshotJSON.contains("bookmarkData"))
        let storedRun = try #require(try await handle.services.localResearchExecutionStore.listing().records.first {
            $0.id == analyze.runID
        })
        let storedInstructions = storedRun.preparedInstructions
        #expect(!storedInstructions.contains(fixture.analysisSourceURL.path))
        #expect(!storedInstructions.contains("bookmarkData"))
        await runtime.shutdown()
    }

    @Test("A prepared Analyze cannot resume or complete after source authority is removed")
    func preparedAnalyzeSourceLossFailsClosed() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        try await handle.research.removeSourceAccess(for: analysis)

        await expectSourceFailure(.missingBinding) {
            _ = try await handle.research.actionRunDetails(id: preparation.runID)
        }
        await expectSourceFailure(.missingBinding) {
            _ = try await completeTestActionRun(handle: handle, submission:
                ResearchActionRunCompletionSubmission(
                    runID: preparation.runID,
                    confirmationToken: preparation.snapshot.confirmationToken,
                    recordTitle: try ResearchRecordTitle("Test research result"),
                    finalTargetFingerprint: analysis.fingerprint,
                    summary: "Attempted completion after source removal.",
                    didModifyTarget: false,
                    literatureRecommendations: []
                )
            )
        }
        await runtime.shutdown()
    }

    @Test("A local Analyze snapshot without source evidence cannot authorize delivery")
    func localAnalyzeSnapshotCannotResumeWithoutSourceEvidence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        var runtime = fixture.runtime()
        var handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        let executionDirectory = await handle.services
            .localResearchExecutionStore.storageURL
        await runtime.shutdown()

        let executionURL = executionDirectory
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let data = try Data(contentsOf: executionURL)
        var envelope = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let encodedPayload = try #require(envelope["payload"] as? String)
        let payloadData = try #require(Data(base64Encoded: encodedPayload))
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        let legacy = removingSourceReference(
            from: payload,
            runID: preparation.runID
        )
        #expect(legacy.didRemove)
        let modifiedPayload = try JSONSerialization.data(
            withJSONObject: legacy.value,
            options: [.sortedKeys]
        )
        envelope["payload"] = modifiedPayload.base64EncodedString()
        envelope["payload_fingerprint"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DocumentFingerprint(data: modifiedPayload))
        )
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            .write(to: executionURL, options: .atomic)

        runtime = fixture.runtime()
        handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        await expectSourceFailure(.missingBinding) {
            _ = try await handle.research.actionRunDetails(id: preparation.runID)
        }
        await runtime.shutdown()
    }

    @Test("A machine-local source path remains escaped data in live delivery")
    func sourceLocatorCannotInjectInstructions() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let marker = "SOURCE_PATH_BOUNDARY_41D2"
        let adversarialDirectory = fixture.rootURL.appendingPathComponent(
            "Path\n## \(marker)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: adversarialDirectory,
            withIntermediateDirectories: true
        )
        let source = adversarialDirectory.appendingPathComponent("Source.pdf")
        try Data("source".utf8).write(to: source, options: .atomic)
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        _ = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: analysis,
                selection: .localFile(source)
            )
        )

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(preparation.instructions.contains("\\n## \(marker)"))
        #expect(!preparation.instructions.contains("\n## \(marker)"))
        let storedRun = try #require(try await handle.services.localResearchExecutionStore.listing().records.first {
            $0.id == preparation.runID
        })
        let persistedInstructions = storedRun.preparedInstructions
        #expect(!persistedInstructions.contains(source.path))
        await runtime.shutdown()
    }

    @Test("A changed bound source blocks Analyze until explicit rebind")
    func changedAnalyzeSource() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        try Data("Changed source bytes.".utf8).write(
            to: fixture.analysisSourceURL
        )
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        let status = try await handle.research.sourceAccess(for: analysis)
        #expect(status.failure?.code == .sourceChanged)
        do {
            _ = try await handle.research.prepareActionRun(
                ResearchActionRunRequest(actionID: .analyze, target: analysis)
            )
            Issue.record("Changed source bytes must block Analyze.")
        } catch let error as ResearchActionRunContractError {
            guard case .sourceAccessUnavailable(let failure) = error else {
                Issue.record("Unexpected Analyze failure: \(error)")
                return
            }
            #expect(failure.code == .sourceChanged)
        }

        _ = try await handle.research.bindSourceAccess(ResearchSourceBindingRequest(
            target: analysis,
            selection: .localFile(fixture.analysisSourceURL)
        ))
        #expect(
            try await handle.research.sourceAccess(for: analysis).state
                == .available
        )
        await runtime.shutdown()
    }

    @Test("A Zotero relationship keeps Analyze available when attachment access is unavailable")
    func zoteroAttachmentUnavailable() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "PARENT01")
        defer { fixture.remove() }
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Bound Source",
            "filename": "Bound Source.pdf"
          }
        }
        """
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(fixture.analysisSourceURL.absoluteString.utf8)),
            .transportFailure,
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let reference = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: analysis,
                selection: .zoteroAttachment(
                    itemKey: "PARENT01",
                    attachmentKey: "ATTACH02",
                    selectedFileURL: fixture.analysisSourceURL
                )
            )
        )
        #expect(reference.identity.route == .zoteroAttachment)
        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(preparation.snapshot.sourceReference == nil)
        #expect(preparation.snapshot.zoteroBibliographicContext?.itemKey == "PARENT01")
        #expect(preparation.snapshot.zoteroBibliographicContext?.warning != nil)
        #expect(await script.requestCount() == 3)
        await runtime.shutdown()
    }

    @Test("A Zotero attachment cannot authorize a different selected file")
    func zoteroAttachmentPathMismatch() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "PARENT01")
        defer { fixture.remove() }
        let otherFile = fixture.rootURL.appendingPathComponent("Other Source.pdf")
        try Data("other".utf8).write(to: otherFile, options: .atomic)
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Bound Source",
            "filename": "Bound Source.pdf"
          }
        }
        """
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(fixture.analysisSourceURL.absoluteString.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        do {
            _ = try await handle.research.bindSourceAccess(
                ResearchSourceBindingRequest(
                    target: analysis,
                    selection: .zoteroAttachment(
                        itemKey: "PARENT01",
                        attachmentKey: "ATTACH02",
                        selectedFileURL: otherFile
                    )
                )
            )
            Issue.record("A different selected file must not satisfy Zotero identity.")
        } catch let error as ResearchActionRunContractError {
            guard case .sourceAccessUnavailable(let failure) = error else {
                Issue.record("Unexpected source binding failure: \(error)")
                return
            }
            #expect(failure.code == .zoteroIdentityMismatch)
        }
        #expect(
            try await handle.research.sourceAccess(for: analysis)
                .reference?.identity.route == .localFile
        )
        #expect(await script.requestCount() == 2)
        await runtime.shutdown()
    }

    @Test("A Zotero attachment symlink cannot authorize its real target")
    func zoteroAttachmentSymlinkFailsClosed() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "PARENT01")
        defer { fixture.remove() }
        let link = fixture.rootURL.appendingPathComponent("Zotero Link.pdf")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.analysisSourceURL
        )
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Bound Source",
            "filename": "Bound Source.pdf"
          }
        }
        """
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(link.absoluteString.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        await expectSourceFailure(.zoteroIdentityMismatch) {
            _ = try await handle.research.bindSourceAccess(
                ResearchSourceBindingRequest(
                    target: analysis,
                    selection: .zoteroAttachment(
                        itemKey: "PARENT01",
                        attachmentKey: "ATTACH02",
                        selectedFileURL: fixture.analysisSourceURL
                    )
                )
            )
        }
        #expect(
            try await handle.research.sourceAccess(for: analysis)
                .reference?.identity.route == .localFile
        )
        await runtime.shutdown()
    }

    @Test("A changed Analysis Zotero relationship is resolved as a fresh data route")
    func zoteroParentDriftFailsClosed() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "PARENT01")
        defer { fixture.remove() }
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Bound Source",
            "filename": "Bound Source.pdf"
          }
        }
        """
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(fixture.analysisSourceURL.absoluteString.utf8)),
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(fixture.analysisSourceURL.absoluteString.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        _ = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: analysis,
                selection: .zoteroAttachment(
                    itemKey: "PARENT01",
                    attachmentKey: "ATTACH02",
                    selectedFileURL: fixture.analysisSourceURL
                )
            )
        )
        let bindingSnapshot = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.setZoteroBinding(
            AnalysisZoteroBinding(
                noteID: analysis.noteID,
                library: .user,
                itemKey: "PARENT99"
            ),
            expectedRevision: bindingSnapshot.revision
        )
        analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(preparation.snapshot.sourceReference == nil)
        #expect(preparation.snapshot.zoteroBibliographicContext?.itemKey == "PARENT99")
        #expect(await script.requestCount() == 3)
        await runtime.shutdown()
    }

    @Test("A Zotero relationship makes Analyze available without Scholium source access")
    func zoteroRelationshipDoesNotRequireScholiumSourceAccess() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "META0001")
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(Self.zoteroItemJSON.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        try await handle.research.removeSourceAccess(for: analysis)

        let availability = try #require(
            try await handle.research.availableActionOperations(for: analysis).first {
                $0.actionID == .analyze
            }
        )
        #expect(availability.isEnabled)
        #expect(availability.repairReasons.isEmpty)

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(preparation.snapshot.sourceReference == nil)
        #expect(preparation.snapshot.zoteroBibliographicContext?.itemKey == "META0001")
        #expect(!preparation.instructions.contains("## Explicit source access"))
        #expect(await script.requestCount() == 1)
        await runtime.shutdown()
    }

    @Test("A Zotero-only Analyze completes into a portable schema-17 Record")
    func zoteroOnlyAnalyzeCompletesPortableRecord() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "META0001")
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(Self.zoteroItemJSON.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        try await handle.research.removeSourceAccess(for: target)

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .analyze,
                target: target,
                instruction: "Analyze the paper retrieved through Zotero."
            )
        )
        #expect(preparation.snapshot.sourceReference == nil)
        let context = try #require(preparation.snapshot.zoteroBibliographicContext)
        #expect(context.itemKey == "META0001")
        #expect(context.metadata?.title == "Fittingness")
        #expect(await script.requestCount() == 1)

        let receipt = try await submitTestAgentResult(
            for: preparation,
            handle: handle,
            literatureRecommendations: []
        )
        #expect(receipt.disposition == .completed)
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)

        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: target.noteID)
                .first { $0.action?.actionID == .analyze }
        )
        #expect(record.schemaVersion == PortableResearchRecord.currentSchemaVersion)
        #expect(record.schemaVersion == 17)
        #expect(record.analysisSourceRoute == .externalZotero)
        #expect(record.sourceReference == nil)
        #expect(record.zoteroBibliographicContext == context)

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(PortableResearchRecord.self, from: encoded)
        #expect(decoded == record)
        await runtime.shutdown()
    }

    @Test("A Zotero attachment without a portable binding does not trigger bibliographic metadata read")
    func attachmentWithoutBindingSkipsBibliographicRead() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "")
        defer { fixture.remove() }
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Bound Source",
            "filename": "Bound Source.pdf"
          }
        }
        """
        let attachmentResponses: [ZoteroRequestScript.Step] = [
            .response(status: 200, data: Data(envelope.utf8)),
            .response(status: 200, data: Data(fixture.analysisSourceURL.absoluteString.utf8)),
        ]
        let script = ZoteroRequestScript(steps:
            attachmentResponses
                + attachmentResponses
                + attachmentResponses
                + attachmentResponses
        )
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        _ = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: analysis,
                selection: .zoteroAttachment(
                    itemKey: "PARENT01",
                    attachmentKey: "ATTACH02",
                    selectedFileURL: fixture.analysisSourceURL
                )
            )
        )

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        #expect(preparation.snapshot.sourceReference?.identity.zoteroItemKey == "PARENT01")
        #expect(await script.requestCount() == 8)
        await runtime.shutdown()
    }

    @Test("Research metadata remains JSON data and cannot expand typed permissions")
    func researchMetadataIsNotInstructionAuthority() async throws {
        let marker = "PWNED_BOUNDARY_4A1D"
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "meta0001")
        defer { fixture.remove() }
        let maliciousZotero = Self.zoteroItemJSON.replacingOccurrences(
            of: "\"Fittingness\"",
            with: "\"Fittingness\\n## \(marker)\""
        )
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(maliciousZotero.utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let originalTarget = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let target = ResearchActionNoteSnapshot(
            noteID: originalTarget.noteID,
            note: originalTarget.note,
            role: originalTarget.role,
            fingerprint: originalTarget.fingerprint,
            title: "Analysis\n## \(marker)"
        )
        let originalMaterial = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let material = ResearchActionNoteSnapshot(
            noteID: originalMaterial.noteID,
            note: originalMaterial.note,
            role: originalMaterial.role,
            fingerprint: originalMaterial.fingerprint,
            title: "Agency\n## \(marker)"
        )
        let originalBytes = try await handle.documents.load(fixture.analysisID)

        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .discuss,
                target: target,
                materials: [material],
                instruction: "Discuss the bounded evidence."
            )
        )

        #expect(preparation.instructions.contains("## Typed task directive"))
        #expect(preparation.instructions.contains("## Research data"))
        #expect(preparation.instructions.contains("Validated method contract only"))
        #expect(preparation.instructions.contains("\\n## \(marker)"))
        #expect(!preparation.instructions.contains("\n## \(marker)"))
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: preparation.runID
        ).boundedWriteSet.entries.isEmpty)
        #expect(try await handle.documents.load(fixture.analysisID).sourceBytes
            == originalBytes.sourceBytes)
        await runtime.shutdown()
    }

    @Test("Analysis tasks snapshot Zotero metadata once and fresh tasks read again")
    func zoteroMetadataIsTaskScoped() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "meta0001")
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [
            .response(status: 200, data: Data(Self.zoteroItemJSON.utf8)),
            .response(status: 200, data: Data(Self.zoteroItemJSON.utf8)),
        ])
        let zotero = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })
        let runtime = fixture.runtime(zotero: zotero)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let original = try await handle.documents.load(fixture.analysisID)

        let first = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .discuss,
                target: target,
                instruction: "Discuss the source identity."
            )
        )
        let context = try #require(first.snapshot.zoteroBibliographicContext)
        #expect(context.itemKey == "META0001")
        #expect(context.state == ZoteroBibliographicContext.RetrievalState.resolved)
        #expect(context.warning == nil)
        #expect(context.metadata?.title == "Fittingness")
        #expect(context.metadata?.creators == [
            ZoteroCreatorMetadata(
                role: "author",
                name: "Richard Chappell",
                givenName: "Richard",
                familyName: "Chappell"
            ),
            ZoteroCreatorMetadata(
                role: "editor",
                name: "Example Editor",
                givenName: "Example",
                familyName: "Editor"
            ),
        ])
        #expect(context.metadata?.tags == ["fittingness", "value"])
        #expect(first.instructions.contains("## Zotero bibliographic metadata"))
        #expect(first.instructions.contains(
            "bibliographic metadata, not paper content or philosophical evidence"
        ))
        #expect(first.instructions.contains(
            "use the configured Zotero/MCP capability"
        ))
        #expect(await script.requestCount() == 1)

        let resumed = try await handle.research.actionRunDetails(id: first.runID)
        #expect(resumed.snapshot.zoteroBibliographicContext == context)
        #expect(await script.requestCount() == 1)
        _ = try await handle.research.finishDiscussion(discussionID: first.runID)

        let second = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .discuss,
                target: target,
                instruction: "Discuss the source identity again."
            )
        )
        #expect(second.snapshot.zoteroBibliographicContext?.state == .resolved)
        #expect(await script.requestCount() == 2)
        _ = try await handle.research.finishDiscussion(discussionID: second.runID)
        let unchanged = try await handle.documents.load(fixture.analysisID)
        #expect(unchanged.fingerprint == original.fingerprint)
        #expect(unchanged.rawContent == original.rawContent)
        await runtime.shutdown()
    }

    @Test("Missing keys and non-Analysis notes never invoke Zotero")
    func zoteroContextIsAnalysisOnly() async throws {
        let fixture = try await ResearchFixture.make(workZoteroKey: "WORK0001")
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let work = try await researchActionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )

        let analysisPreparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .discuss,
                target: analysis,
                instruction: "Discuss the Analysis."
            )
        )
        let workPreparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .discuss,
                target: work,
                instruction: "Discuss the Work."
            )
        )
        #expect(analysisPreparation.snapshot.zoteroBibliographicContext == nil)
        #expect(workPreparation.snapshot.zoteroBibliographicContext == nil)
        #expect(await script.requestCount() == 0)

        let handoff = try await handle.research.issueAgentHandoff(
            runID: analysisPreparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.authenticatedAgentContext(
            credential: credential,
            run: handoff.run
        )
        #expect(!context.requiredSkills.contains {
            $0.name == ResearchSystemSkillID.zoteroIntegration.rawValue
        })
        _ = try await runtime.endResearchAgentRun(
            credential: credential,
            run: handoff.run
        )
        await runtime.shutdown()
    }

    @Test("Researcher-provided Analyze ignores an existing Zotero binding through Record formation")
    func researcherProvidedAnalyzeSuppressesZoteroRoute() async throws {
        let fixture = try await ResearchFixture.make(
            analysisZoteroKey: "BOUND001"
        )
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: ResearchAgentStartRequest(
                actionID: .analyze,
                target: fixture.analysisID,
                sourceRoute: .researcherProvided
            ),
            sessionValidity: 300
        )
        let context = try await runtime.researchAgentContext(
            credential: started.credential,
            run: started.receipt.run
        )
        #expect(!context.requiredSkills.contains {
            $0.name == ResearchSystemSkillID.zoteroIntegration.rawValue
        })
        #expect(await script.requestCount() == 0)

        let sessions = try #require((await handle.services).researchAgentSessions)
        let authenticated = try await sessions.authenticate(
            started.credential,
            run: started.receipt.run,
            requiresWrite: false,
        )
        let execution = try await handle.services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        #expect(execution.snapshot.analysisSourceRoute == .researcherProvided)
        #expect(execution.snapshot.zoteroBibliographicContext == nil)

        let receipt = try await runtime.submitResearchAgentResult(
            credential: started.credential,
            run: started.receipt.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: ResearchRecordTitle("Researcher-provided bound Analysis"),
                academicResults: ResearchAcademicFieldValues(
                    rawValues: [
                        "source-reconstruction": .freeText("A bounded reconstruction."),
                        "coverage": .singleChoice("specified-part-only"),
                        "reliability": .multipleChoice(["no-material-limitations"]),
                    ],
                    definitions: context.resultContract.academicFields
                ),
                literatureRecommendations: []
            )
        )
        #expect(receipt.state == .finalized)
        let record = try await handle.services.portableResearchRecordStore.record(
            id: authenticated.runID
        )
        #expect(record.analysisSourceRoute == .researcherProvided)
        #expect(record.zoteroBibliographicContext == nil)
        #expect(record.sourceReference == nil)
        #expect(await script.requestCount() == 0)
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Zotero transport, missing-item, and decoding failures remain non-blocking")
    func zoteroFailuresBecomeTaskWarnings() async throws {
        let fixture = try await ResearchFixture.make(analysisZoteroKey: "meta0001")
        defer { fixture.remove() }
        let script = ZoteroRequestScript(steps: [
            .transportFailure,
            .response(status: 404, data: Data()),
            .response(status: 200, data: Data("{not-json".utf8)),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        for expected in [
            ZoteroBibliographicContext.RetrievalState.unavailable,
            .notFound,
            .invalidResponse,
        ] {
            let preparation = try await handle.research.prepareActionRun(
                ResearchActionRunRequest(
                    actionID: .discuss,
                    target: target,
                    instruction: "Continue despite unavailable bibliography metadata."
                )
            )
            #expect(preparation.snapshot.zoteroBibliographicContext?.state == expected)
            #expect(preparation.snapshot.zoteroBibliographicContext?.metadata == nil)
            #expect(preparation.snapshot.zoteroBibliographicContext?.warning != nil)
            #expect(preparation.instructions.contains("Non-blocking warning:"))
            #expect(preparation.instructions.contains(
                "fill only information genuinely needed for this Action"
            ))
            _ = try await handle.research.finishDiscussion(
                discussionID: preparation.runID
            )
        }
        #expect(await script.requestCount() == 3)
        await runtime.shutdown()
    }

}
