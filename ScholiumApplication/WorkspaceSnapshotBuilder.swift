import ScholiumContracts
import Foundation
import ScholiumCore

enum WorkspaceSnapshotBuilder {
    private struct LoadedVault: Sendable {
        let slot: WorkspaceVaultSlot
        let vault: RegisteredVault
        let rootURL: URL
        let allDocuments: [NoteDocument]
        let activeDocuments: [NoteDocument]
        let semantics: [String: MarkdownSemanticDocument]
        let identityStates: [String: WorkspaceNoteIdentityState]
        let identityRecovery: NoteIdentityRecoveryState
        let identityHealthIssues: [String]
    }

    static func build(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        services: WorkspaceServices,
        graphGeneration: Int,
        recoveredIndexIDs: Set<UUID>
    ) async throws -> WorkspaceSnapshot {
        try Task.checkCancellation()

        var loadedVaults: [LoadedVault] = []
        var semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
        var linkCatalog: [LinkCatalogNote] = []

        for slot in WorkspaceVaultSlot.allCases {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                  let repository = services.repositories[vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let rootURL = await repository.vaultURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: rootURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
            }
            let paths = try await repository.markdownRelativePaths(includeLifecycle: true)
            var allDocuments: [NoteDocument] = []
            var activeDocuments: [NoteDocument] = []
            var semantics: [String: MarkdownSemanticDocument] = [:]
            for path in paths {
                try Task.checkCancellation()
                let document = try await repository.load(relativePath: path)
                allDocuments.append(document)
                guard WorkspaceDocumentLifecycle(relativePath: path) == .active else {
                    continue
                }
                let semantic = MarkdownSemanticDocument(parsing: document)
                activeDocuments.append(document)
                semantics[path] = semantic
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
                semanticDocuments[id] = semantic
                linkCatalog.append(
                    LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantic)
                )
            }
            var identityStates = Dictionary(
                uniqueKeysWithValues: allDocuments.map {
                    ($0.relativePath, WorkspaceNoteIdentityState.unresolved)
                }
            )
            var identityHealthIssues: [String] = []
            var identityRecovery = NoteIdentityRecoveryState(
                identities: [:],
                ambiguities: [],
                pendingRebindings: [],
                failures: []
            )
            do {
                let recovery = try await services.identityRecoveryCoordinator.reconcile(
                    vaultID: vault.id,
                    documents: allDocuments.map { ($0.relativePath, $0.fingerprint) },
                    repository: repository,
                    migrateCritiquePaths: slot == .output
                )
                identityRecovery = recovery
                for (path, record) in recovery.identities {
                    identityStates[path] = .resolved(record.id)
                }
                for ambiguity in recovery.ambiguities {
                    identityStates[ambiguity.relativePath] = .ambiguous(
                        candidateIDs: ambiguity.candidates.map(\.id).sorted {
                            $0.uuidString < $1.uuidString
                        }
                    )
                }
                for pending in recovery.pendingRebindings {
                    identityStates[pending.relativePath] = .pending(pending.noteID)
                }
                identityHealthIssues.append(contentsOf: recovery.failures.map(\.message))
            } catch {
                identityHealthIssues.append(
                    "Portable note identity for \(vault.name): \(error.localizedDescription)"
                )
            }
            loadedVaults.append(
                LoadedVault(
                    slot: slot,
                    vault: vault,
                    rootURL: rootURL,
                    allDocuments: allDocuments,
                    activeDocuments: activeDocuments,
                    semantics: semantics,
                    identityStates: identityStates,
                    identityRecovery: identityRecovery,
                    identityHealthIssues: identityHealthIssues
                )
            )
        }

        let graph = LinkGraphBuilder.build(
            generation: graphGeneration,
            catalog: linkCatalog,
            documents: semanticDocuments,
            resolutionScope: .workspace
        )
        let brokenNoteIDs = Set(graph.diagnostics.compactMap { diagnostic in
            diagnostic.code == .broken ? diagnostic.source : nil
        })

