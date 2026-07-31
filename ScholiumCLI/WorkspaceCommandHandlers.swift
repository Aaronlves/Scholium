import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func runVault(_ arguments: [String], context: CLIContext) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium vault list")
        }
        switch subcommand {
        case "list":
            let triptychs = try await context.assignments()
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Vault list supports --format text or json.")
            }
            if format == "json" {
                let payload = triptychs.map { assignment -> [String: Any] in
                    let vaults = WorkspaceVaultSlot.allCases.compactMap { slot -> [String: Any]? in
                        guard let vault = assignment.vault(for: slot) else { return nil }
                        return [
                            "role": slot.rawValue,
                            "id": vault.id.uuidString.lowercased(),
                            "name": vault.name,
                            "path": vault.canonicalPath,
                        ]
                    }
                    return [
                        "id": assignment.id.uuidString.lowercased(),
                        "name": assignment.triptych.name,
                        "vaults": vaults,
                    ]
                }
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else if triptychs.isEmpty {
                write("No Scholium Triptychs are configured. Use Scholium onboarding or Manage Triptychs.\n")
            } else {
                for assignment in triptychs {
                    write("\(assignment.id.uuidString)  \(assignment.triptych.name)\n")
                    for slot in WorkspaceVaultSlot.allCases {
                        guard let vault = assignment.vault(for: slot) else { continue }
                        write("  \(slot.displayName): \(vault.id.uuidString)\n    \(vault.canonicalPath)\n")
                    }
                }
            }
        default:
            throw CLIError.usage(
                "Unknown vault command '\(subcommand)'. Configure complete Triptychs in Scholium; use 'scholium vault list' for CLI discovery."
            )
        }
    }

    static func runSearch(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let first = arguments.first else {
            throw CLIError.usage("Usage: scholium search <query> (--vault <selector> | --triptych <selector>) [options]")
        }
        let query: String
        let assignment: TriptychAssignment
        let executionScope: SearchExecutionScope
        let presentationScope: SearchPresentationScope
        if let selector = option("--vault", in: arguments) {
            query = first
            let vault = try await context.resolveVault(selector)
            if let triptychSelector = option("--triptych", in: arguments) {
                assignment = try await context.selectedTriptych(selector: triptychSelector)
                guard assignment.vaults.values.contains(where: { $0.id == vault.id }) else {
                    throw CLIError.usage("The selected vault is not a member of the selected Triptych.")
                }
            } else {
                assignment = try await context.triptych(containing: [vault.id])
            }
            executionScope = .currentVault(vault.id)
            presentationScope = .currentVault
        } else if let selector = option("--triptych", in: arguments) {
            query = first
            assignment = try await context.selectedTriptych(selector: selector)
            executionScope = .triptych
            presentationScope = .triptych
        } else {
            throw CLIError.usage("Choose --vault <selector> or --triptych <uuid-or-unique-name>.")
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw CLIError.usage("Search query cannot be empty.") }
        let limitText = option("--limit", in: arguments) ?? "20"
        guard let limit = Int(limitText), (1 ... 500).contains(limit) else {
            throw CLIError.usage("--limit must be a whole number from 1 through 500.")
        }
        let handle = try await context.handle(for: assignment)
        let response = try await handle.discovery.search(SearchRequest(
            query: trimmedQuery,
            presentationScope: presentationScope,
            executionScope: executionScope,
            limit: limit
        ))
        if let diagnostic = response.diagnostics.first {
            throw CLIError.usage(diagnostic.message)
        }
        let format = option("--format", in: arguments) ?? "text"
        switch format {
        case "jsonl":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let summary = SearchSummaryRecord(response: response)
            write(String(decoding: try encoder.encode(summary), as: UTF8.self) + "\n")
            for hit in response.results {
                write(String(
                    decoding: try encoder.encode(SearchResultRecord(hit: hit)),
                    as: UTF8.self
                ) + "\n")
            }
        case "text":
            if response.results.isEmpty { write("No matches.\n") }
            for hit in response.results {
                let line = hit.sourceRange?.line ?? hit.sourceLine
                let column = hit.sourceRange?.column ?? 1
                write(
                    "\(hit.vaultName):\(hit.relativePath):\(line):\(column) "
                        + "[retrieval_lead; \(hit.rankReason.rawValue)]\n  \(hit.snippet)\n"
                )
            }
        default:
            throw CLIError.usage("--format must be text or jsonl.")
        }
    }

    private struct SearchSummaryRecord: Encodable {
        let type = "search_summary"
        let contractVersion: Int
        let generation: SearchGenerationID?
        let scope: String
        let status: String
        let resultCount: Int
        let hasMore: Bool

        init(response: SearchResponse) {
            contractVersion = response.contractVersion
            generation = response.availability.lastGoodGeneration
            scope = response.scope.rawValue
            status = switch response.availability {
            case .unavailable: "unavailable"
            case .building: "building"
            case .current: "current"
            case .refreshing: "refreshing"
            case .stale: "stale"
            case .failed: "failed"
            }
            resultCount = response.results.count
            hasMore = response.hasMore
        }

        enum CodingKeys: String, CodingKey {
            case type
            case contractVersion = "contract_version"
            case generation, scope, status
            case resultCount = "result_count"
            case hasMore = "has_more"
        }
    }

    private struct SearchResultRecord: Encodable {
        let type = "search_result"
        let resultID: String
        let vaultID: UUID
        let vaultName: String
        let vaultRole: VaultRole
        let relativePath: String
        let stableNoteID: String?
        let title: String
        let matchedFields: [SearchMatchedField]
        let rankReason: SearchRankReason
        let snippet: String
        let highlights: [SearchHighlight]
        let sourceRange: SearchSourceRange?
        let fingerprint: DocumentFingerprint
        let freshnessToken: SearchFreshnessToken
        let classification: SearchResultClassification

        init(hit: SearchHit) {
            resultID = hit.resultID
            vaultID = hit.vaultID
            vaultName = hit.vaultName
            vaultRole = hit.vaultRole
            relativePath = hit.relativePath
            stableNoteID = hit.stableNoteID
            title = hit.title
            matchedFields = hit.matchedFields
            rankReason = hit.rankReason
            snippet = hit.snippet
            highlights = hit.highlights
            sourceRange = hit.sourceRange
            fingerprint = hit.fingerprint
            freshnessToken = hit.freshnessToken
            classification = hit.classification
        }

        enum CodingKeys: String, CodingKey {
            case type
            case resultID = "result_id"
            case vaultID = "vault_id"
            case vaultName = "vault_name"
            case vaultRole = "vault_role"
            case relativePath = "relative_path"
            case stableNoteID = "stable_note_id"
            case title
            case matchedFields = "matched_fields"
            case rankReason = "rank_reason"
            case snippet, highlights
            case sourceRange = "source_range"
            case fingerprint
            case freshnessToken = "freshness_token"
            case classification
        }
    }

    static func runLinks(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium links <incoming|outgoing|relationships|diagnostics> ...")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Links commands support --format json.")
        }
        switch subcommand {
        case "incoming", "outgoing":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: scholium links \(subcommand) <vault>:<path> --format json")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let catalog = try await handle.discovery.snapshot().catalog
            guard let snapshot = catalog.graph else {
                throw CLIError.unavailable("The Triptych graph is not ready.")
            }
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let edges = subcommand == "incoming" ? (snapshot.incoming[id] ?? []) : (snapshot.outgoing[id] ?? [])
            write(String(decoding: try encoder.encode(edges), as: UTF8.self) + "\n")
        case "relationships":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: scholium links relationships <vault>:<path> --format json")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let catalog = try await handle.discovery.snapshot().catalog
            guard let snapshot = catalog.graph else {
                throw CLIError.unavailable("The Triptych graph is not ready.")
            }
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let relationships = snapshot.relationships.filter {
                $0.subjectNote == id || $0.objectNote == id
                    || ($0.subjectNote == nil && $0.objectNote == nil
                        && ($0.subjectPath == path || $0.objectPath == path))
            }
            write(String(decoding: try encoder.encode(relationships), as: UTF8.self) + "\n")
        case "diagnostics":
            guard arguments.contains("--workspace") else {
                throw CLIError.usage("Usage: scholium links diagnostics --workspace [--triptych <selector>] --format json")
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let catalog = try await handle.discovery.snapshot().catalog
            guard let graph = catalog.graph else {
                throw CLIError.unavailable("The Triptych graph is not ready.")
            }
            let diagnostics = graph.diagnostics
            write(String(decoding: try encoder.encode(diagnostics), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("Unknown links command '\(subcommand)'.")
        }
    }

    static func runGraph(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard ["trace", "relation-trace"].contains(arguments.first ?? ""), arguments.count >= 3 else {
            throw CLIError.usage("Usage: scholium graph <trace|relation-trace> <source> <target> --max-depth 3 --format json")
        }
        let (sourceVault, sourcePath) = try await context.resolveTarget(arguments[1])
        let (targetVault, targetPath) = try await context.resolveTarget(arguments[2])
        let assignment = try await context.triptych(containing: [sourceVault.id, targetVault.id])
        let maximumDepthText = option("--max-depth", in: arguments) ?? "3"
        guard let maximumDepth = Int(maximumDepthText),
              (1 ... 10).contains(maximumDepth) else {
            throw CLIError.usage("--max-depth must be a whole number from 1 through 10.")
        }
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Graph commands support --format json.")
        }
        let handle = try await context.handle(for: assignment)
        let catalog = try await handle.discovery.snapshot().catalog
        guard let snapshot = catalog.graph else {
            throw CLIError.unavailable("The Triptych graph is not ready.")
        }
        let source = VaultQualifiedNoteID(vaultID: sourceVault.id, relativePath: sourcePath)
        let target = VaultQualifiedNoteID(vaultID: targetVault.id, relativePath: targetPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if arguments.first == "relation-trace" {
            let paths = relationshipTracePaths(
                from: source,
                to: target,
                snapshot: snapshot,
                maximumDepth: maximumDepth
            )
            write(String(decoding: try encoder.encode(paths), as: UTF8.self) + "\n")
        } else {
            let paths = tracePaths(from: source, to: target, snapshot: snapshot, maximumDepth: maximumDepth)
            write(String(decoding: try encoder.encode(paths), as: UTF8.self) + "\n")
        }
    }

    static func runWorkspace(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium workspace <catalog|attention|bootstrap>")
        }
        if subcommand == "bootstrap" {
            try await runWorkspaceBootstrap(Array(arguments.dropFirst()), context: context)
            return
        }
        let assignment = try await context.selectedTriptych(
            selector: option("--triptych", in: arguments)
        )
        let handle = try await context.handle(for: assignment)
        let snapshot = try await handle.discovery.snapshot().catalog
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Workspace catalog and attention support --format json.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        switch subcommand {
        case "catalog":
            write(String(decoding: try encoder.encode(snapshot), as: UTF8.self) + "\n")
        case "attention":
            let items: [AttentionQueueItem]
            if let kindText = option("--kind", in: arguments) {
                guard let kind = AttentionQueueKind(rawValue: kindText) else {
                    throw CLIError.usage("Unknown attention queue '\(kindText)'.")
                }
                items = snapshot.attention.filter { $0.kind == kind }
            } else {
                items = snapshot.attention
            }
            write(String(decoding: try encoder.encode(items), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("Unknown workspace command '\(subcommand)'.")
        }
    }

    private static func runWorkspaceBootstrap(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let selector = option("--triptych", in: arguments),
              let targetPath = option("--target", in: arguments) else {
            throw CLIError.usage(
                "Usage: scholium workspace bootstrap --triptych <uuid-or-unique-name> --target <directory> [--conventions-file <file>] [--format markdown|json]"
            )
        }
        let assignment = try await context.triptych(selector: selector)
        let targetURL = URL(
            fileURLWithPath: (targetPath as NSString).expandingTildeInPath,
            isDirectory: true
        )
        let conventions: String
        if let conventionsPath = option("--conventions-file", in: arguments) {
            let url = URL(
                fileURLWithPath: (conventionsPath as NSString).expandingTildeInPath,
                isDirectory: false
            )
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw CLIError.invalidUTF8(url.path)
            }
            conventions = content
        } else {
            conventions = "None recorded."
        }
        let request = WorkspaceBootstrapRequest(
            triptychSelector: assignment.workspace.id.uuidString,
            triptychName: assignment.triptych.name,
            targetURL: targetURL,
            researcherConventions: conventions
        )
        let candidate = try context.runtime.bootstrapCandidate(for: request)
        let format = option("--format", in: arguments) ?? "markdown"
        switch format {
        case "markdown":
            // This command is deliberately candidate-only. An external agent
            // must promote the output after its own final target verification.
            write(candidate.content)
        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            write(String(decoding: try encoder.encode(candidate), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("--format must be markdown or json.")
        }
    }

    static func runSkills(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium skills <catalog|show|resources> [options]"
            )
        }
        let workspaceResearch: (any ResearchSkillUseCases)?
        if let selector = option("--triptych", in: arguments) {
            let assignment = try await context.triptych(selector: selector)
            workspaceResearch = try await context.handle(for: assignment).research
        } else {
            workspaceResearch = nil
        }
        let catalog = if let workspaceResearch {
            try await workspaceResearch.skillCatalog()
        } else {
            try await context.runtime.researchGuidance.catalog()
        }
        let format = option("--format", in: arguments) ?? "text"

        func skills() async throws -> [ResearchSkillPackage] {
            if let workspaceResearch {
                return try await workspaceResearch.skills()
            }
            return try await context.runtime.researchGuidance.skills()
        }

        func resolvedPackage(id: String) async throws -> ResearchSkillPackage {
            if let workspaceResearch {
                return try await workspaceResearch.skillPackage(id: id)
            }
            return try await context.runtime.researchGuidance.package(id: id)
        }

        func resourcePaths(id: String) async throws -> [String] {
            if let workspaceResearch {
                return try await workspaceResearch.skillResourcePaths(id: id)
            }
            return try await context.runtime.researchGuidance.resourcePaths(id: id)
        }

        func resource(id: String, relativePath: String) async throws -> String {
            if let workspaceResearch {
                return try await workspaceResearch.skillResource(
                    id: id,
                    relativePath: relativePath
                )
            }
            return try await context.runtime.researchGuidance.resource(
                id: id,
                relativePath: relativePath
            )
        }

        func packagePayload(_ package: ResearchSkillPackage) -> [String: Any] {
            var payload: [String: Any] = [
                "id": package.id,
                "name": package.name,
                "description": package.description,
                "class": package.skillClass.rawValue,
                "role": package.role,
                "version": package.version,
                "origin": package.origin.rawValue,
                "update_policy": package.updatePolicy,
                "supported_modes": package.supportedModes.map(\.rawValue),
                "automatic_modes": package.automaticModes.map(\.rawValue),
                "compatible_practices": package.compatiblePracticeIDs,
                "required_skills": package.requiredSkillIDs,
                "practice_resources": package.practiceResources,
                "validation_issues": package.validationIssues,
            ]
            if let revision = package.revision {
                payload["revision"] = [
                    "sha256": revision.sha256,
                    "byte_count": revision.byteCount,
                ]
            }
            return payload
        }

        switch subcommand {
        case "catalog":
            guard format == "text" || format == "json" else {
                throw CLIError.usage("--format must be text or json.")
            }
            if format == "json" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if workspaceResearch != nil {
                    let protectedData = try encoder.encode(catalog)
                    let protectedObject = try JSONSerialization.jsonObject(with: protectedData)
                    let local = try await skills().filter { $0.origin == .triptych }
                    let data = try JSONSerialization.data(
                        withJSONObject: [
                            "protected_catalog": protectedObject,
                            "triptych_packages": local.map(packagePayload),
                        ],
                        options: [.prettyPrinted, .sortedKeys]
                    )
                    write(String(decoding: data, as: UTF8.self) + "\n")
                } else {
                    write(String(decoding: try encoder.encode(catalog), as: UTF8.self) + "\n")
                }
            } else {
                write("Scholium protected Skill catalog (schema \(catalog.schemaVersion))\n")
                for entry in catalog.entries {
                    let modes = entry.supportedModes.map(\.rawValue).joined(separator: ", ")
                    write("\(entry.id)  \(entry.skillClass.rawValue)  \(entry.version)\n")
                    write("  \(entry.name): \(entry.description)\n")
                    write("  Modes: \(modes)\n")
                    if !entry.automaticModes.isEmpty {
                        write("  Automatic: \(entry.automaticModes.map(\.rawValue).joined(separator: ", "))\n")
                    }
                    if !entry.requiredSkillIDs.isEmpty {
                        write("  Requires: \(entry.requiredSkillIDs.joined(separator: ", "))\n")
                    }
                    if !entry.compatiblePracticeIDs.isEmpty {
                        write("  Compatible Practices: \(entry.compatiblePracticeIDs.joined(separator: ", "))\n")
                    }
                }
                if workspaceResearch != nil {
                    let local = try await skills().filter { $0.origin == .triptych }
                    if !local.isEmpty {
                        write("\nTriptych-local Researcher Skills\n")
                        for package in local {
                            write("\(package.id)  researcher  \(package.revision?.sha256 ?? "invalid")\n")
                            write("  \(package.name): \(package.description)\n")
                        }
                    }
                }
            }

        case "show":
            guard arguments.count >= 2 else {
                throw CLIError.usage(
                    "Usage: scholium skills show <skill-id> [--triptych <selector>] [--resource <path>] [--format text|json]"
                )
            }
            let skillID = arguments[1]
            let resourcePath = option("--resource", in: arguments) ?? "SKILL.md"
            let package: ResearchSkillPackage
            let source: String
            let entry = try? catalog.entry(id: skillID)
            if let entry {
                package = try await resolvedPackage(id: entry.id)
                source = try await resource(id: entry.id, relativePath: resourcePath)
            } else {
                guard workspaceResearch != nil else {
                    throw CLIError.usage(
                        "Triptych-local Skill \(skillID) requires --triptych <selector>."
                    )
                }
                package = try await resolvedPackage(id: skillID)
                source = try await resource(id: skillID, relativePath: resourcePath)
            }
            if format == "json" {
                var metadata = packagePayload(package)
                if let entry {
                    metadata["supported_modes"] = entry.supportedModes.map(\.rawValue)
                    metadata["automatic_modes"] = entry.automaticModes.map(\.rawValue)
                    metadata["compatible_practices"] = entry.compatiblePracticeIDs
                    metadata["required_skills"] = entry.requiredSkillIDs
                    metadata["path"] = entry.resourcePath
                }
                let payload: [String: Any] = ["entry": metadata, "source": source]
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else {
                write("\(package.name) (\(package.id))\n")
                write("Class: \(package.skillClass.rawValue)\n")
                write("Origin: \(package.origin.rawValue)\n")
                write("Version: \(package.version)\n")
                if let revision = package.revision {
                    write("Revision: \(revision.sha256)\n")
                }
                if let entry {
                    write("Modes: \(entry.supportedModes.map(\.rawValue).joined(separator: ", "))\n")
                    if !entry.automaticModes.isEmpty {
                        write("Automatic: \(entry.automaticModes.map(\.rawValue).joined(separator: ", "))\n")
                    }
                    if !entry.compatiblePracticeIDs.isEmpty {
                        write("Compatible Practices: \(entry.compatiblePracticeIDs.joined(separator: ", "))\n")
                    }
                }
                write("\n")
                write(source)
                if !source.hasSuffix("\n") { write("\n") }
            }

        case "resources":
            guard arguments.count >= 2 else {
                throw CLIError.usage(
                    "Usage: scholium skills resources <skill-id> [--triptych <selector>] [--format text|json]"
                )
            }
            let skillID = arguments[1]
            let resources: [String]
            let revision: DocumentFingerprint?
            if (try? catalog.entry(id: skillID)) != nil {
                resources = try await resourcePaths(id: skillID)
                revision = try await resolvedPackage(id: skillID).revision
            } else {
                guard workspaceResearch != nil else {
                    throw CLIError.usage(
                        "Triptych-local Skill \(skillID) requires --triptych <selector>."
                    )
                }
                resources = try await resourcePaths(id: skillID)
                revision = try await resolvedPackage(id: skillID).revision
            }
            guard format == "text" || format == "json" else {
                throw CLIError.usage("--format must be text or json.")
            }
            if format == "json" {
                let revisionPayload: Any = if let revision {
                    ["sha256": revision.sha256, "byte_count": revision.byteCount]
                } else {
                    NSNull()
                }
                let data = try JSONSerialization.data(
                    withJSONObject: [
                        "skill_id": skillID,
                        "revision": revisionPayload,
                        "resources": resources,
                    ],
                    options: [.prettyPrinted, .sortedKeys]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else {
                for resource in resources { write(resource + "\n") }
            }

        default:
            throw CLIError.usage("Unknown Skill command '\(subcommand)'.")
        }
    }

    static func runWorkflow(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium workflow <validate|assemble|audit-plan> --from <file|-> [options]"
            )
        }
        guard let input = option("--from", in: arguments) else {
            throw CLIError.usage("Workflow commands require --from <file|->.")
        }
        let data = try inputData(from: input)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        switch subcommand {
        case "validate", "assemble":
            let contract: ResearchWorkflowContract
            do {
                contract = try decoder.decode(ResearchWorkflowContract.self, from: data)
            } catch {
                throw CLIError.usage(
                    "Workflow input must be a valid ResearchWorkflowContract JSON document. \(error.localizedDescription)"
                )
            }
            let assignment = try await workflowTriptych(
                for: contract,
                triptychSelector: option("--triptych", in: arguments),
                context: context
            )
            let envelope: ResolvedResearchWorkflowEnvelope
            if let assignment {
                let handle = try await context.handle(for: assignment)
                envelope = try await handle.research.resolveWorkflow(contract)
            } else {
                envelope = try await context.runtime.researchGuidance.resolveWorkflow(contract)
            }

            if subcommand == "validate" {
                guard (option("--format", in: arguments) ?? "json") == "json" else {
                    throw CLIError.usage("scholium workflow validate supports only --format json.")
                }
                let report = WorkflowValidationReport(envelope: envelope)
                write(String(decoding: try encoder.encode(report), as: UTF8.self) + "\n")
                return
            }

            let format = option("--format", in: arguments) ?? "markdown"
            switch format {
            case "markdown":
                write(envelope.renderedInstructions)
                if !envelope.renderedInstructions.hasSuffix("\n") { write("\n") }
            case "json":
                write(String(decoding: try encoder.encode(envelope), as: UTF8.self) + "\n")
            default:
                throw CLIError.usage(
                    "scholium workflow assemble --format must be markdown or json."
                )
            }

        case "audit-plan":
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("scholium workflow audit-plan supports only --format json.")
            }
            let planningInput: ResearchAuditPlanningInput
            do {
                planningInput = try decoder.decode(ResearchAuditPlanningInput.self, from: data)
            } catch {
                throw CLIError.usage(
                    "Workflow audit input must be valid ResearchAuditPlanningInput JSON. \(error.localizedDescription)"
                )
            }
            let plan = try ResearchAuditPlanner.plan(planningInput)
            write(String(decoding: try encoder.encode(plan), as: UTF8.self) + "\n")

        default:
            throw CLIError.usage("Unknown workflow command '\(subcommand)'.")
        }
    }

    private static func workflowTriptych(
        for contract: ResearchWorkflowContract,
        triptychSelector: String?,
        context: CLIContext
    ) async throws -> TriptychAssignment? {
        let catalog = try await context.runtime.researchGuidance.catalog()
        let protectedIDs = Set(catalog.entries.map(\.id))
        let requestedIDs = Set(contract.phases.flatMap { phase in
            phase.requiredSkillIDs + phase.selectedPractices.map(\.packageID)
        })
        let localPackageIDs = requestedIDs.subtracting(protectedIDs)
        let allReferences = contract.originalReadSet
            + contract.originalWriteSet
            + contract.phases.flatMap { phase in
                phase.readSet + phase.writeSet + phase.handoff.basis
                    + phase.handoff.candidateTargets
            }
        let referencesTriptych = contract.dialogueTarget != nil || allReferences.contains {
            $0.kind == .note || $0.kind == .dialogue || $0.kind == .workspaceCatalog
        }
        if triptychSelector == nil, referencesTriptych || !localPackageIDs.isEmpty {
            var reasons: [String] = []
            if referencesTriptych { reasons.append("Triptych artifacts") }
            if !localPackageIDs.isEmpty {
                reasons.append(
                    "local packages: " + localPackageIDs.sorted().joined(separator: ", ")
                )
            }
            throw CLIError.usage(
                "--triptych <selector> is required because this workflow references "
                    + reasons.joined(separator: " and ") + "."
            )
        }
        guard let triptychSelector else {
            return nil
        }
        return try await context.triptych(selector: triptychSelector)
    }

    private static func inputData(from path: String) throws -> Data {
        let data: Data
        if path == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            let url = URL(
                fileURLWithPath: (path as NSString).expandingTildeInPath,
                isDirectory: false
            )
            data = try Data(contentsOf: url)
        }
        guard !data.isEmpty else {
            throw CLIError.usage("Workflow input is empty.")
        }
        return data
    }

    static func runDiscuss(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium discuss <list|show|reply> ... [--triptych <uuid-or-unique-name>]")
        }
        let assignment = try await context.selectedTriptych(
            selector: option("--triptych", in: arguments)
        )
        let handle = try await context.handle(for: assignment)
        let research = handle.research
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        switch subcommand {
        case "list":
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Discuss list supports --format text or json.")
            }
            let entries = try await research.activeDiscussions(noteID: nil)
            if format == "json" {
                write(String(decoding: try encoder.encode(entries), as: UTF8.self) + "\n")
            } else if entries.isEmpty {
                write("No active Discussions.\n")
            } else {
                for entry in entries {
                    let noteNames = entry.participatingNotes.map(\.title).joined(separator: ", ")
                    write("\(entry.id.uuidString)  \(entry.createdAt.formatted(.iso8601))\n")
                    write("  Notes: \(noteNames)\n")
                    write("  Latest: \(entry.statements.last?.text ?? "")\n")
                }
            }
        case "show":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage("Usage: scholium discuss show <discussion-id> [--format json]")
            }
            let entry = try await research.activeDiscussion(id: id)
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Discuss show supports --format text or json.")
            }
            if format == "json" {
                write(String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n")
            } else {
                write("Discussion: \(entry.id.uuidString)\n")
                write("Notes: \(entry.participatingNotes.map(\.title).joined(separator: ", "))\n\n")
                for statement in entry.statements {
                    write("- \(statement.attribution): \(statement.text)\n")
                }
            }
        case "reply":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage("Usage: scholium discuss reply <discussion-id> --agent <name> (--text <reply> | --from <file|->)")
            }
            let agentName = option("--agent", in: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let agentName, !agentName.isEmpty else {
                throw CLIError.usage("Discuss replies require --agent <name>.")
            }
            let replyText: String
            if let text = option("--text", in: arguments) {
                replyText = text
            } else if let file = option("--from", in: arguments) {
                let data = file == "-"
                    ? FileHandle.standardInput.readDataToEndOfFile()
                    : try Data(contentsOf: URL(
                        fileURLWithPath: (file as NSString).expandingTildeInPath
                    ))
                guard let decoded = String(data: data, encoding: .utf8) else {
                    throw CLIError.invalidUTF8(file)
                }
                replyText = decoded
            } else {
                throw CLIError.usage("Discuss replies require --text <reply> or --from <file|->.")
            }
            guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Discuss reply text cannot be empty.")
            }
            let updated = try await research.appendDiscussionStatement(
                discussionID: id,
                author: .agent,
                attribution: agentName,
                text: replyText
            )
            guard let reply = updated.statements.last, reply.author == .agent else {
                throw CLIError.unavailable("The Discuss reply was not available after persistence.")
            }
            write("Recorded reply \(reply.id.uuidString) for Discussion \(id.uuidString).\n")
        default:
            throw CLIError.usage("Unknown Discuss command '\(subcommand)'.")
        }
    }

    private static func tracePaths(
        from source: VaultQualifiedNoteID,
        to target: VaultQualifiedNoteID,
        snapshot: GraphSnapshot,
        maximumDepth: Int
    ) -> [[LinkGraphEdge]] {
        var results: [[LinkGraphEdge]] = []
        var queue: [(VaultQualifiedNoteID, [LinkGraphEdge], Set<VaultQualifiedNoteID>)] = [(source, [], [source])]
        while !queue.isEmpty {
            let (current, path, visited) = queue.removeFirst()
            guard path.count < maximumDepth else { continue }
            for edge in snapshot.outgoing[current] ?? [] {
                guard let next = edge.destination?.note, !visited.contains(next) else { continue }
                let nextPath = path + [edge]
                if next == target {
                    results.append(nextPath)
                } else {
                    queue.append((next, nextPath, visited.union([next])))
                }
            }
        }
        return results.sorted {
            if $0.count != $1.count { return $0.count < $1.count }
            return ($0.first?.source.relativePath ?? "") < ($1.first?.source.relativePath ?? "")
        }
    }

    private static func relationshipTracePaths(
        from source: VaultQualifiedNoteID,
        to target: VaultQualifiedNoteID,
        snapshot: GraphSnapshot,
        maximumDepth: Int
    ) -> [RelationshipTrace] {
        var results: [RelationshipTrace] = []
        var queue: [(VaultQualifiedNoteID, [RelationshipEdge], Set<VaultQualifiedNoteID>)] = [
            (source, [], [source]),
        ]
        while !queue.isEmpty {
            let (current, path, visited) = queue.removeFirst()
            if current == target, !path.isEmpty {
                results.append(RelationshipTrace(edges: path))
                continue
            }
            guard path.count < maximumDepth else { continue }
            let next = snapshot.relationships.compactMap { edge -> (VaultQualifiedNoteID, RelationshipEdge)? in
                guard case .resolved = edge.resolution else { return nil }
                if edge.subjectNote == current, let destination = edge.objectNote { return (destination, edge) }
                if !edge.isDirectional, edge.objectNote == current, let destination = edge.subjectNote {
                    return (destination, edge)
                }
                return nil
            }.sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            for (destination, edge) in next where !visited.contains(destination) {
                queue.append((destination, path + [edge], visited.union([destination])))
            }
        }
        return results.sorted {
            if $0.edges.count != $1.edges.count { return $0.edges.count < $1.edges.count }
            return ($0.edges.first?.id.uuidString ?? "") < ($1.edges.first?.id.uuidString ?? "")
        }
    }

}
