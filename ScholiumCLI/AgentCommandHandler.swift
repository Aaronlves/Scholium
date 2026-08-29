import Foundation
import ScholiumContracts

extension ScholiumCLI {
    private static let maximumAgentInputByteCount = 1_024 * 1_024
    private static let maximumPairingInputByteCount = 256

    static func runAgent(
        _ arguments: [String],
        triptychID: UUID? = nil,
        operations: any AgentBridgeUseCases,
        credentialStore: AgentSessionCredentialStore
    ) async throws {
        if arguments.first == "preflight-analysis" {
            guard let triptychID,
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent preflight-analysis")
            }
            let request = try JSONDecoder().decode(
                ResearchAgentAnalysisCreationPreflightRequest.self,
                from: agentInput(input)
            )
            let preflight = try await operations.preflightAnalysisCreation(
                triptychID: triptychID,
                request: request
            )
            try writeAgentJSON(preflight)
            return
        }
        if arguments.first == "start" {
            guard let triptychID,
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent start")
            }
            let request = try JSONDecoder().decode(
                ResearchAgentStartRequest.self,
                from: agentInput(input)
            )
            try credentialStore.prepare()
            let started = try await operations.start(
                triptychID: triptychID,
                request: request
            )
            try await persistNewCredential(
                started.credential,
                for: started.receipt.run,
                operations: operations,
                credentialStore: credentialStore
            )
            let context = try await initialContext(
                for: started.receipt.run,
                credential: started.credential,
                operations: operations
            )
            try writeAgentJSON(AgentStartReport(
                receipt: started.receipt,
                context: context
            ))
            return
        }
        if arguments.first == "pair" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw commandUsageError("agent pair")
            }
            let input = try boundedAgentInput(
                from: FileHandle.standardInput,
                maximumByteCount: maximumPairingInputByteCount
            )
            let rawCode = String(decoding: input, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard let code = ResearchPairingCode(rawValue: rawCode) else {
                throw CLIError.usage("Standard input did not contain one valid Pairing Code.")
            }
            try credentialStore.prepare()
            let credential = try await operations.pair(run: run, pairingCode: code)
            try await persistNewCredential(
                credential,
                for: run,
                operations: operations,
                credentialStore: credentialStore
            )
            let context = try await initialPairedContext(
                for: run,
                credential: credential,
                operations: operations
            )
            try writeAgentJSON(AgentPairingReport(run: run, context: context))
            return
        }
        if arguments.first == "reload" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw commandUsageError("agent reload")
            }
            let credential = try credentialStore.load(for: run)
            let context = try await operations.initialContext(
                run: run,
                credential: credential
            )
            switch context {
            case .action(let value):
                try writeAgentJSON(value)
            case .methodImprovement(let value):
                try writeAgentJSON(value)
            }
            return
        }
        if arguments.first == "query" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent query")
            }
            let data = try agentInput(input)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(ResearchContextRequest.self, from: data)
            let credential = try credentialStore.load(for: run)
            let response = try await operations.query(
                run: run,
                credential: credential,
                request: request
            )
            try writeAgentJSON(response)
            return
        }
        if arguments.first == "related" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw commandUsageError("agent related")
            }
            let noteNames = options("--note", in: arguments)
            let limitText = option("--limit", in: arguments) ?? "8"
            guard !noteNames.isEmpty,
                  noteNames.count <= ResearchContextClause.maximumRelatedNoteNames,
                  let limit = Int(limitText),
                  (1...RelatedContentContract.maximumCandidates).contains(limit) else {
                throw commandUsageError("agent related")
            }
            let clause = try ResearchContextClause(
                kind: .relatedNotes,
                noteNames: noteNames,
                limit: limit
            )
            let request = try ResearchContextRequest(clauses: [clause])
            let credential = try credentialStore.load(for: run)
            let response = try await operations.query(
                run: run,
                credential: credential,
                request: request
            )
            try writeAgentJSON(response)
            return
        }
        if arguments.first == "discuss-reply" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent discuss-reply")
            }
            let draft = try JSONDecoder().decode(
                AgentDiscussionReplyDraft.self,
                from: agentInput(input)
            )
            let request = try ResearchAgentDiscussionReplyRequest(
                statementID: draft.statementID,
                attribution: draft.attribution,
                text: draft.text
            )
            let store = credentialStore
            let credential = try store.load(for: run)
            let receipt = try await operations.replyToDiscussion(
                run: run,
                credential: credential,
                request: request
            )
            do {
                try store.remove(for: run)
            } catch {
                writeError(
                    "scholium: warning: The Discussion formed its Research Record, but its now-finalized local credential file could not be removed. Repair the protected Session store before using this Run again.\n"
                )
            }
            try writeAgentJSON(receipt)
            return
        }
        if arguments.first == "extend-write-set" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent extend-write-set")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let intent = try decoder.decode(
                ResearchWriteSetExtensionIntent.self,
                from: agentInput(input)
            )
            let credential = try credentialStore.load(for: run)
            let result = try await operations.extendWriteSet(
                run: run,
                credential: credential,
                intent: intent
            )
            try writeAgentJSON(AgentWriteSetReport(result))
            return
        }
        if arguments.first == "write" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent write")
            }
            let draft = try JSONDecoder().decode(
                AgentDocumentWriteDraft.self,
                from: agentInput(input)
            )
            let requestID = try stableAgentWriteRequestID(run: run, draft: draft)
            let intent = try ResearchDocumentWriteIntent(
                requestID: requestID,
                role: draft.role,
                relativePath: draft.relativePath,
                operation: draft.operation,
                content: draft.content,
                source: draft.source,
                metadata: draft.metadata,
                authoredYAML: draft.authoredYAML,
                analysisMetadata: draft.analysisMetadata
            )
            let credential = try credentialStore.load(for: run)
            let result = try await operations.writeDocument(
                run: run,
                credential: credential,
                intent: intent
            )
            try writeAgentJSON(AgentDocumentWriteReport(result))
            return
        }
        if arguments.first == "write-zotero-binding" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent write-zotero-binding")
            }
            let draft = try JSONDecoder().decode(
                AgentZoteroBindingWriteDraft.self,
                from: agentInput(input)
            )
            let intent = try ResearchZoteroBindingWriteIntent(
                requestID: try stableAgentZoteroBindingWriteRequestID(
                    run: run,
                    draft: draft
                ),
                role: draft.role,
                relativePath: draft.relativePath,
                operation: draft.operation,
                library: draft.library,
                itemKey: draft.itemKey
            )
            let credential = try credentialStore.load(for: run)
            let result = try await operations.writeZoteroBinding(
                run: run,
                credential: credential,
                intent: intent
            )
            try writeAgentJSON(AgentZoteroBindingWriteReport(result))
            return
        }
        if arguments.first == "resolve-write-conflict" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent resolve-write-conflict")
            }
            let draft = try JSONDecoder().decode(
                AgentWriteConflictResolutionDraft.self,
                from: agentInput(input)
            )
            let intent = try ResearchWriteConflictResolutionIntent(
                requestID: stableAgentConflictResolutionRequestID(
                    run: run,
                    draft: draft
                ),
                role: draft.role,
                relativePath: draft.relativePath,
                action: draft.action
            )
            let credential = try credentialStore.load(for: run)
            let result = try await operations.resolveWriteConflict(
                run: run,
                credential: credential,
                intent: intent
            )
            try writeAgentJSON(AgentWriteConflictResolutionReport(result))
            return
        }
        if arguments.first == "submit-result" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent submit-result")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let submission = try decoder.decode(
                ResearchAgentResultSubmission.self,
                from: agentInput(input)
            )
            let credential = try credentialStore.load(for: run)
            let receipt = try await operations.submitResult(
                run: run,
                credential: credential,
                submission: submission
            )
            try writeAgentJSON(receipt)
            return
        }
        if arguments.first == "continue" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent continue")
            }
            let request = try JSONDecoder().decode(
                ResearchContinuationRequest.self,
                from: agentInput(input)
            )
            let credential = try credentialStore.load(for: run)
            let result = try await operations.continueResearch(
                run: run,
                credential: credential,
                request: request
            )
            try writeAgentJSON(result)
            return
        }
        if arguments.first == "method-context" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw commandUsageError("agent method-context")
            }
            let credential = try credentialStore.load(for: run)
            let context = try await operations.methodImprovementContext(
                run: run,
                credential: credential
            )
            try writeAgentJSON(context)
            return
        }
        if arguments.first == "improve-method" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw commandUsageError("agent improve-method")
            }
            let draft = try JSONDecoder().decode(
                ResearchMethodImprovementDraft.self,
                from: agentInput(input)
            )
            let credential = try credentialStore.load(for: run)
            let context = try await operations.methodImprovementContext(
                run: run,
                credential: credential
            )
            guard let target = context.targets.first(where: {
                $0.id == draft.targetID
            }) else {
                throw CLIError.usage(
                    "The selected Method improvement target is not in the current authenticated Run context."
                )
            }
            let submission = try ResearchMethodImprovementSubmission(
                requestID: stableMethodImprovementRequestID(
                    run: run,
                    draft: draft
                ),
                feedbackRevision: context.feedbackRevision,
                expectedResultFingerprint:
                    context.expectedResultFingerprint,
                targetID: target.id,
                expectedTargetRevision: target.revision,
                disposition: draft.disposition,
                replacementSource: draft.replacementSource,
                diagnosis: draft.diagnosis
            )
            let receipt = try await operations.submitMethodImprovement(
                run: run,
                credential: credential,
                submission: submission
            )
            try writeAgentJSON(receipt)
            return
        }
        if arguments.first == "end" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw commandUsageError("agent end")
            }
            let store = credentialStore
            let credential = try store.load(for: run)
            let receipt = try await operations.end(
                run: run,
                credential: credential
            )
            do {
                try store.remove(for: run)
            } catch {
                writeError(
                    "scholium: warning: The Run ended, but its now-revoked local credential file could not be removed. Repair the protected Session store before pairing this Run again.\n"
                )
            }
            try writeAgentJSON(receipt)
            return
        }
        throw commandUsageError("agent")
    }

    private static func writeAgentJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        write(String(decoding: try encoder.encode(value), as: UTF8.self) + "\n")
    }

    private static func agentInput(_ specification: String) throws -> Data {
        if specification == "-" {
            return try boundedAgentInput(
                from: FileHandle.standardInput,
                maximumByteCount: maximumAgentInputByteCount
            )
        }
        let url = URL(
            fileURLWithPath: (specification as NSString).expandingTildeInPath
        )
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try boundedAgentInput(
            from: handle,
            maximumByteCount: maximumAgentInputByteCount
        )
    }

    private static func boundedAgentInput(
        from handle: FileHandle,
        maximumByteCount: Int
    ) throws -> Data {
        let data = try handle.read(upToCount: maximumByteCount + 1) ?? Data()
        guard data.count <= maximumByteCount else {
            throw CLIError.usage(
                "The Agent input exceeded its \(maximumByteCount)-byte limit."
            )
        }
        return data
    }

    private static func stableAgentWriteRequestID(
        run: ResearchRunLocator,
        draft: AgentDocumentWriteDraft
    ) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let fingerprint = DocumentFingerprint(
            data: try encoder.encode(AgentDocumentWriteDigest(run: run, draft: draft))
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func stableAgentZoteroBindingWriteRequestID(
        run: ResearchRunLocator,
        draft: AgentZoteroBindingWriteDraft
    ) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let fingerprint = DocumentFingerprint(
            data: try encoder.encode(
                AgentZoteroBindingWriteDigest(run: run, draft: draft)
            )
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func stableAgentConflictResolutionRequestID(
        run: ResearchRunLocator,
        draft: AgentWriteConflictResolutionDraft
    ) -> UUID {
        let fingerprint = DocumentFingerprint(
            content: [
                run.rawValue,
                draft.role.rawValue,
                draft.relativePath,
                draft.action.rawValue,
            ].joined(separator: "\u{001F}")
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func stableMethodImprovementRequestID(
        run: ResearchRunLocator,
        draft: ResearchMethodImprovementDraft
    ) -> UUID {
        let fingerprint = DocumentFingerprint(
            content: [
                run.rawValue,
                draft.targetID,
                draft.disposition.rawValue,
                draft.replacementSource ?? "",
                draft.diagnosis,
            ].joined(separator: "\u{001F}")
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func persistNewCredential(
        _ credential: ResearchConnectionCredential,
        for run: ResearchRunLocator,
        operations: any AgentBridgeUseCases,
        credentialStore: AgentSessionCredentialStore
    ) async throws {
        do {
            try credentialStore.save(credential, for: run)
        } catch {
            let revocationConfirmed: Bool
            do {
                let receipt = try await operations.revokeSession(credential)
                revocationConfirmed = receipt.sessionID == credential.sessionID
            } catch {
                revocationConfirmed = false
            }
            throw AgentSessionPersistenceError(
                run: run,
                revocationConfirmed: revocationConfirmed
            )
        }
    }

    /// Delivers the first authenticated context without making the Agent
    /// perform a second public lifecycle operation. If transport delivery
    /// fails after the Session is stored, the existing Run and credential are
    /// intentionally retained so `reload` can recover them exactly.
    private static func initialContext(
        for run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        operations: any AgentBridgeUseCases
    ) async throws -> ResearchAuthenticatedRunContext {
        do {
            return try await operations.context(run: run, credential: credential)
        } catch {
            throw AgentInitialContextDeliveryError(run: run)
        }
    }

    private static func initialPairedContext(
        for run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        operations: any AgentBridgeUseCases
    ) async throws -> ResearchAgentInitialContext {
        do {
            return try await operations.initialContext(
                run: run,
                credential: credential
            )
        } catch {
            throw AgentInitialContextDeliveryError(run: run)
        }
    }
}

private struct AgentInitialContextDeliveryError: LocalizedError,
    AgentCommandErrorCodeProviding
{
    let run: ResearchRunLocator

    var errorDescription: String? {
        "The Session for Run \(run.rawValue) was stored, but its initial authenticated context could not be delivered. Do not repeat start or pair; run scholium agent reload --run \(run.rawValue)."
    }

    var agentCommandErrorCode: String { "initial_context_unavailable" }

    var agentCommandRecovery: AgentOperationRecovery? {
        AgentOperationRecovery(
            safeToRetry: true,
            mustReuseRequestIdentity: false,
            nextStep: .reloadCurrentRun
        )
    }
}

private struct AgentSessionPersistenceError: LocalizedError,
    AgentCommandErrorCodeProviding
{
    let run: ResearchRunLocator
    let revocationConfirmed: Bool

    var errorDescription: String? {
        if revocationConfirmed {
            return "The protected local Session store became unavailable after Session creation. Scholium revoked that Session; Run \(run.rawValue) remains active. Copy a new handoff and pair the same Run."
        }
        return "The protected local Session store became unavailable after Session creation, and revocation could not be confirmed for Run \(run.rawValue). Stop and report this state without retrying the request."
    }

    var agentCommandErrorCode: String { "session_store_unavailable" }

    var agentCommandRecovery: AgentOperationRecovery? {
        AgentOperationRecovery(
            safeToRetry: false,
            mustReuseRequestIdentity: revocationConfirmed,
            nextStep: revocationConfirmed
                ? .copyNewHandoffAndPairSameRun
                : .stopAndReport
        )
    }
}

private struct AgentStartReport: Encodable {
    let schemaVersion = 1
    let receipt: ResearchAgentStartReceipt
    let context: ResearchAuthenticatedRunContext

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case receipt, context
    }
}

private struct AgentPairingReport: Encodable {
    let schemaVersion = 2
    let paired = true
    let run: ResearchRunLocator
    let context: ResearchAgentInitialContext

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case paired, run
        case contextKind = "context_kind"
        case context
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(paired, forKey: .paired)
        try container.encode(run, forKey: .run)
        switch context {
        case .action(let value):
            try container.encode("action", forKey: .contextKind)
            try container.encode(value, forKey: .context)
        case .methodImprovement(let value):
            try container.encode("method_improvement", forKey: .contextKind)
            try container.encode(value, forKey: .context)
        }
    }
}

private struct AgentDiscussionReplyDraft: Decodable {
    let statementID: UUID
    let attribution: String
    let text: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case statementID = "statement_id"
        case attribution
        case text
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AgentWriteCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw CLIError.usage(
                "The Agent Discussion reply JSON contains an unknown field."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statementID = try container.decode(UUID.self, forKey: .statementID)
        attribution = try container.decode(String.self, forKey: .attribution)
        text = try container.decode(String.self, forKey: .text)
    }
}

private struct AgentDocumentWriteDraft: Codable {
    let role: ResearchActionTargetRole
    let relativePath: String
    let operation: ResearchDocumentWriteOperation
    let content: String
    let source: String?
    let metadata: [CanonicalPropertyInput]
    let authoredYAML: AuthoredNoteYAML?
    let analysisMetadata: AnalysisCreationMetadata?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operation, content, source, metadata
        case authoredYAML = "authored_yaml"
        case analysisMetadata = "analysis_metadata"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AgentWriteCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw CLIError.usage("The Agent write JSON contains an unknown field.")
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ResearchActionTargetRole.self, forKey: .role)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        operation = try container.decodeIfPresent(
            ResearchDocumentWriteOperation.self,
            forKey: .operation
        ) ?? .modifyMarkdown
        switch operation {
        case .modifyMarkdown:
            guard container.contains(.content) else {
                throw CLIError.usage(
                    "modify_markdown requires an explicit content string; use an explicit empty string only to intentionally clear the body."
                )
            }
            content = try container.decode(String.self, forKey: .content)
            source = try container.decodeIfPresent(String.self, forKey: .source)
        case .modifySource:
            guard container.contains(.source) else {
                throw CLIError.usage(
                    "modify_source requires an explicit complete Markdown source string."
                )
            }
            source = try container.decode(String.self, forKey: .source)
            content = try container.decodeIfPresent(
                String.self,
                forKey: .content
            ) ?? ""
        case .createNote, .modifyMetadata:
            content = try container.decodeIfPresent(
                String.self,
                forKey: .content
            ) ?? ""
            source = try container.decodeIfPresent(String.self, forKey: .source)
        case .setZoteroBinding, .clearZoteroBinding:
            throw CLIError.usage(
                "Use agent write-zotero-binding for portable Zotero relationship mutations."
            )
        }
        metadata = try container.decodeIfPresent(
            [CanonicalPropertyInput].self,
            forKey: .metadata
        )?.sorted { $0.key < $1.key } ?? []
        authoredYAML = try container.decodeIfPresent(
            AuthoredNoteYAML.self,
            forKey: .authoredYAML
        )
        analysisMetadata = try container.decodeIfPresent(
            AnalysisCreationMetadata.self,
            forKey: .analysisMetadata
        )
        _ = try ResearchDocumentWriteIntent(
            role: role,
            relativePath: relativePath,
            operation: operation,
            content: content,
            source: source,
            metadata: metadata,
            authoredYAML: authoredYAML,
            analysisMetadata: analysisMetadata
        )
    }
}

private struct AgentDocumentWriteDigest: Encodable {
    let run: ResearchRunLocator
    let draft: AgentDocumentWriteDraft
}

private struct AgentZoteroBindingWriteDraft: Codable {
    let role: ResearchActionTargetRole
    let relativePath: String
    let operation: ResearchDocumentWriteOperation
    let library: ZoteroLibraryIdentity?
    let itemKey: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operation, library
        case itemKey = "item_key"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AgentWriteCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw CLIError.usage(
                "The Agent Zotero binding JSON contains an unknown field."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ResearchActionTargetRole.self, forKey: .role)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        operation = try container.decode(
            ResearchDocumentWriteOperation.self,
            forKey: .operation
        )
        library = try container.decodeIfPresent(
            ZoteroLibraryIdentity.self,
            forKey: .library
        )
        itemKey = try container.decodeIfPresent(String.self, forKey: .itemKey)
        _ = try ResearchZoteroBindingWriteIntent(
            role: role,
            relativePath: relativePath,
            operation: operation,
            library: library,
            itemKey: itemKey
        )
    }
}