        let humanReviews = await services.humanReviewStore.allRecords()
        let reviewByLocation = Dictionary(
            humanReviews.map { record in
                (VaultQualifiedNoteID(vaultID: record.vaultID, relativePath: record.relativePath), record)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var reviewStates: [String: WorkspaceReviewState] = [:]
        var indexGenerations: [UUID: IndexGeneration] = [:]

        for loaded in loadedVaults {
            try Task.checkCancellation()
            guard let index = services.indexes[loaded.vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let searchDocuments = loaded.activeDocuments.map { document in
                let id = VaultQualifiedNoteID(
                    vaultID: loaded.vault.id,
                    relativePath: document.relativePath
                )
                let review = reviewByLocation[id]
                if let latest = review?.latestReview {
                    let referenceID = "\(loaded.vault.id.uuidString):\(document.relativePath)"
                    reviewStates[referenceID] = WorkspaceReviewState(
                        qualification: latest.qualification.rawValue,
                        reviewedFingerprint: latest.fingerprint,
                        changedSinceReview: latest.fingerprint != document.fingerprint
                    )
                }
                return SearchIndexDocument(
                    vaultID: loaded.vault.id,
                    vaultName: loaded.vault.name,
                    vaultRole: loaded.vault.role,
                    document: document,
                    semantic: loaded.semantics[document.relativePath],
                    review: review?.review(for: document.fingerprint) == nil
                        ? "unreviewed"
                        : "reviewed",
                    hasBrokenLink: brokenNoteIDs.contains(id)
                )
            }
            let result = try await index.synchronize(
                searchDocuments,
                vaultName: loaded.vault.name,
                vaultRole: loaded.vault.role,
                recoveredCorruption: recoveredIndexIDs.contains(loaded.vault.id)
            )
            indexGenerations[loaded.vault.id] = result.generation
        }

        let documentsByVault = Dictionary(
            uniqueKeysWithValues: loadedVaults.map {
                ($0.vault.id, $0.activeDocuments)
            }
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: loadedVaults.map(\.vault),
            documents: documentsByVault,
            reviewStates: reviewStates,
            graph: graph
        )

        var healthIssues: [String] = []
        healthIssues.append(contentsOf: loadedVaults.flatMap(\.identityHealthIssues))
        if let issue = await services.humanReviewStore.healthError() {
            healthIssues.append(issue)
        }
        if let issue = await services.dialogueStore.healthError() {
            healthIssues.append(issue)
        }
        if let issue = await services.critiqueRegistry.healthError() {
            healthIssues.append(issue)
        }
        let recoveryRecords: [TriptychMutationRecoveryRecord]
        do {
            recoveryRecords = try await services.transactionRecoveryStore.pending()
        } catch {
            recoveryRecords = []
            healthIssues.append(
                "Durable transaction recovery: \(error.localizedDescription)"
            )
        }
        for loaded in loadedVaults {
            if let repository = services.repositories[loaded.vault.id],
               let issue = await repository.versionHistoryHealthError() {
                healthIssues.append("\(loaded.vault.name): \(issue)")
            }
        }

        var critiquesByID: [UUID: CritiqueAssociation] = [:]
        if let output = loadedVaults.first(where: { $0.slot == .output }) {
            for document in output.activeDocuments {
                if let association = await services.critiqueRegistry.association(
                    critiqueRelativePath: document.relativePath
                ) {
                    critiquesByID[association.id] = association
                }
                do {
                    if let identity = try await services.controlStore.identityRecord(
                        vaultID: output.vault.id,
                        relativePath: document.relativePath
                    ), let association = await services.critiqueRegistry.association(
                        workNoteID: identity.id
                    ) {
                        critiquesByID[association.id] = association
                    }
                } catch {
                    healthIssues.append(
                        "Portable note identity \(document.relativePath): \(error.localizedDescription)"
                    )
                }
            }
        }

        let vaultSnapshots = loadedVaults.map { loaded in
            WorkspaceVaultSnapshot(
                slot: loaded.slot,
                vault: loaded.vault,
                documents: loaded.allDocuments.map { document in
                    let id = VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: document.relativePath
                    )
                    let values = try? loaded.rootURL
                        .appendingPathComponent(document.relativePath, isDirectory: false)
                        .resourceValues(forKeys: [
                            .creationDateKey,
                            .contentModificationDateKey,
                            .fileSizeKey,
                        ])
                    let review = reviewByLocation[id]?.latestReview.map {
                        WorkspaceReviewState(
                            qualification: $0.qualification.rawValue,
                            reviewedFingerprint: $0.fingerprint,
                            changedSinceReview: $0.fingerprint != document.fingerprint
                        )
                    }
                    let diagnostics = graph.diagnostics.filter { $0.source == id }
                    return WorkspaceNoteSnapshot(
                        id: id,
                        vaultRole: loaded.vault.role,
                        stableIdentity: loaded.identityStates[document.relativePath] ?? .unresolved,
                        document: document,
                        fileMetadata: WorkspaceFileMetadata(
                            byteCount: values?.fileSize ?? document.sourceBytes.count,
                            creationDate: values?.creationDate,
                            modificationDate: values?.contentModificationDate
                        ),
                        lifecycle: WorkspaceDocumentLifecycle(
                            relativePath: document.relativePath
                        ),
                        review: review,
                        graphCounts: WorkspaceGraphCounts(
                            incoming: graph.incoming[id]?.count ?? 0,
                            outgoing: graph.outgoing[id]?.count ?? 0,
                            broken: diagnostics.count { $0.code == .broken },
                            ambiguous: diagnostics.count {
                                $0.code == .ambiguous || $0.code == .ambiguousHeading
                            }
                        )
                    )
                },
                identityRecovery: loaded.identityRecovery
            )
        }
        let allDialogueEntries = await services.dialogueStore.allEntries()
        let critiqueAssociations = critiquesByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let storedFunctionRuns = (
            allDialogueEntries.compactMap { entry in
                entry.functionSnapshot.map {
                    ResearchFunctionRecordProjection(
                        snapshot: $0,
                        completion: entry.functionCompletion,
                        preparedInstructions: entry.generatedPrompt
                    )
                }
            }
            + critiqueAssociations.flatMap { association in
                association.rounds.compactMap { round in
                    round.functionSnapshot.map {
                        ResearchFunctionRecordProjection(
                            snapshot: $0,
                            completion: round.functionCompletion,
                            preparedInstructions: round.functionInstructions
                        )
                    }
                }
            }
        ).sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let currentByStableID: [UUID: DocumentFingerprint] = Dictionary(
            vaultSnapshots.flatMap(\.documents).compactMap { note in
                guard case .resolved(let stableID) = note.stableIdentity else { return nil }
                return (stableID, note.fingerprint)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let currentByLocation: [VaultQualifiedNoteID: DocumentFingerprint] = Dictionary(
            uniqueKeysWithValues: vaultSnapshots.flatMap(\.documents).map {
                ($0.id, $0.fingerprint)
            }
        )
        let commentsByID: [UUID: ResearcherComment] = Dictionary(
            humanReviews.flatMap(\.comments).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let functionRuns = storedFunctionRuns.map { run in
            guard let completion = run.completion,
                  completion.state != .cancelled,
                  completion.state != .stale else { return run }
            let targetIsCurrent = currentByStableID[run.snapshot.request.target.noteID]
                == completion.targetFingerprint
            let materialsAreCurrent = run.snapshot.request.materials.allSatisfy { material in
                currentByStableID[material.noteID]
                    == completion.materialFingerprints[material.noteID]
            }
            let outputIsCurrent: Bool
            if let preparedOutput = run.snapshot.preparedOutput {
                outputIsCurrent = currentByLocation[preparedOutput.note]
                    == completion.outputFingerprint
            } else {
                outputIsCurrent = completion.outputFingerprint == nil
            }
            let currentEvidence = try? run.snapshot.request.commentIDs.map { id -> DocumentFingerprint in
                guard let comment = commentsByID[id] else {
                    throw ResearchFunctionContractError.invalidCompletion(
                        "Selected Comment evidence is no longer available."
                    )
                }
                return try researchCommentEvidenceRevision(comment)
            }.sorted { lhs, rhs in
                if lhs.sha256 != rhs.sha256 { return lhs.sha256 < rhs.sha256 }
                return lhs.byteCount < rhs.byteCount
            }
            let preparedEvidence = run.snapshot.evidenceRevisions.sorted { lhs, rhs in
                if lhs.sha256 != rhs.sha256 { return lhs.sha256 < rhs.sha256 }
                return lhs.byteCount < rhs.byteCount
            }
            guard targetIsCurrent,
                  materialsAreCurrent,
                  outputIsCurrent,
                  currentEvidence == preparedEvidence else {
                return ResearchFunctionRecordProjection(
                    snapshot: run.snapshot,
                    completion: ResearchFunctionCompletion(
                        runID: completion.runID,
                        function: completion.function,
                        state: .stale,
                        targetFingerprint: completion.targetFingerprint,
                        materialFingerprints: completion.materialFingerprints,
                        summary: completion.summary,
                        didModifyTarget: completion.didModifyTarget,
                        outputFingerprint: completion.outputFingerprint,
                        fidelityOutcomes: completion.fidelityOutcomes,
                        fidelityEvidenceKey: completion.fidelityEvidenceKey,
                        reusedFidelityRunID: completion.reusedFidelityRunID,
                        childRunIDs: completion.childRunIDs ?? [],
                        completedAt: completion.completedAt,
                        derivedRefreshWarning: completion.derivedRefreshWarning
                    ),
                    preparedInstructions: run.preparedInstructions
                )
            }
            return run
        }
        let research = WorkspaceResearchSnapshot(
            humanReviews: humanReviews,
            dialogues: allDialogueEntries.filter {
                $0.functionSnapshot == nil
                    || $0.functionSnapshot?.request.function == .dialogue
            },
            critiques: critiqueAssociations,
            functionRuns: functionRuns,
            checkpointListing: await services.checkpointStore.listing(),
            recoveryRecords: recoveryRecords,
            healthIssues: Array(Set(healthIssues)).sorted()
        )
        return WorkspaceSnapshot(
            triptych: assignment.triptych,
            mode: mode,
            generatedAt: Date(),
            vaults: vaultSnapshots,
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                indexGenerations: indexGenerations
            ),
            research: research
        )
    }
}

private func researchCommentEvidenceRevision(
    _ comment: ResearcherComment
) throws -> DocumentFingerprint {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return DocumentFingerprint(data: try encoder.encode(comment))
}
