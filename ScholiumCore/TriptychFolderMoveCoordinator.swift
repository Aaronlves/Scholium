import Foundation
import ScholiumContracts

/// Commits one directory rename and the exact incoming-link edits implied by
/// every moved note. The folder has no identity; note identities are committed
/// by the Application layer after this source transaction succeeds.
public actor TriptychFolderMoveCoordinator {
    private struct PreparedRewrite {
        let plan: IncomingLinkRewrite
        let repository: VaultRepository
        let mutationPath: String
        let before: NoteDocument
    }

    private struct AppliedRewrite {
        let prepared: PreparedRewrite
        let committed: NoteDocument
    }

    private let triptychID: UUID
    private let repositories: [UUID: VaultRepository]
    private let recoveryStore: TriptychMutationRecoveryStore

    public init(
        triptychID: UUID,
        repositories: [UUID: VaultRepository],
        recoveryStore: TriptychMutationRecoveryStore
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.recoveryStore = recoveryStore
    }

    public func move(_ plan: FolderIncomingLinkRewritePlan) async throws
        -> FolderMoveCommit
    {
        guard plan.sourceFolder != plan.destinationFolder else {
            throw TriptychTransactionError.invalidPlan(
                "The source and destination folder paths are identical."
            )
        }
        guard plan.blockedIncomingLinks.isEmpty else {
            let first = plan.blockedIncomingLinks[0]
            throw TriptychTransactionError.invalidPlan(
                "An incoming link in \(first.source.relativePath) at line \(first.span.start.line) cannot identify its moved note without ambiguity."
            )
        }
        guard let sourceRepository = repositories[plan.vaultID],
              sourceRepository.identity.id == plan.vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "No matching repository is registered for the folder's vault."
            )
        }

        let sourcePrefix = plan.sourceFolder.rawValue + "/"
        let destinationPrefix = plan.destinationFolder.rawValue + "/"
        guard plan.noteMoves.allSatisfy({ move in
            move.source.vaultID == plan.vaultID
                && move.destination.vaultID == plan.vaultID
                && move.source.relativePath.hasPrefix(sourcePrefix)
                && move.destination.relativePath
                    == destinationPrefix + move.source.relativePath.dropFirst(sourcePrefix.count)
        }) else {
            throw TriptychTransactionError.invalidPlan(
                "A folder move must preserve every descendant note's relative suffix."
            )
        }
        guard Set(plan.noteMoves.map(\.source)).count == plan.noteMoves.count,
              Set(plan.noteMoves.map(\.destination)).count == plan.noteMoves.count else {
            throw TriptychTransactionError.invalidPlan(
                "A folder move cannot contain duplicate note locations."
            )
        }

        let expectedDocuments = Dictionary(
            uniqueKeysWithValues: plan.noteMoves.map {
                ($0.source.relativePath, $0.expectedRevision)
            }
        )
        let sourceDocuments: [NoteDocument]
        do {
            sourceDocuments = try await sourceRepository.preflightFolderMove(
                from: plan.sourceFolder,
                to: plan.destinationFolder,
                expectedDocuments: expectedDocuments,
                createMissingParents: destinationNeedsLifecycleParent(plan.destinationFolder)
            )
        } catch {
            throw TriptychTransactionError.preflightFailed(
                note: nil,
                detail: error.localizedDescription
            )
        }
        let documentsByPath = Dictionary(
            uniqueKeysWithValues: sourceDocuments.map { ($0.relativePath, $0) }
        )
        let movesBySource = Dictionary(
            uniqueKeysWithValues: plan.noteMoves.map { ($0.source, $0) }
        )

        var prepared: [PreparedRewrite] = []
        do {
            for rewrite in plan.rewrites {
                guard let repository = repositories[rewrite.source.vaultID],
                      repository.identity.id == rewrite.source.vaultID else {
                    throw TriptychTransactionError.invalidPlan(
                        "No repository is registered for an incoming-link source."
                    )
                }
                let mutationPath: String
                let before: NoteDocument
                if let move = movesBySource[rewrite.source] {
                    mutationPath = move.destination.relativePath
                    guard let sourceBefore = documentsByPath[move.source.relativePath],
                          sourceBefore.fingerprint == rewrite.expectedRevision else {
                        throw TriptychTransactionError.invalidPlan(
                            "A moved note and its link rewrite have different starting revisions."
                        )
                    }
                    before = sourceBefore
                } else {
                    mutationPath = rewrite.source.relativePath
                    before = try await repository.preflightExisting(
                        relativePath: rewrite.source.relativePath,
                        expectedRevision: rewrite.expectedRevision
                    )
                }
                let proposed = NoteDocument(
                    relativePath: mutationPath,
                    rawContent: rewrite.updatedSource
                )
                if proposed.rawFrontmatter != nil, !proposed.validationWarnings.isEmpty {
                    throw VaultRepositoryError.invalidFrontmatter(
                        proposed.validationWarnings.joined(separator: "\n")
                    )
                }
                prepared.append(PreparedRewrite(
                    plan: rewrite,
                    repository: repository,
                    mutationPath: mutationPath,
                    before: before
                ))
            }
        } catch let error as TriptychTransactionError {
            throw error
        } catch {
            throw TriptychTransactionError.preflightFailed(
                note: nil,
                detail: error.localizedDescription
            )
        }

        var folderDidMove = false
        var recoveryMoves: [FolderNoteMovePlan] = []
        var applied: [AppliedRewrite] = []
        var movedDocumentsByPath: [String: NoteDocument] = [:]
        do {
            let folderMove = try await sourceRepository.moveFolder(
                from: plan.sourceFolder,
                to: plan.destinationFolder,
                expectedDocuments: expectedDocuments,
                createMissingParents: destinationNeedsLifecycleParent(plan.destinationFolder)
            )
            movedDocumentsByPath = Dictionary(uniqueKeysWithValues: folderMove.documents.map {
                ($0.relativePath, $0)
            })
            folderDidMove = true
            for move in plan.noteMoves {
                try await sourceRepository.migrateRecoveryLedger(
                    from: move.source.relativePath,
                    to: move.destination.relativePath
                )
                recoveryMoves.append(move)
            }
            for rewrite in prepared {
                let saved = try await rewrite.repository.save(
                    relativePath: rewrite.mutationPath,
                    changeSet: .exactContent(rewrite.plan.updatedSource),
                    expectedRevision: rewrite.plan.expectedRevision
                )
                applied.append(AppliedRewrite(prepared: rewrite, committed: saved.document))
            }
        } catch {
            if !folderDidMove {
                folderDidMove = await sourceRepository.folderExists(plan.destinationFolder)
            }
            try await reconcileFailure(
                error,
                plan: plan,
                sourceRepository: sourceRepository,
                folderDidMove: folderDidMove,
                recoveryMoves: recoveryMoves,
                applied: applied
            )
        }

        let appliedBySource = Dictionary(
            uniqueKeysWithValues: applied.map { ($0.prepared.plan.source, $0) }
        )
        let noteCommits = try plan.noteMoves.map { move in
            guard let committedDocument = appliedBySource[move.source]?.committed
                    ?? movedDocumentsByPath[move.destination.relativePath],
                  committedDocument.relativePath == move.destination.relativePath else {
                throw TriptychTransactionError.invalidPlan(
                    "The committed source for \(move.destination.relativePath) is unavailable."
                )
            }
            return FolderNoteMoveCommit(
                stableNoteID: move.stableNoteID,
                source: move.source,
                destination: move.destination,
                previousRevision: move.expectedRevision,
                committedRevision: committedDocument.fingerprint,
                committedRawContent: committedDocument.rawContent
            )
        }.sorted { $0.source < $1.source }
        let rewriteCommits = applied.map { rewrite in
            let projectedNote = movesBySource[rewrite.prepared.plan.source]?.destination
                ?? rewrite.prepared.plan.source
            return CoordinatedIncomingLinkRewriteResult(
                note: projectedNote,
                previousRevision: rewrite.prepared.before.fingerprint,
                committedRevision: rewrite.committed.fingerprint,
                rewrittenOccurrences: rewrite.prepared.plan.rewrittenOccurrences
            )
        }
        return FolderMoveCommit(
            vaultID: plan.vaultID,
            sourceFolder: plan.sourceFolder,
            destinationFolder: plan.destinationFolder,
            graphGeneration: plan.graphGeneration,
            noteMoves: noteCommits,
            rewrites: rewriteCommits
        )
    }

    private func reconcileFailure(
        _ cause: Error,
        plan: FolderIncomingLinkRewritePlan,
        sourceRepository: VaultRepository,
        folderDidMove: Bool,
        recoveryMoves: [FolderNoteMovePlan],
        applied: [AppliedRewrite]
    ) async throws -> Never {
        var rollbackErrors: [String] = []
        for rewrite in applied.reversed() {
            do {
                _ = try await rewrite.prepared.repository.save(
                    relativePath: rewrite.prepared.mutationPath,
                    changeSet: .exactContent(rewrite.prepared.before.rawContent),
                    expectedRevision: rewrite.committed.fingerprint
                )
            } catch {
                rollbackErrors.append(
                    "\(rewrite.prepared.mutationPath): \(error.localizedDescription)"
                )
            }
        }

        for move in recoveryMoves.reversed() {
            do {
                try await sourceRepository.migrateRecoveryLedger(
                    from: move.destination.relativePath,
                    to: move.source.relativePath
                )
            } catch {
                rollbackErrors.append(
                    "Recovery \(move.destination.relativePath): \(error.localizedDescription)"
                )
            }
        }

        if folderDidMove {
            let destinationPrefix = plan.destinationFolder.rawValue + "/"
            let destinationDocuments = Dictionary(
                uniqueKeysWithValues: plan.noteMoves.map { move in
                    let suffix = move.source.relativePath.dropFirst(
                        plan.sourceFolder.rawValue.count + 1
                    )
                    return (destinationPrefix + suffix, move.expectedRevision)
                }
            )
            do {
                _ = try await sourceRepository.moveFolder(
                    from: plan.destinationFolder,
                    to: plan.sourceFolder,
                    expectedDocuments: destinationDocuments
                )
            } catch {
                rollbackErrors.append(
                    "\(plan.sourceFolder.rawValue): \(error.localizedDescription)"
                )
            }
        }

        let sourceExists = await sourceRepository.folderExists(plan.sourceFolder)
        let destinationExists = await sourceRepository.folderExists(plan.destinationFolder)
        if sourceExists, !destinationExists, rollbackErrors.isEmpty {
            throw TriptychTransactionError.transactionRolledBack(cause.localizedDescription)
        }

        let folderState: TriptychMutationRecoveryState
        if sourceExists, !destinationExists {
            folderState = .restored
        } else if !sourceExists, destinationExists {
            folderState = .intendedBytesRemain
        } else if !sourceExists, !destinationExists {
            folderState = .missing
        } else {
            folderState = .externallyChanged
        }
        var files = [TriptychMutationRecoveryFile(
            vaultID: plan.vaultID,
            path: plan.sourceFolder.rawValue,
            alternatePath: plan.destinationFolder.rawValue,
            role: .movedFolder,
            beforeRevision: nil,
            intendedRevision: nil,
            observedRevision: nil,
            state: folderState,
            detail: "Folder paths have no identity. Inspect both locations and their descendant notes before resolving recovery."
        )]
        for rewrite in applied {
            let observed = try? await rewrite.prepared.repository.load(
                relativePath: rewrite.prepared.mutationPath
            )
            let intended = DocumentFingerprint(content: rewrite.prepared.plan.updatedSource)
            let state: TriptychMutationRecoveryState
            if observed?.fingerprint == rewrite.prepared.before.fingerprint {
                state = .restored
            } else if observed?.fingerprint == intended {
                state = .intendedBytesRemain
            } else if observed == nil {
                state = .missing
            } else {
                state = .externallyChanged
            }
            files.append(TriptychMutationRecoveryFile(
                vaultID: rewrite.prepared.plan.source.vaultID,
                path: rewrite.prepared.mutationPath,
                role: .incomingLinkRewrite,
                beforeRevision: rewrite.prepared.before.fingerprint,
                intendedRevision: intended,
                observedRevision: observed?.fingerprint,
                state: state,
                detail: "Incoming link rewrite for \(rewrite.prepared.plan.rewrittenOccurrences) resolved occurrence(s)."
            ))
        }
        let detail = ([cause.localizedDescription] + rollbackErrors).joined(separator: "\n")
        let record = TriptychMutationRecoveryRecord(
            triptychID: triptychID,
            operation: .folderMove,
            failure: detail,
            files: files
        )
        do {
            try await recoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        throw TriptychTransactionError.recoveryRequired(record)
    }

    private func destinationNeedsLifecycleParent(
        _ destination: VaultRelativeFolderPath
    ) -> Bool {
        destination.components.first == "Trash"
            || destination.components.first == "Set Aside"
    }
}
