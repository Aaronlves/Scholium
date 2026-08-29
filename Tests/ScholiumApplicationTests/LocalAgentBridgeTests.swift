import Darwin
import Foundation
@testable import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Local Agent bridge", .serialized)
struct LocalAgentBridgeTests {
    @Test("The bridge wire rejects unknown fields, unknown operations, and old versions")
    func strictCurrentWire() throws {
        let request = try pairRequest()
        let encoded = try LocalAgentBridgeWireCoding.encode(request)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["pairing_code"] as? String == request.pairingCode?.rawValue)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("rawValue"))
        #expect(!String(reflecting: request).contains(
            try #require(request.pairingCode).rawValue
        ))
        object["unexpected_secret"] = String(repeating: "x", count: 73)
        #expect(throws: (any Error).self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unexpected_secret")
        object["operation"] = "status"
        #expect(throws: (any Error).self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object["operation"] = "pair"
        object["schema_version"] = LocalAgentBridgeRequest.currentSchemaVersion - 1
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let credential = try testCredential()
        let response = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            credential: credential
        )
        let responseObject = try #require(
            JSONSerialization.jsonObject(
                with: LocalAgentBridgeWireCoding.encode(response)
            ) as? [String: Any]
        )
        let wireCredential = try #require(
            responseObject["credential"] as? [String: Any]
        )
        #expect(UUID(uuidString: wireCredential["session_id"] as? String ?? "")
            == credential.sessionID)
        #expect(wireCredential["secret"] as? String == credential.secret)
        #expect(wireCredential["sessionID"] == nil)
        #expect(!String(reflecting: response).contains(credential.secret))
    }

    @Test("Bridge carries read-only Analysis creation preflight without a Session")
    func analysisCreationPreflightShape() throws {
        let triptychID = UUID()
        let vaultID = UUID()
        let input = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000812")!,
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Managed Root.md"
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            sourceRoute: .researcherProvided
        )
        let request = try LocalAgentBridgeRequest(
            operation: .preflightAnalysisCreation,
            triptychID: triptychID,
            analysisCreationPreflightRequest: input
        )
        let encoded = try LocalAgentBridgeWireCoding.encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["operation"] as? String == "preflight_analysis_creation")
        #expect(object["analysis_creation_preflight_request"] != nil)
        #expect(object["credential"] == nil)
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: encoded
        ).analysisCreationPreflightRequest == input)
        let unknownRecovery = LocalAgentBridgeErrorPayload
            .outcomeUnknownRecovery(for: request)
        #expect(unknownRecovery.safeToRetry)
        #expect(unknownRecovery.nextStep == .rerunCreationPreflight)

        let target = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Managed Root.md"
        )
        let result = ResearchAgentAnalysisCreationPreflight(
            request: input,
            analysisVaultID: vaultID,
            applicableFields: PropertyContractCatalog.contracts(for: .analysis),
            preferredFields: [],
            fixedYAMLFields: PropertyContractCatalog.authoredCanonicalKeys,
            targetState: ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: nil,
                fingerprint: nil,
                sourceState: .absent
            ),
            status: .ready,
            startNewAnalysis: ResearchAgentNewAnalysisRequest(preflight: input),
            recovery: AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .startWithReturnedTemplate
            ),
            message: "The managed root destination is ready."
        )
        let response = try LocalAgentBridgeResponse(
            correlationID: request.correlationID,
            analysisCreationPreflight: result
        )
        let decoded = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(response)
        )
        #expect(decoded.analysisCreationPreflight?.status == .ready)
        #expect(decoded.analysisCreationPreflight?.targetState.target == target)
    }

    @Test("Bridge errors distinguish stale Run, stale projection, missing source evidence, and expired Session")
    func structuredRecoveryErrors() throws {
        let stale = LocalAgentBridgeWireCoding.errorPayload(
            ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "Agent Analysis creation",
                reason: "disposable projection failed"
            )
        )
        #expect(stale.code == .staleProjection)
        #expect(!stale.message.contains("disposable projection failed"))

        let staleRun = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentConnectionError.runStale(.targetChanged)
        )
        #expect(staleRun.code == .staleRun)
        #expect(staleRun.message.contains("start a new Action"))
        #expect(LocalAgentBridgeWireCoding.errorPayload(
            ResearchActionRunContractError.materialChanged("Material")
        ).code == .staleRun)

        let missingSource = LocalAgentBridgeWireCoding.errorPayload(
            ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .missingBinding)
            )
        )
        #expect(missingSource.code == .missingSourceEvidence)
        #expect(missingSource.message.contains("source_route=researcher_provided"))
        #expect(missingSource.recovery.nextStep == .correctRequest)

        for failure in [
            ResearchSourceAccessFailureCode.sourceMissing,
            .zoteroAttachmentMissing,
        ] {
            #expect(LocalAgentBridgeWireCoding.errorPayload(
                ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: failure)
                )
            ).code == .missingSourceEvidence)
        }
        for failure in [
            ResearchSourceAccessFailureCode.corruptBinding,
            .bookmarkUnavailable,
            .bookmarkStale,
            .sourceUnreadable,
            .sourceNotRegular,
            .sourceIsSymbolicLink,
            .zoteroUnavailable,
            .zoteroIdentityMismatch,
        ] {
            #expect(LocalAgentBridgeWireCoding.errorPayload(
                ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: failure)
                )
            ).code == .sourceUnreadable)
        }
        #expect(LocalAgentBridgeWireCoding.errorPayload(
            ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .sourceChanged)
            )
        ).code == .staleRun)

        let expired = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentSessionError.sessionRejected
        )
        #expect(expired.code == .sessionExpired)
        #expect(expired.message.contains("copy a new handoff"))

        let unfinished = LocalAgentBridgeWireCoding.errorPayload(
            ResearchActionRunContractError.activeResultRequired
        )
        #expect(unfinished.code == .operationFailed)
        #expect(unfinished.message.contains("copy the resume handoff"))
        #expect(unfinished.message.contains("do not start another Run"))

        let replayConflict = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentConnectionError.newAnalysisReplayConflict
        )
        #expect(replayConflict.code == .replayConflict)
        #expect(replayConflict.recovery.safeToRetry == false)
        #expect(replayConflict.recovery.mustReuseRequestIdentity)
        #expect(replayConflict.recovery.nextStep == .inspectOriginalRequestState)

        let invalidAuthored = LocalAgentBridgeWireCoding.errorPayload(
            DocumentCreationError.invalidAuthoredYAML
        )
        #expect(invalidAuthored.code == .invalidRequest)

        let invalidResult = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentResultContractError
                .fidelityOutcomesNotPermitted(.analyze)
        )
        #expect(invalidResult.code == .invalidRequest)
        #expect(invalidResult.message.contains("fidelity_outcomes"))
        #expect(invalidResult.message.contains("resubmit the same Run"))
        #expect(invalidResult.recovery.safeToRetry)
        #expect(invalidResult.recovery.mustReuseRequestIdentity)
        #expect(invalidResult.recovery.nextStep == .correctRequest)

        let attachedResult = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentResultContractError.resultAlreadySubmitted
        )
        #expect(attachedResult.code == .invalidRequest)
        #expect(!attachedResult.recovery.safeToRetry)
        #expect(attachedResult.recovery.mustReuseRequestIdentity)
        #expect(attachedResult.recovery.nextStep == .inspectOriginalRequestState)

        let pathOccupied = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentConnectionError.analysisPathOccupied
        )
        #expect(pathOccupied.code == .pathOccupied)
        #expect(!pathOccupied.recovery.mustReuseRequestIdentity)
        #expect(pathOccupied.recovery.nextStep
            == .requestResearcherDistinctFilenameAndPreflight)

        let identityOccupied = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentConnectionError.analysisIdentityOccupied
        )
        #expect(identityOccupied.code == .identityOccupied)
        #expect(identityOccupied.recovery.nextStep == .startExistingAnalysis)

        let identityMissing = LocalAgentBridgeWireCoding.errorPayload(
            ResearchAgentConnectionError.analysisIdentitySourceMissingOrTrashed
        )
        #expect(identityMissing.code == .identitySourceMissingOrTrashed)
        #expect(!identityMissing.recovery.mustReuseRequestIdentity)
        #expect(identityMissing.recovery.creationBranches.map(\.kind) == [
            .restoreOriginalSource,
            .explicitlyCreateAtDistinctDestination,
        ])
        #expect(identityMissing.recovery.creationBranches[0]
            .mustReuseRequestIdentity)
        #expect(identityMissing.recovery.creationBranches[0].nextStep
            == .retryExactRequest)
        #expect(!identityMissing.recovery.creationBranches[1]
            .mustReuseRequestIdentity)

        let pairRecovery = LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(
            for: try pairRequest()
        )
        let localUnknown = LocalAgentBridgeError.outcomeUnknown(pairRecovery)
        let unknown = LocalAgentBridgeWireCoding.errorPayload(localUnknown)
        #expect(unknown.code == .outcomeUnknown)
        #expect(unknown.recovery.safeToRetry == false)
        #expect(unknown.recovery.mustReuseRequestIdentity)
        #expect(unknown.recovery.nextStep == .copyNewHandoffAndPairSameRun)

        let endRecovery = LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(
            for: try endRequest()
        )
        #expect(!endRecovery.safeToRetry)
        #expect(!endRecovery.mustReuseRequestIdentity)
        #expect(endRecovery.nextStep == .stopAndReport)

        #expect(localUnknown.agentCommandErrorCode == "outcome_unknown")
        #expect(
            localUnknown.agentCommandRecovery?.nextStep
                == .copyNewHandoffAndPairSameRun
        )
        #expect(LocalAgentBridgeError.permissionDenied.agentCommandErrorCode == "permission_denied")
        #expect(
            LocalAgentBridgeError.permissionDenied.agentCommandRecovery?.nextStep
                == .stopAndReport
        )
    }

    @Test("Bridge Discussion replies use the authenticated Run payload")
    func discussionReplyShape() throws {
        let run = try #require(
            ResearchRunLocator(rawValue: "bridgediscussionreply1")
        )
        let credential = try testCredential()
        let reply = try ResearchAgentDiscussionReplyRequest(
            statementID: UUID(uuidString: "00000000-0000-4000-8000-000000000902")!,
            attribution: "External Agent",
            text: "This reply remains attributed and portable."
        )
        let request = try LocalAgentBridgeRequest(
            operation: .discussionReply,
            run: run,
            credential: credential,
            discussionReplyRequest: reply
        )
        let data = try LocalAgentBridgeWireCoding.encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["discussion_reply_request"] != nil)
        #expect(object["context_request"] == nil)
        let decoded = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: data
        )
        #expect(decoded.operation == .discussionReply)
        #expect(decoded.run == run)
        #expect(decoded.credential == credential)
        #expect(decoded.discussionReplyRequest == reply)

        let receipt = try ResearchAgentDiscussionReplyReceipt(
            run: run,
            discussionID: UUID(),
            statementID: reply.statementID,
            state: .recorded,
            message: "The Agent Discussion reply was recorded."
        )
        let response = try LocalAgentBridgeResponse(
            correlationID: request.correlationID,
            discussionReplyReceipt: receipt
        )
        let decodedResponse = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(response)
        )
        #expect(decodedResponse.discussionReplyReceipt == receipt)
        #expect(decodedResponse.discussionReplyReceipt?.recordFormed == true)
        #expect(decodedResponse.context == nil)
        let recovery = LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(
            for: request
        )
        #expect(recovery.safeToRetry)
        #expect(recovery.mustReuseRequestIdentity)
        #expect(recovery.nextStep == .retryExactRequest)
    }

    @Test("Bridge document-write JSON omits only operation-irrelevant fields")
    func documentWriteIntentOperationShapes() throws {
        let run = try #require(ResearchRunLocator(rawValue: "bridgewriteshapeabcd"))
        let credential = try testCredential()
        func wireObject(_ intent: ResearchDocumentWriteIntent) throws -> [String: Any] {
            let request = try LocalAgentBridgeRequest(
                operation: .writeDocument,
                run: run,
                credential: credential,
                documentWriteIntent: intent
            )
            return try #require(JSONSerialization.jsonObject(
                with: LocalAgentBridgeWireCoding.encode(request)
            ) as? [String: Any])
        }

        var create = try wireObject(ResearchDocumentWriteIntent(
            role: .topic,
            relativePath: "Created.md",
            operation: .createNote
        ))
        var createIntent = try #require(
            create["document_write_intent"] as? [String: Any]
        )
        createIntent.removeValue(forKey: "content")
        createIntent.removeValue(forKey: "metadata")
        create["document_write_intent"] = createIntent
        let decodedCreate = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: JSONSerialization.data(withJSONObject: create)
        )
        #expect(decodedCreate.documentWriteIntent?.operation == .createNote)

        var metadata = try wireObject(ResearchDocumentWriteIntent(
            role: .topic,
            relativePath: "Agency.md",
            operation: .modifyMetadata,
            metadata: [try CanonicalPropertyInput(
                key: "aliases",
                value: .array([.string("Exact")])
            )]
        ))
        var metadataIntent = try #require(
            metadata["document_write_intent"] as? [String: Any]
        )
        metadataIntent.removeValue(forKey: "content")
        metadata["document_write_intent"] = metadataIntent
        let decodedMetadata = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: JSONSerialization.data(withJSONObject: metadata)
        )
        #expect(decodedMetadata.documentWriteIntent?.metadata.map(\.key)
            == ["aliases"])

        var markdown = try wireObject(ResearchDocumentWriteIntent(
            role: .topic,
            relativePath: "Agency.md",
            operation: .modifyMarkdown,
            content: ""
        ))
        var markdownIntent = try #require(
            markdown["document_write_intent"] as? [String: Any]
        )
        markdownIntent.removeValue(forKey: "content")
        markdown["document_write_intent"] = markdownIntent
        #expect(throws: (any Error).self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: markdown)
            )
        }

        let sourceText = "\u{FEFF}---\r\ntitle: Complete\r\n---\r\n# Complete\r\n"
        let sourceRequest = try LocalAgentBridgeRequest(
            operation: .writeDocument,
            run: run,
            credential: credential,
            documentWriteIntent: try ResearchDocumentWriteIntent(
                role: .topic,
                relativePath: "Agency.md",
                operation: .modifySource,
                source: sourceText
            )
        )
        let decodedSource = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: LocalAgentBridgeWireCoding.encode(sourceRequest)
        )
        #expect(decodedSource.documentWriteIntent?.operation == .modifySource)
        #expect(decodedSource.documentWriteIntent?.source == sourceText)
    }

    @Test("Bridge Zotero-binding writes use a separate exact payload")
    func zoteroBindingWriteIntentShape() throws {
        let intent = try ResearchZoteroBindingWriteIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000811")!,
            role: .analysis,
            relativePath: "Agency.md",
            operation: .setZoteroBinding,
            library: .group(42),
            itemKey: "item_42"
        )
        let request = try LocalAgentBridgeRequest(
            operation: .writeZoteroBinding,
            run: ResearchRunLocator(rawValue: "bridgezoterowrite123")!,
            credential: try testCredential(),
            zoteroBindingWriteIntent: intent
        )
        let data = try LocalAgentBridgeWireCoding.encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["document_write_intent"] == nil)
        #expect(object["zotero_binding_write_intent"] != nil)
        let decoded = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: data
        )
        #expect(decoded.zoteroBindingWriteIntent == intent)

        var invalid = object
        invalid["document_write_intent"] = [
            "schema_version": ResearchDocumentWriteIntent.currentSchemaVersion,
            "request_id": UUID().uuidString.lowercased(),
            "role": "analysis",
            "relative_path": "Agency.md",
            "operation": "modify_markdown",
            "content": "changed",
            "properties": [],
        ]
        #expect(throws: Error.self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: invalid)
            )
        }
    }

    @Test("A loopback peer is accepted and bridge state persists no credential")
    func loopbackAndSecretBoundary() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let reached = LockedFlag()
        let credential = try testCredential()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.2
        ) { request in
            guard request.operation == .pair else { throw TestFailure.expected }
            reached.set()
            return .credential(credential)
        }
        defer { server.stop() }

        let port = LocalAgentBridgeLocation.port(
            applicationSupportURL: fixture.support
        )
        #expect(LocalAgentBridgeLocation.host == "127.0.0.1")
        #expect(port >= 49_152)
        let response = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 0.5
        ).send(try pairRequest())
        #expect(response.credential == credential)
        #expect(reached.value)

        let enumerator = FileManager.default.enumerator(
            at: fixture.support,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey]))
                .isRegularFile == true else { continue }
            #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self)
                .contains(credential.secret))
        }
    }

    @Test("Malformed, oversized, and idle connections fail closed")
    func boundedFramesAndTimeout() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.1
        ) { _ in throw TestFailure.expected }
        defer { server.stop() }
        let port = LocalAgentBridgeLocation.port(
            applicationSupportURL: fixture.support
        )
        #expect(try sendRawFrame(Data("{}".utf8), to: port).error?.code
            == .invalidRequest)
        #expect(try sendRawPrefix(
            UInt32(LocalAgentBridgeLocation.maximumFrameByteCount + 1),
            to: port
        ).error?.code == .invalidFrame)
        #expect(try sendNothing(to: port).error?.code == .timeout)
    }

    @Test("The largest legal exact-source page fits its complete bridge response envelope")
    func researchContextEnvelopeBudget() throws {
        let context = try maximumExactSourceContextResponse()
        let response = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            researchContext: context
        )
        let data = try LocalAgentBridgeWireCoding.encode(response)

        #expect(data.count < LocalAgentBridgeLocation.maximumFrameByteCount)
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: data
        ).researchContext == context)
    }

    @Test("A timed-out handler is cancelled without a late mutation")
    func handlerTimeoutOwnsCancellation() async throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let entered = LockedFlag()
        let cancellationObserved = LockedFlag()
        let committed = LockedFlag()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.1
        ) { _ in
            entered.set()
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                cancellationObserved.set()
                throw error
            }
            committed.set()
            return .credential(try testCredential())
        }
        defer { server.stop() }
        let client = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 1
        )
        do {
            _ = try client.send(try pairRequest())
            Issue.record("Expected a bounded timeout.")
        } catch let error as LocalAgentBridgeError {
            guard case .remote(let payload) = error else {
                Issue.record("Unexpected bridge error: \(error)")
                return
            }
            #expect(payload.code == .outcomeUnknown)
            #expect(payload.recovery.nextStep == .copyNewHandoffAndPairSameRun)
        }
        #expect(await server.stopAndWait())
        // Under contention cancellation can win before the unstructured
        // handler task starts. If it did start, the server's cancellation
        // grace period must let it observe cancellation before ownership is
        // released.
        #expect(!entered.value || cancellationObserved.value)
        #expect(!committed.value)
    }

    @Test("A committed End with a lost response forbids credential retry")
    func committedEndOutcomeUnknown() async throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let committed = LockedFlag()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.1
        ) { request in
            let run = try #require(request.run)
            #expect(request.operation == .end)
            committed.set()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { /* The terminal mutation already happened. */ }
            return .endReceipt(try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: true,
                message: "The Session was revoked and durable recovery remains."
            ))
        }
        defer { server.stop() }
        let client = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 1
        )
        do {
            _ = try client.send(try endRequest())
            Issue.record("Expected an unknown End outcome.")
        } catch let error as LocalAgentBridgeError {
            guard case .remote(let payload) = error else {
                Issue.record("Unexpected bridge error: \(error)")
                return
            }
            #expect(payload.code == .outcomeUnknown)
            #expect(!payload.recovery.safeToRetry)
            #expect(!payload.recovery.mustReuseRequestIdentity)
            #expect(payload.recovery.nextStep == .stopAndReport)
        }
        #expect(committed.value)
        #expect(await server.stopAndWait())
    }

    @Test("Shutdown awaits the active handler before releasing ownership")
    func shutdownOwnsActiveHandler() async throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let entered = LockedFlag()
        let cancelled = LockedFlag()
        let gate = AsyncGate()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 1
        ) { _ in
            entered.set()
            await gate.wait()
            do { try Task.checkCancellation() }
            catch {
                cancelled.set()
                throw error
            }
            return .credential(try testCredential())
        }
        let client = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 2
        )
        let response = Task.detached { try? client.send(try pairRequest()) }
        for _ in 0..<100 where !entered.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(entered.value)
        let stopped = Task { await server.stopAndWait() }
        try await Task.sleep(for: .milliseconds(25))
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeServer(
                applicationSupportURL: fixture.support
            ) { _ in throw TestFailure.expected }
        }
        await gate.open()
        #expect(await stopped.value)
        _ = await response.value
        #expect(cancelled.value)
        let replacement = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support
        ) { _ in throw TestFailure.expected }
        #expect(await replacement.stopAndWait())
    }

    @Test("Bounded write results round-trip without a retired coordination payload")
    func boundedWriteResultRoundTrip() throws {
        let entry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(runID: UUID(), noteID: UUID()),
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Agency.md"),
            role: .topic,
            title: "Agency",
            allowedOperations: [.modifyMarkdown],
            expectedRevision: DocumentFingerprint(content: "before"),
            authorizationBasis: .initialAction,
            expiresAt: Date().addingTimeInterval(60)
        )
        let result = ResearchDocumentWriteResult(
            operationID: UUID(),
            state: .committed,
            target: ResearchBoundedWriteSetViewEntry(entry),
            message: "Committed and read back.",
            warning: "Old exact source cleanup is pending."
        )
        let response = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            documentWriteResult: result
        )
        let decoded = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(response)
        )
        #expect(decoded.documentWriteResult == result)
        #expect(decoded.documentWriteResult?.warning
            == "Old exact source cleanup is pending.")
    }

    @Test("Method improvement context and one-file submission round-trip without exposing a capability")
    func methodImprovementRoundTrip() throws {
        let locator = try #require(ResearchRunLocator(
            rawValue: "methodimprovementrunabcd"
        ))
        let credential = try testCredential()
        let registration = try ResearchSkillRegistration(
            actionID: .write,
            displayName: "Write Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Write Method\n"
        )
        let improvement = try ResearchMethodImprovementRun(
            id: UUID(),
            parentRecordID: UUID(),
            triptychID: UUID(),
            registrationKey: registration.key,
            actionID: .write,
            method: method,
            feedbackRevision: UUID(),
            feedbackText: "Clarify one preservation boundary.",
            expectedResultFingerprint: DocumentFingerprint(content: "result")
        )
        let context = try ResearchMethodImprovementContext(
            run: locator,
            improvement: improvement
        )
        let contextRequest = try LocalAgentBridgeRequest(
            operation: .methodImprovementContext,
            run: locator,
            credential: credential
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: LocalAgentBridgeWireCoding.encode(contextRequest)
        ).operation == .methodImprovementContext)
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: improvement.feedbackRevision,
            expectedResultFingerprint: improvement.expectedResultFingerprint,
            targetID: "primary-method",
            expectedTargetRevision: method.primaryMarkdownRevision,
            disposition: .diagnosedNoChange,
            diagnosis: "The issue concerns execution rather than the Method."
        )
        let submitRequest = try LocalAgentBridgeRequest(
            operation: .submitMethodImprovement,
            run: locator,
            credential: credential,
            methodImprovementSubmission: submission
        )
        let decodedRequest = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: LocalAgentBridgeWireCoding.encode(submitRequest)
        )
        #expect(decodedRequest.methodImprovementSubmission == submission)
        #expect(!String(reflecting: decodedRequest).contains(credential.secret))

        let contextResponse = try LocalAgentBridgeResponse(
            correlationID: contextRequest.correlationID,
            methodImprovementContext: context
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(contextResponse)
        ).methodImprovementContext == context)
        let receipt = try ResearchMethodImprovementReceipt(
            runID: improvement.id,
            requestID: submission.requestID,
            disposition: submission.disposition,
            targetID: submission.targetID,
            startingRevision: submission.expectedTargetRevision,
            endingRevision: submission.expectedTargetRevision,
            feedbackCleared: true,
            diagnosis: submission.diagnosis
        )
        let receiptResponse = try LocalAgentBridgeResponse(
            correlationID: submitRequest.correlationID,
            methodImprovementReceipt: receipt
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(receiptResponse)
        ).methodImprovementReceipt == receipt)
    }

    @Test("A closed App remains unavailable and a second listener is rejected")
    func absenceAndOwnership() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeClient(
                applicationSupportURL: fixture.support,
                timeout: 0.1
            ).send(try pairRequest())
        }
        let first = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support
        ) { _ in throw TestFailure.expected }
        defer { first.stop() }
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeServer(
                applicationSupportURL: fixture.support
            ) { _ in throw TestFailure.expected }
        }

    }

    private func sendRawFrame(
        _ data: Data,
        to port: UInt16
    ) throws -> LocalAgentBridgeResponse {
        let length = UInt32(data.count)
        let header = Data([
            UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
        ])
        return try withConnectedSocket(to: port) { descriptor in
            try writeAll(header + data, to: descriptor)
            return try readResponse(from: descriptor)
        }
    }

    private func sendRawPrefix(
        _ length: UInt32,
        to port: UInt16
    ) throws -> LocalAgentBridgeResponse {
        try withConnectedSocket(to: port) { descriptor in
            try writeAll(Data([
                UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
                UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
            ]), to: descriptor)
            return try readResponse(from: descriptor)
        }
    }

    private func sendNothing(to port: UInt16) throws -> LocalAgentBridgeResponse {
        try withConnectedSocket(to: port) { try readResponse(from: $0) }
    }

    private func withConnectedSocket<T>(
        to port: UInt16,
        _ body: (Int32) throws -> T
    ) throws -> T {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TestFailure.socket }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(LocalAgentBridgeLocation.host))
        let length = MemoryLayout<sockaddr_in>.size
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(length))
            }
        }
        guard connected == 0 else { throw TestFailure.socket }
        return try body(descriptor)
    }

    private func readResponse(from descriptor: Int32) throws -> LocalAgentBridgeResponse {
        let header = try readExactly(4, from: descriptor)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let data = try readExactly(Int(length), from: descriptor)
        return try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: data
        )
    }

    private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let amount = result.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress!.advanced(by: offset), count - offset)
            }
            guard amount > 0 else { throw TestFailure.socket }
            offset += amount
        }
        return result
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let amount = data.withUnsafeBytes {
                write(descriptor, $0.baseAddress!.advanced(by: offset), data.count - offset)
            }
            guard amount > 0 else { throw TestFailure.socket }
            offset += amount
        }
    }
}

