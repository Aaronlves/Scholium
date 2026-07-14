import Darwin
import Foundation
import ScholiumCore

@main
struct ScholiumCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeError("scholium: \(error.localizedDescription)\n")
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        let home = ScholiumPaths.cliHomeURL()
        let workspaceURL = try ScholiumPaths.workspaceRegistryURL()
        let registry = WorkspaceRegistry(storageURL: workspaceURL)

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "vault":
            try await runVault(Array(arguments.dropFirst()), registry: registry)
        case "search":
            try await runSearch(Array(arguments.dropFirst()), home: home, registry: registry)
        case "links":
            try await runLinks(Array(arguments.dropFirst()), home: home, registry: registry)
        case "graph":
            try await runGraph(Array(arguments.dropFirst()), home: home, registry: registry)
        case "workspace":
            try await runWorkspace(Array(arguments.dropFirst()), home: home, registry: registry)
        case "read":
            try await runRead(Array(arguments.dropFirst()), home: home, registry: registry)
        case "note":
            try await runNote(Array(arguments.dropFirst()), home: home, registry: registry)
        case "dialogue":
            try await runDialogue(Array(arguments.dropFirst()), home: home, registry: registry)
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run 'scholium help'.")
        }
    }

    private static func runVault(_ arguments: [String], registry: WorkspaceRegistry) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium vault list")
        }
        switch subcommand {
        case "list":
            let triptychs = await registry.allTriptychs()
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

    private static func runSearch(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard let first = arguments.first else {
            throw CLIError.usage("Usage: scholium search <query> (--vault <selector> | --workspace) [filters]")
        }
        let query: String
        let vaults: [RegisteredVault]
        if let selector = option("--vault", in: arguments) {
            query = first
            let vault = try await registry.resolve(selector)
            _ = try await triptych(containing: [vault.id], registry: registry)
            vaults = [vault]
        } else if arguments.contains("--workspace") {
            query = first
            let assignment = try await selectedTriptych(
                registry: registry,
                selector: option("--triptych", in: arguments)
            )
            vaults = WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
        } else if arguments.count >= 2, !arguments[0].hasPrefix("-") {
            // One-release compatibility alias: scholium search <vault> <query>
            let vault = try await registry.resolve(arguments[0])
            _ = try await triptych(containing: [vault.id], registry: registry)
            vaults = [vault]
            query = arguments[1]
        } else {
            throw CLIError.usage("Choose --vault <selector> or --workspace.")
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw CLIError.usage("Search query cannot be empty.") }
        let limit = Int(option("--limit", in: arguments) ?? "20") ?? 20
        let support = try searchApplicationSupportURL(home: home)
        var indexes: [(vault: RegisteredVault, index: SQLiteSearchIndex)] = []
        for vault in vaults {
            indexes.append((vault, try await synchronizedSearchIndex(for: vault, home: home, applicationSupportURL: support)))
        }
        let hits = try await FederatedSearchEngine.search(
            SearchQuery(trimmedQuery),
            indexes: indexes,
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

    private static func runLinks(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
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
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let assignment = try await triptych(containing: [vault.id], registry: registry)
            let snapshot = try await workspaceLinkSnapshot(for: assignment, home: home)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let edges = subcommand == "incoming" ? (snapshot.incoming[id] ?? []) : (snapshot.outgoing[id] ?? [])
            write(String(decoding: try encoder.encode(edges), as: UTF8.self) + "\n")
        case "relationships":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: scholium links relationships <vault>:<path> --format json")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let assignment = try await triptych(containing: [vault.id], registry: registry)
            let snapshot = try await workspaceLinkSnapshot(for: assignment, home: home)
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
            let assignment = try await selectedTriptych(
                registry: registry,
                selector: option("--triptych", in: arguments)
            )
            let diagnostics = try await workspaceLinkSnapshot(for: assignment, home: home).diagnostics
            write(String(decoding: try encoder.encode(diagnostics), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("Unknown links command '\(subcommand)'.")
        }
    }

    private static func runGraph(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard ["trace", "relation-trace"].contains(arguments.first ?? ""), arguments.count >= 3 else {
            throw CLIError.usage("Usage: scholium graph <trace|relation-trace> <source> <target> --max-depth 3 --format json")
        }
        let (sourceVault, sourcePath) = try await resolveTarget(arguments[1], registry: registry)
        let (targetVault, targetPath) = try await resolveTarget(arguments[2], registry: registry)
        let assignment = try await triptych(containing: [sourceVault.id, targetVault.id], registry: registry)
        let maximumDepth = max(1, min(Int(option("--max-depth", in: arguments) ?? "3") ?? 3, 10))
        let snapshot = try await workspaceLinkSnapshot(for: assignment, home: home)
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

    private static func runWorkspace(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium workspace <catalog|attention>")
        }
        let assignment = try await selectedTriptych(
            registry: registry,
            selector: option("--triptych", in: arguments)
        )
        let vaults = WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
        var documents: [UUID: [NoteDocument]] = [:]
        for vault in vaults {
            let loaded = try await markdownDocuments(in: vault, repository: repository(for: vault, home: home))
            documents[vault.id] = loaded
        }
        let workspaceGraph = workspaceLinkSnapshot(vaults: vaults, documents: documents)
        var reviewStates: [String: WorkspaceReviewState] = [:]
        let reviews = try await humanReviewStore(
            home: home,
            registry: registry,
            triptychSelector: assignment.workspace.id.uuidString
        )
        if let health = await reviews.healthError() { throw CLIError.unavailable(health) }
        for record in await reviews.allRecords() {
            guard let latest = record.latestReview else { continue }
            let document = documents[record.vaultID]?.first { $0.relativePath == record.relativePath }
            reviewStates["\(record.vaultID.uuidString):\(record.relativePath)"] = WorkspaceReviewState(
                qualification: latest.qualification.rawValue,
                reviewedFingerprint: latest.fingerprint,
                changedSinceReview: document.map { $0.fingerprint != latest.fingerprint } ?? true
            )
        }
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: vaults,
            documents: documents,
            reviewStates: reviewStates,
            graph: workspaceGraph
        )
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

    private static func runRead(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard let specification = arguments.first else {
            throw CLIError.usage("Usage: scholium read <vault>:<relative-path>")
        }
        let (vault, relativePath) = try await resolveTarget(specification, registry: registry)
        let document = try await repository(for: vault, home: home).load(relativePath: relativePath)
        if option("--format", in: arguments) == "json" {
            let payload: [String: String] = [
                "vault_id": vault.id.uuidString,
                "vault_name": vault.name,
                "relative_path": relativePath,
                "sha256": document.fingerprint.sha256,
                "content": document.rawContent,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            write(String(decoding: data, as: UTF8.self) + "\n")
            return
        }
        write(document.rawContent)
        if !document.rawContent.hasSuffix("\n") { write("\n") }
    }

    private static func runNote(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium note <create|replace|move|set-aside|trash|delete> ...")
        }
        switch subcommand {
        case "create":
            guard arguments.count >= 2, let input = option("--from", in: arguments) else {
                throw CLIError.usage("Usage: scholium note create <vault>:<path> --from <markdown-file>")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let content = try sourceContent(from: input)
            let document = try await repository(for: vault, home: home).create(relativePath: path, content: content)
            write("Created \(vault.name):\(path)\nSHA-256: \(document.fingerprint.sha256)\n")
        case "replace":
            guard arguments.count >= 2,
                  let input = option("--from", in: arguments),
                  let expected = option("--expected", in: arguments) else {
                throw CLIError.usage("Usage: scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let repository = try repository(for: vault, home: home)
            let current = try await repository.load(relativePath: path)
            try requireExpected(expected, current: current.fingerprint)
            let result = try await repository.save(
                relativePath: path,
                changeSet: .exactContent(try sourceContent(from: input)),
                expectedRevision: current.fingerprint
            )
            write("Replaced \(vault.name):\(path)\nSHA-256: \(result.document.fingerprint.sha256)\n")
        case "move":
            guard arguments.count >= 3, let expected = option("--expected", in: arguments) else {
                throw CLIError.usage("Usage: scholium note move <vault>:<path> <new-relative-path> --expected <sha256>")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let repository = try repository(for: vault, home: home)
            let current = try await repository.load(relativePath: path)
            try requireExpected(expected, current: current.fingerprint)
            let result = try await repository.move(
                relativePath: path,
                to: arguments[2],
                expectedRevision: current.fingerprint
            )
            write("Moved \(vault.name):\(path) -> \(result.relativePath)\n")
        case "set-aside", "trash":
            guard arguments.count >= 2, let expected = option("--expected", in: arguments) else {
                throw CLIError.usage("Usage: scholium note \(subcommand) <vault>:<path> --expected <sha256>")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            let repository = try repository(for: vault, home: home)
            let current = try await repository.load(relativePath: path)
            try requireExpected(expected, current: current.fingerprint)
            let result = subcommand == "set-aside"
                ? try await repository.setAside(relativePath: path, expectedRevision: current.fingerprint)
                : try await repository.moveToTrash(relativePath: path, expectedRevision: current.fingerprint)
            write("Moved \(vault.name):\(path) -> \(result.relativePath)\n")
        case "delete":
            guard arguments.count >= 2,
                  arguments.contains("--permanent"),
                  let expected = option("--expected", in: arguments) else {
                throw CLIError.usage("Usage: scholium note delete <vault>:<Trash/path.md> --permanent --expected <sha256>")
            }
            let (vault, path) = try await resolveTarget(arguments[1], registry: registry)
            guard path.hasPrefix("Trash/") else {
                throw CLIError.usage("Permanent deletion is allowed only for a note already in Trash.")
            }
            let repository = try repository(for: vault, home: home)
            let current = try await repository.load(relativePath: path)
            try requireExpected(expected, current: current.fingerprint)
            _ = try await repository.deletePermanently(relativePath: path, expectedRevision: current.fingerprint)
            write("Permanently deleted \(vault.name):\(path). Recovery history was retained.\n")
        default:
            throw CLIError.usage("Unknown note command '\(subcommand)'.")
        }
    }

    private static func sourceContent(from path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let content = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw CLIError.invalidUTF8(path)
        }
        return content
    }

    private static func requireExpected(
        _ expectedSHA256: String,
        current: DocumentFingerprint
    ) throws {
        guard expectedSHA256.lowercased() == current.sha256.lowercased() else {
            throw CLIError.usage("Revision mismatch. Re-read the note and use its current SHA-256 fingerprint.")
        }
    }

    private static func runDialogue(
        _ arguments: [String],
        home: URL,
        registry: WorkspaceRegistry
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: scholium dialogue <list|show|reply> ... [--triptych <uuid-or-unique-name>]")
        }
        let context = try await dialogueStore(
            home: home,
            registry: registry,
            triptychSelector: option("--triptych", in: arguments)
        )
        let store = context.store
        if let health = await store.healthError() { throw CLIError.unavailable(health) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        switch subcommand {
        case "list":
            let entries: [DialogueEntry]
            if let target = option("--note", in: arguments) {
                let (vault, relativePath) = try await resolveTarget(
                    target,
                    registry: registry,
                    within: context.assignment
                )
                let matching = await store.allEntries().filter { entry in
                    entry.selectedNotes.contains {
                        $0.vaultID == vault.id && $0.relativePath == relativePath
                    }
                }
                entries = matching
            } else {
                entries = await store.allEntries()
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
            let entry = try await store.entry(id: id)
            if option("--format", in: arguments) == "json" {
                write(String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n")
            } else {
                write("Dialogue: \(entry.id.uuidString)\n")
                write("Instruction: \(entry.instruction)\n")
                write("Checkpoint: \(entry.checkpointID.uuidString)\n\n")
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
            let entry = try await store.entry(id: id)
            let noteID: UUID?
            if let target = option("--note", in: arguments) {
                let (vault, relativePath) = try await resolveTarget(
                    target,
                    registry: registry,
                    within: context.assignment
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
            let updated = try await store.appendReply(
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

    private static func searchApplicationSupportURL(home: URL) throws -> URL {
        if ProcessInfo.processInfo.environment["SCHOLIUM_HOME"] != nil {
            return home.appendingPathComponent("ApplicationSupport", isDirectory: true)
        }
        return try ScholiumPaths.sharedApplicationSupportURL()
    }

    private static func synchronizedSearchIndex(
        for vault: RegisteredVault,
        home: URL,
        applicationSupportURL: URL
    ) async throws -> SQLiteSearchIndex {
        let repository = try repository(for: vault, home: home)
        let documents = try await markdownDocuments(in: vault, repository: repository)
        let url = SQLiteSearchIndex.databaseURL(applicationSupportURL: applicationSupportURL, vaultID: vault.id)
        let opened = try SQLiteSearchIndex.openRecovering(databaseURL: url, vaultID: vault.id)
        let index = opened.index
        let fingerprints = Dictionary(uniqueKeysWithValues: documents.map {
            ($0.relativePath, $0.fingerprint)
        })
        if !opened.recoveredCorruption,
           try await index.matches(
               fingerprints: fingerprints,
               vaultName: vault.name,
               vaultRole: vault.role
           ) {
            return index
        }

        let semantics = Dictionary(uniqueKeysWithValues: documents.map { document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let catalog = documents.map { document in
            LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[
                VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            ])
        }
        let graph = LinkGraphBuilder.build(generation: 1, catalog: catalog, documents: semantics)
        let brokenPaths = Set(graph.diagnostics.filter { $0.code == .broken }.map { $0.source.relativePath })
        let indexed = documents.map { document in
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: document,
                semantic: semantics[VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)],
                hasBrokenLink: brokenPaths.contains(document.relativePath)
            )
        }
        _ = try await index.synchronize(
            indexed,
            vaultName: vault.name,
            vaultRole: vault.role,
            recoveredCorruption: opened.recoveredCorruption
        )
        return index
    }

    private static func workspaceLinkSnapshot(
        for assignment: TriptychAssignment,
        home: URL
    ) async throws -> GraphSnapshot {
        let vaults = WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
        guard vaults.count == WorkspaceVaultSlot.allCases.count else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        var documents: [UUID: [NoteDocument]] = [:]
        for vault in vaults {
            documents[vault.id] = try await markdownDocuments(
                in: vault,
                repository: repository(for: vault, home: home)
            )
        }
        return workspaceLinkSnapshot(vaults: vaults, documents: documents)
    }

    private static func workspaceLinkSnapshot(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]]
    ) -> GraphSnapshot {
        let semantics = Dictionary(uniqueKeysWithValues: vaults.flatMap { vault in
            documents[vault.id, default: []].map { document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return (id, MarkdownSemanticDocument(parsing: document))
            }
        })
        let catalog = vaults.flatMap { vault in
            documents[vault.id, default: []].map { document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[id])
            }
        }
        return LinkGraphBuilder.build(
            generation: 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace
        )
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

    private struct DialogueStoreContext {
        let assignment: TriptychAssignment
        let store: DialogueStore
    }

    private static func dialogueStore(
        home: URL,
        registry: WorkspaceRegistry,
        triptychSelector: String? = nil
    ) async throws -> DialogueStoreContext {
        let assignment: TriptychAssignment?
        if let triptychSelector {
            assignment = try await registry.resolveTriptych(triptychSelector)
        } else {
            assignment = await registry.threeVaultWorkspace()
        }
        guard let assignment,
              let works = assignment.vault(for: .output) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let control = TriptychControlStore(
            worksVaultURL: URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        )
        let manifest = try await control.manifest()
        let support: URL
        if ProcessInfo.processInfo.environment["SCHOLIUM_HOME"] != nil {
            support = home
        } else {
            support = try ScholiumPaths.sharedApplicationSupportURL()
        }
        return DialogueStoreContext(assignment: assignment, store: DialogueStore(storageURL: support
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
            .appendingPathComponent("dialogue", isDirectory: true)))
    }

    private static func humanReviewStore(
        home: URL,
        registry: WorkspaceRegistry,
        triptychSelector: String? = nil
    ) async throws -> HumanReviewStore {
        let assignment = try await selectedTriptych(registry: registry, selector: triptychSelector)
        guard let works = assignment.vault(for: .output) else { throw WorkspaceRegistryError.incompleteWorkspace }
        let control = TriptychControlStore(
            worksVaultURL: URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        )
        let manifest = try await control.manifest()
        let support = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"] != nil
            ? home
            : try ScholiumPaths.sharedApplicationSupportURL()
        return HumanReviewStore(storageURL: support
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
            .appendingPathComponent("human-review", isDirectory: true))
    }

    private static func selectedTriptych(
        registry: WorkspaceRegistry,
        selector: String?
    ) async throws -> TriptychAssignment {
        if let selector {
            return try await registry.resolveTriptych(selector)
        }
        guard let assignment = await registry.threeVaultWorkspace() else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return assignment
    }

    private static func triptych(
        containing requiredVaultIDs: Set<UUID>,
        registry: WorkspaceRegistry
    ) async throws -> TriptychAssignment {
        let matches = await registry.allTriptychs().filter { assignment in
            let assigned = Set(assignment.vaults.values.map(\.id))
            return requiredVaultIDs.isSubset(of: assigned)
        }
        guard !matches.isEmpty else {
            throw CLIError.usage("The selected vaults do not belong to one registered Scholium Triptych.")
        }
        guard matches.count == 1 else {
            throw CLIError.usage("The selected vaults belong to more than one registered Triptych; specify unique vault paths or IDs.")
        }
        return matches[0]
    }

    private static func resolveTarget(
        _ specification: String,
        registry: WorkspaceRegistry,
        within triptych: TriptychAssignment? = nil
    ) async throws -> (RegisteredVault, String) {
        guard let separator = specification.firstIndex(of: ":") else {
            throw CLIError.usage("Target must use <vault>:<relative-path> syntax.")
        }
        let selector = String(specification[..<separator])
        let relativePath = String(specification[specification.index(after: separator)...])
        guard !selector.isEmpty, !relativePath.isEmpty else {
            throw CLIError.usage("Target must use <vault>:<relative-path> syntax.")
        }
        if let triptych {
            let standardizedPath = URL(fileURLWithPath: (selector as NSString).expandingTildeInPath)
                .resolvingSymlinksInPath().standardizedFileURL.path
            let matches = triptych.vaults.values.filter { vault in
                vault.id.uuidString.caseInsensitiveCompare(selector) == .orderedSame
                    || vault.name.caseInsensitiveCompare(selector) == .orderedSame
                    || vault.canonicalPath == standardizedPath
            }
            guard let vault = matches.first else {
                throw WorkspaceRegistryError.vaultNotFound(selector)
            }
            guard matches.count == 1 else {
                throw WorkspaceRegistryError.ambiguousSelector(selector)
            }
            return (vault, relativePath)
        }
        let vault = try await registry.resolve(selector)
        _ = try await Self.triptych(containing: [vault.id], registry: registry)
        return (vault, relativePath)
    }

    private static func repository(for vault: RegisteredVault, home: URL) throws -> VaultRepository {
        let identity = VaultIdentity(id: vault.id, canonicalPath: vault.canonicalPath, bookmarkData: nil)
        return try VaultRepository(
            vaultURL: URL(fileURLWithPath: vault.canonicalPath, isDirectory: true),
            identity: identity,
            applicationSupportURL: home.appendingPathComponent("repository", isDirectory: true)
        )
    }

    private static func markdownDocuments(
        in vault: RegisteredVault,
        repository: VaultRepository
    ) async throws -> [NoteDocument] {
        let root = canonicalFileSystemURL(vault.canonicalPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var paths: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            paths.append(String(url.path.dropFirst(root.path.count + 1)))
        }
        var documents: [NoteDocument] = []
        for path in paths.sorted() {
            documents.append(try await repository.load(relativePath: path))
        }
        return documents
    }

    private static func canonicalFileSystemURL(_ path: String) -> URL {
        let resolved: String? = path.withCString { pointer in
            guard let canonical = realpath(pointer, nil) else { return nil }
            defer { free(canonical) }
            return String(cString: canonical)
        }
        return URL(fileURLWithPath: resolved ?? path, isDirectory: true)
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func printHelp() {
        write("""
        Scholium CLI — agent-facing, local-first research access

        Usage:
          scholium vault list
          scholium search <query> --vault <selector> [--format text|jsonl]
          scholium search <query> --workspace [--triptych <uuid-or-unique-name>] [filters]
          scholium links incoming <vault>:<path> --format json
          scholium links outgoing <vault>:<path> --format json
          scholium links relationships <vault>:<path> --format json
          scholium links diagnostics --workspace [--triptych <uuid-or-unique-name>] --format json
          scholium graph trace <source> <target> --max-depth 3 --format json
          scholium graph relation-trace <source> <target> --max-depth 3 --format json
          scholium workspace catalog [--triptych <uuid-or-unique-name>] --format json
          scholium workspace attention [--triptych <uuid-or-unique-name>] [--kind <queue>] --format json
          scholium read <vault>:<relative-path> [--format json]
          scholium note create <vault>:<path> --from <markdown-file>
          scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>
          scholium note move <vault>:<path> <new-path> --expected <sha256>
          scholium note set-aside <vault>:<path> --expected <sha256>
          scholium note trash <vault>:<path> --expected <sha256>
          scholium note delete <vault>:<Trash/path> --permanent --expected <sha256>
          scholium dialogue list [--triptych <uuid-or-unique-name>]
              [--note <vault>:<relative-path>] [--format json]
          scholium dialogue show <dialogue-id> [--triptych <uuid-or-unique-name>] [--format json]
          scholium dialogue reply <dialogue-id> --triptych <uuid-or-unique-name> --agent <name>
              (--text <reply> | --from <file>) [--note <vault>:<path>] [--comment <uuid>]
        Omitting --triptych uses the compatibility default Triptych.
        Triptych roles: analyses, topics, works
        Legacy registry spellings and aliases remain accepted for compatibility:
        source_corpus, topic_knowledge, dissertation_control, draft_project,
        other, unclassified, sources, knowledge, dissertation, and project.

        Existing-note mutations require the exact SHA-256 reported by
        `scholium read --format json`. Fingerprints prevent stale overwrites;
        they are revision checks, not permission tokens. The researcher remains
        responsible for deciding when an agent may edit Triptych files.
        """ + "\n")
    }

    private static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    private static func writeError(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case invalidUTF8(String)
    case noteNotFound(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .invalidUTF8(let path): return "File is not valid UTF-8: \(path)"
        case .noteNotFound(let target): return "The workspace note was not found: \(target)"
        case .unavailable(let message): return message
        }
    }
}