private struct AgentZoteroBindingWriteDigest: Encodable {
    let run: ResearchRunLocator
    let draft: AgentZoteroBindingWriteDraft
}

private struct AgentWriteConflictResolutionDraft: Decodable {
    let role: ResearchActionTargetRole
    let relativePath: String
    let action: ResearchWriteConflictResolutionAction

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case action
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AgentWriteCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw CLIError.usage(
                "The Agent write-conflict JSON contains an unknown field."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ResearchActionTargetRole.self, forKey: .role)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        action = try container.decode(
            ResearchWriteConflictResolutionAction.self,
            forKey: .action
        )
    }
}

private struct AgentWriteSetReport: Encodable {
    let schemaVersion = 1
    let state: ResearchWriteSetExtensionState
    let entries: [ResearchBoundedWriteSetViewEntry]
    let message: String

    init(_ result: ResearchWriteSetExtensionResult) {
        state = result.state
        entries = result.entries
        message = result.message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state, entries, message
    }
}

private struct AgentDocumentWriteReport: Encodable {
    let schemaVersion = 1
    let state: ResearchDocumentWriteState
    let target: ResearchBoundedWriteSetViewEntry
    let message: String
    let warning: String?

    init(_ result: ResearchDocumentWriteResult) {
        state = result.state
        target = result.target
        message = result.message
        warning = result.warning
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state, target, message, warning
    }
}

private struct AgentZoteroBindingWriteReport: Encodable {
    let schemaVersion = 1
    let state: ResearchZoteroBindingWriteState
    let target: ResearchBoundedWriteSetViewEntry
    let message: String
    let warning: String?

    init(_ result: ResearchZoteroBindingWriteResult) {
        state = result.state
        target = result.target
        message = result.message
        warning = result.warning
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state, target, message, warning
    }
}

private struct AgentWriteConflictResolutionReport: Encodable {
    let schemaVersion = 1
    let state: ResearchWriteConflictResolutionState
    let target: ResearchBoundedWriteSetViewEntry
    let message: String

    init(_ result: ResearchWriteConflictResolutionResult) {
        state = result.state
        target = result.target
        message = result.message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state, target, message
    }
}

private struct AgentWriteCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