private func pairRequest() throws -> LocalAgentBridgeRequest {
    try LocalAgentBridgeRequest(
        operation: .pair,
        run: ResearchRunLocator(rawValue: "abcdefghijklmnopqrstuvwx")!,
        pairingCode: ResearchPairingCode(rawValue: "23456789ABCDEFGHJKLMNPQR")!
    )
}

private func endRequest() throws -> LocalAgentBridgeRequest {
    try LocalAgentBridgeRequest(
        operation: .end,
        run: ResearchRunLocator(rawValue: "abcdefghijklmnopqrstuvwx")!,
        credential: testCredential()
    )
}

private func testCredential() throws -> ResearchConnectionCredential {
    try ResearchConnectionCredential(
        sessionID: UUID(),
        secret: String(repeating: "s", count: 48),
        expiresAt: Date().addingTimeInterval(3_600)
    )
}

private func testFidelityContext(
    run: ResearchRunLocator
) throws -> ResearchAuthenticatedRunContext {
    let target = ResearchActionNoteSnapshot(
        noteID: UUID(),
        note: VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "Analysis.md"
        ),
        role: .analysis,
        fingerprint: DocumentFingerprint(content: "# Analysis\n"),
        title: "Analysis"
    )
    let inspection = try ResearchContextRequest(clauses: [
        ResearchContextClause(
            kind: .readNote,
            note: target.note,
            expectedFingerprint: target.fingerprint,
            limit: 1,
        ),
    ])
    let profile = try #require(
        ResearchAcademicProfileCatalog.defaultProfiles.first {
            $0.actionID == .checkFidelity
        }
    )
    let registration = try ResearchSkillRegistration(
        actionID: .checkFidelity,
        displayName: "Fidelity Method",
        primaryMarkdown: .machineLocal()
    )
    let method = try ResearchMethodSnapshot(
        registration: registration,
        primaryMarkdownSource: "# Fidelity\n"
    )
    return try ResearchAuthenticatedRunContext(
        brief: ResearchRunBrief(
            run: run,
            actionID: .checkFidelity,
            state: .prepared,
            initialObjectTitle: target.title,
            initialObjectRole: .analysis,
            academicPurpose: nil,
            capabilities: ResearchRunCapabilityAvailability(
                search: true,
                read: true,
                relations: true,
                metadata: true,
                records: true,
                researchState: true,
                zotero: false,
                writeInitialObject: false,
                extendWriteSet: false
            )
        ),
        requiredSkills: [
            .coreProtocol,
            try .actionMethod(method),
        ],
        resultContract: ResearchResultContract(
            profile: profile,
            registrationKey: registration.key,
            profileRevision: try profile.contentRevision()
        ),
        fidelityContract: ResearchFidelityRunContract(
            checks: [.content],
            targets: [target],
            materials: [],
            scope: .whole,
            sourceReference: nil,
            inspectionRequests: [inspection]
        ),
        boundedWriteSet: []
    )
}

