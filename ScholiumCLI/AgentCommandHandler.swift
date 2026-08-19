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
        if arguments.first == "start" {
            guard let triptychID,
                  let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium agent start --triptych <selector> --from <json|->"
                )
            }
            let request = try JSONDecoder().decode(
                ResearchAgentStartRequest.self,
                from: agentInput(input)
            )
            let started = try await operations.start(
                triptychID: triptychID,
                request: request
            )
            try credentialStore.save(started.credential, for: started.receipt.run)
            try writeAgentJSON(started.receipt)
            return
        }
        if arguments.first == "pair" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw CLIError.usage(
                    "Usage: scholium agent pair --run <locator> (pairing code on standard input)"
                )
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
            let credential = try await operations.pair(run: run, pairingCode: code)
            try credentialStore.save(credential, for: run)
            try writeAgentJSON(AgentPairingReport(run: run))
            return
        }
        if arguments.first == "context" || arguments.first == "reload" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun) else {
                throw CLIError.usage(
                    "Usage: scholium agent \(arguments.first ?? "context") --run <locator>"
                )
            }
            let credential = try credentialStore.load(for: run)
            let context = try await operations.context(
                run: run,
                credential: credential
            )
            try writeAgentJSON(context)
            return
        }
        if arguments.first == "query" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium agent query --run <locator> --from <json|->"
                )
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
        if arguments.first == "extend-write-set" {
            guard let rawRun = option("--run", in: arguments),
                  let run = ResearchRunLocator(rawValue: rawRun),
                  let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium agent extend-write-set --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent write --run <locator> --from <json|->"
                )
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
                properties: draft.properties,
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
                throw CLIError.usage(
                    "Usage: scholium agent write-zotero-binding --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent resolve-write-conflict --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent submit-result --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent continue --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent method-context --run <locator>"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent improve-method --run <locator> --from <json|->"
                )
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
                throw CLIError.usage(
                    "Usage: scholium agent end --run <locator>"
                )
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
        throw CLIError.usage(
            "Usage: scholium agent pair|context|reload|query|extend-write-set|write|write-zotero-binding|resolve-write-conflict|submit-result|continue|method-context|improve-method|end"
        )
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
}

private struct AgentPairingReport: Encodable {
    let schemaVersion = 1
    let paired = true
    let run: ResearchRunLocator

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case paired, run
    }
}

private struct AgentDocumentWriteDraft: Codable {
    let role: ResearchActionTargetRole
    let relativePath: String
    let operation: ResearchDocumentWriteOperation
    let content: String
    let source: String?
    let properties: [CanonicalPropertyInput]
    let analysisMetadata: AnalysisCreationMetadata?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operation, content, source, properties
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
        case .createNote, .modifyProperties:
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
        properties = try container.decodeIfPresent(
            [CanonicalPropertyInput].self,
            forKey: .properties
        )?.sorted { $0.key < $1.key } ?? []
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
            properties: properties,
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
