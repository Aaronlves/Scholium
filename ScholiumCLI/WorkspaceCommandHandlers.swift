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
            if triptychs.isEmpty {
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
            throw CLIError.usage("Usage: scholium search <query> (--vault <selector> | --workspace) [filters]")
        }
        let query: String
        let assignment: TriptychAssignment
        let scope: SearchScope
        if let selector = option("--vault", in: arguments) {
            query = first
            let vault = try await context.resolveVault(selector)
            assignment = try await context.triptych(containing: [vault.id])
            scope = .currentVault(vault.id)
        } else if arguments.contains("--workspace") {
            query = first
            assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            scope = .workspace
        } else if arguments.count >= 2, !arguments[0].hasPrefix("-") {
            // One-release compatibility alias: scholium search <vault> <query>
            let vault = try await context.resolveVault(arguments[0])
            assignment = try await context.triptych(containing: [vault.id])
            scope = .currentVault(vault.id)
            query = arguments[1]
        } else {
            throw CLIError.usage("Choose --vault <selector> or --workspace.")
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw CLIError.usage("Search query cannot be empty.") }
        let limit = Int(option("--limit", in: arguments) ?? "20") ?? 20
        let handle = try await context.handle(for: assignment)
        let hits = try await handle.discovery.search(
            SearchQuery(trimmedQuery),
            scope: scope,
            limit: limit
        )
        let format = option("--format", in: arguments) ?? "text"
        switch format {
        case "jsonl":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            for hit in hits { write(String(decoding: try encoder.encode(hit), as: UTF8.self) + "\n") }
        case "text":
            if hits.isEmpty { write("No matches.\n") }
            for hit in hits {
                write("\(hit.vaultName):\(hit.relativePath):\(hit.sourceLine)  [retrieval_lead]\n  \(hit.snippet)\n")
            }
        default:
            throw CLIError.usage("--format must be text or jsonl.")
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
        let maximumDepth = max(1, min(Int(option("--max-depth", in: arguments) ?? "3") ?? 3, 10))
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
                "Usage: scholium skills <catalog|show|resources|assemble> [options]"
            )
        }
        let workspaceResearch: (any ResearchUseCases)?
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

        func instructionAssembly(
            mode: ResearchSkillMode,
            requestedSkillIDs: [String] = [],
            mixedPhases: [ResearchSkillAssemblyPhase] = []
        ) async throws -> String {
            if let workspaceResearch {
                return try await workspaceResearch.skillInstructionAssembly(
                    mode: mode,
                    requestedSkillIDs: requestedSkillIDs,
                    mixedPhases: mixedPhases
                )
            }
            return try await context.runtime.researchGuidance.instructionAssembly(
                mode: mode,
                requestedSkillIDs: requestedSkillIDs,
                mixedPhases: mixedPhases
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

        case "assemble":
            let modeValue = option("--mode", in: arguments) ?? "dialogue"
            guard let mode = ResearchSkillMode(rawValue: modeValue) else {
                throw CLIError.usage("Unknown Skill mode '\(modeValue)'.")
            }
            let skillIDs = allOptions("--skill", in: arguments)

            if mode == .mixed {
                let phaseValues = allOptions("--phase", in: arguments)
                guard !phaseValues.isEmpty else {
                    throw CLIError.usage(
                        "Mixed mode requires --phase <mode>[:skill-id,skill-id] at least once."
                    )
                }
                let phases = try phaseValues.map { value -> ResearchSkillAssemblyPhase in
                    let pieces = value.split(separator: ":", maxSplits: 1).map(String.init)
                    guard let phaseMode = ResearchSkillMode(rawValue: pieces[0]),
                          phaseMode != .mixed else {
                        throw CLIError.usage("Invalid Mixed phase: \(value)")
                    }
                    let phaseSkills = pieces.count == 2
                        ? pieces[1].split(separator: ",").map(String.init)
                        : []
                    return ResearchSkillAssemblyPhase(mode: phaseMode, skillIDs: phaseSkills)
                }
                let assembly = try await instructionAssembly(
                    mode: .mixed,
                    mixedPhases: phases
                )
                write(assembly + (assembly.hasSuffix("\n") ? "" : "\n"))
            } else {
                let assembly = try await instructionAssembly(
                    mode: mode,
                    requestedSkillIDs: skillIDs
                )
                write(assembly + (assembly.hasSuffix("\n") ? "" : "\n"))
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

    static func runDialogue(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium dialogue <list|show|reply> ... [--triptych <uuid-or-unique-name>]")
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
            let entries: [DialogueEntry]
            if let target = option("--note", in: arguments) {
                let (vault, relativePath) = try await context.resolveTarget(
                    target,
                    within: assignment
                )
                let matching = try await research.dialogueEntries().filter { entry in
                    entry.selectedNotes.contains {
                        $0.vaultID == vault.id && $0.relativePath == relativePath
                    }
                }
                entries = matching
            } else {
                entries = try await research.dialogueEntries()
            }
            if option("--format", in: arguments) == "json" {
                write(String(decoding: try encoder.encode(entries), as: UTF8.self) + "\n")
            } else if entries.isEmpty {
                write("No Dialogue entries.\n")
            } else {
                for entry in entries {
                    let noteNames = entry.selectedNotes.map(\.title).joined(separator: ", ")
                    write("\(entry.id.uuidString)  \(entry.createdAt.formatted(.iso8601))\n")
                    write("  Notes: \(noteNames)\n")
                    write("  Instruction: \(entry.instruction)\n")
                }
            }
        case "show":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage("Usage: scholium dialogue show <dialogue-id> [--format json]")
            }
            let entry = try await research.dialogue(id: id)
            if option("--format", in: arguments) == "json" {
                write(String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n")
            } else {
                write("Dialogue: \(entry.id.uuidString)\n")
                write("Instruction: \(entry.instruction)\n")
                write("Checkpoint: \(entry.checkpointID.uuidString)\n\n")
                if let contract = entry.responseContract {
                    write("Response contract: request-snapshot\n")
                    write("  Base: \(contract.base)\n")
                    write("  Modules: \(contract.modules.isEmpty ? "None selected" : contract.modules.joined(separator: ", "))\n")
                    write("  Comment preservation: \(contract.commentPreservation)\n")
                    if !contract.validationIssues.isEmpty {
                        write("  Contract issues: \(contract.validationIssues.joined(separator: " "))\n")
                    }
                } else {
                    write("Response contract: legacy-default (request-time selection unavailable)\n")
                }
                if !entry.generatedPrompt.isEmpty {
                    write("Legacy copied prompt:\n")
                    write(entry.generatedPrompt + "\n")
                }
                if !entry.chronologicalTurns.isEmpty {
                    write("\nFollow-up exchange:\n")
                    for turn in entry.chronologicalTurns {
                        switch turn {
                        case .researcher(let comment):
                            write("- Researcher: \(comment.text)\n")
                        case .agent(let reply):
                            write("- \(reply.agentName): \(reply.text)\n")
                        }
                    }
                }
            }
        case "reply":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage("Usage: scholium dialogue reply <dialogue-id> --agent <name> (--text <reply> | --from <file>) [--note <vault>:<path>] [--comment <uuid>]")
            }
            let agentName = option("--agent", in: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let agentName, !agentName.isEmpty else {
                throw CLIError.usage("Dialogue replies require --agent <name>.")
            }
            let replyText: String
            if let text = option("--text", in: arguments) {
                replyText = text
            } else if let file = option("--from", in: arguments) {
                let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
                guard let decoded = String(data: try Data(contentsOf: url), encoding: .utf8) else {
                    throw CLIError.invalidUTF8(file)
                }
                replyText = decoded
            } else {
                throw CLIError.usage("Dialogue replies require --text <reply> or --from <file>.")
            }
            let entry = try await research.dialogue(id: id)
            let noteID: UUID?
            if let target = option("--note", in: arguments) {
                let (vault, relativePath) = try await context.resolveTarget(
                    target,
                    within: assignment
                )
                noteID = entry.selectedNotes.first {
                    $0.vaultID == vault.id && $0.relativePath == relativePath
                }?.noteID
                guard noteID != nil else { throw DialogueError.invalidReplyTarget }
            } else {
                noteID = nil
            }
            let commentID = option("--comment", in: arguments).flatMap(UUID.init(uuidString:))
            if option("--comment", in: arguments) != nil, commentID == nil {
                throw CLIError.usage("--comment requires a valid UUID.")
            }
            let updated = try await research.appendDialogueReply(
                DialogueReply(
                    agentName: agentName,
                    text: replyText,
                    noteID: noteID,
                    commentID: commentID
                ),
                to: id
            )
            guard let reply = updated.replies.last else {
                throw CLIError.unavailable("The Dialogue reply was not available after persistence.")
            }
            write("Recorded reply \(reply.id.uuidString) for Dialogue \(id.uuidString).\n")
        default:
            throw CLIError.usage("Unknown Dialogue command '\(subcommand)'.")
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