private func maximumExactSourceContextResponse() throws -> ResearchContextResponse {
    let runID = UUID()
    let triptychID = UUID()
    let vaultID = UUID()
    let note = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Maximum.md")
    let source = String(
        repeating: "x",
        count: ResearchContextExactSource.maximumUTF8Count
    )
    let clause = try ResearchContextClause(
        kind: .readNote,
        query: "path:Maximum.md",
    )
    let query = try ResearchContextQuery(
        request: ResearchContextRequest(clauses: [clause]),
        runID: runID,
        triptychID: triptychID
    )
    let range = SearchSourceRange(
        utf16LowerBound: 0,
        utf16UpperBound: source.utf16.count,
        line: 1,
        column: 1,
        endLine: 1,
        endColumn: source.utf16.count + 1
    )
    let item = try ResearchContextResponseItem(
        clauseID: clause.id,
        sourceReference: try SourceReferenceEnvelope(
            sourceKind: .note,
            owner: .note(
                triptychID: triptychID,
                note: note,
                stableObjectIdentity: "maximum-source"
            ),
            actorClass: .researcher,
            objectRole: .topic,
            vaultRole: .topicKnowledge,
            fingerprint: DocumentFingerprint(content: source),
            locator: try .sourceRange(range),
            authorizedScope: .triptych(runID: runID, triptychID: triptychID),
            currentness: .current,
            evidentialLayer: .topicNote,
            retrievalReason: .exactRead
        ),
        title: "Maximum",
        contentKind: .noteDocument,
        exactSource: try ResearchContextExactSource(content: source),
    )
    return try ResearchContextResponse(
        query: query,
        outcomes: [try ResearchContextClauseOutcome(
            clause: clause,
            availability: .current,
            items: [item]
        )]
    )
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct BridgeFixture {
    let root: URL
    let support: URL

    init() throws {
        root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(".build/b/\(String(UUID().uuidString.prefix(8)))")
        support = root.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum TestFailure: Error {
    case expected
    case socket
}
