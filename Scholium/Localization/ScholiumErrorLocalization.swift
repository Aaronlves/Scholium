import Foundation
import ScholiumContracts

/// Localizes typed failures only at the researcher-facing application boundary.
/// Domain diagnostics, source bytes, paths and external runtime messages remain
/// verbatim; this projection never changes a stored or protocol error.
enum ScholiumErrorLocalization {
    static func message(_ error: any Error, locale: Locale = .current) -> String {
        if let message = applicationMessage(error, locale: locale) { return message }
        switch error {
        case let error as ExactFileReplacementError:
            return switch error {
            case .revisionConflict: ScholiumL10n.string("The configuration file or its directory changed. Reload before trying again.", locale: locale)
            case .commitUncertain(let reason): ScholiumL10n.string("The configuration replacement could not be proven: \(reason)", locale: locale)
            }
        case let error as IndexedAttachmentAccessError:
            return switch error {
            case .damaged(let reason): ScholiumL10n.string("The machine-local indexed-attachment access store is damaged: \(reason)", locale: locale)
            case .bookmarkUnavailable(let path):
                ScholiumL10n.string("Scholium could not retain read access to the indexed attachment at \(path).", locale: locale)
            }
        case let error as BundledResearchSkillResourceError:
            return switch error {
            case .unavailable: ScholiumL10n.string("The bundled Scholium Core Protocol is unavailable.", locale: locale)
            case .invalid(let path): ScholiumL10n.string("The bundled Scholium Core Protocol is invalid at \(path).", locale: locale)
            }
        case let error as VaultRepositoryError:
            return switch error {
            case .invalidRelativePath(let path): ScholiumL10n.string("Invalid vault-relative path: \(path)", locale: locale)
            case .outsideVault(let path): ScholiumL10n.string("The path escapes the selected vault: \(path)", locale: locale)
            case .rootUnavailable(let path):
                ScholiumL10n.string("The selected vault root is no longer the authorized filesystem object: \(path)", locale: locale)
            case .fileDoesNotExist(let path): ScholiumL10n.string("The note no longer exists: \(path)", locale: locale)
            case .fileAlreadyExists(let path): ScholiumL10n.string("A note already exists at: \(path)", locale: locale)
            case .notRegularFile(let path): ScholiumL10n.string("The path is not a regular file: \(path)", locale: locale)
            case .markdownRequired(let path): ScholiumL10n.string("Scholium note operations require a Markdown file: \(path)", locale: locale)
            case .conflict: ScholiumL10n.string("This note changed on disk after editing began. Compare changes or reload before saving.", locale: locale)
            case .readbackMismatch:
                ScholiumL10n.string(
                    "Scholium could not verify the saved bytes. The editor buffer and any unresolved save transaction remain available for recovery.",
                    locale: locale)
            case .invalidFrontmatter(let detail): ScholiumL10n.string("Invalid YAML frontmatter: \(detail)", locale: locale)
            case .recoveryEntryNotFound(let id): ScholiumL10n.string("Recovery entry not found: \(id.uuidString)", locale: locale)
            case .recoveryPathConflict(let path):
                ScholiumL10n.string("An interrupted-save transaction already belongs to another note at: \(path)", locale: locale)
            case .recoveryLedgerUnavailable(let reason):
                ScholiumL10n.string(
                    "Interrupted-save recovery is unavailable, so Scholium did not modify the note. Existing transaction evidence remains unchanged. \(reason)",
                    locale: locale)
            case .pathCollision(let existing, let requested):
                ScholiumL10n.string(
                    "The requested note path collides with an existing path on this volume: \(requested) (existing: \(existing))", locale: locale)
            case .writeFailed(let reason):
                ScholiumL10n.string("Scholium could not save the note. The source remains unchanged and you can retry. \(reason)", locale: locale)
            case .commitUncertain(let reason):
                ScholiumL10n.string(
                    "Scholium could not prove which bytes are canonical after the commit. It preserved recovery evidence and did not report the note as saved. \(reason)",
                    locale: locale)
            case .recoveryRequired(let recovery):
                ScholiumL10n.string(
                    "The note save remains unresolved. Recovery transaction \(recovery.id.transactionID.uuidString) requires exact source reconciliation before the write can be finalized.",
                    locale: locale)
            case .atomicCommitUnsupported(let reason):
                ScholiumL10n.string(
                    "This volume cannot provide the coordinated atomic commit required for this operation. The note remains open and unchanged. \(reason)",
                    locale: locale)
            }
        case let error as WorkspaceRegistryError:
            return switch error {
            case .notDirectory(let path): ScholiumL10n.string("Vault path is not a directory: \(path)", locale: locale)
            case .duplicateName(let name): ScholiumL10n.string("A different registered vault already uses the name '\(name)'.", locale: locale)
            case .vaultNotFound(let selector): ScholiumL10n.string("No registered vault matches '\(selector)'.", locale: locale)
            case .ambiguousSelector(let selector): ScholiumL10n.string("More than one registered vault matches '\(selector)'. Use its UUID.", locale: locale)
            case .triptychNotFound(let id): ScholiumL10n.string("No registered Triptych matches '\(id.uuidString)'.", locale: locale)
            case .triptychSelectorNotFound(let selector): ScholiumL10n.string("No registered Triptych matches '\(selector)'.", locale: locale)
            case .ambiguousTriptychSelector(let selector):
                ScholiumL10n.string("More than one registered Triptych is named '\(selector)'. Use its UUID.", locale: locale)
            case .triptychIdentityConflict(let id): ScholiumL10n.string("Another registered Triptych already uses identity '\(id.uuidString)'.", locale: locale)
            case .registryRecoveryRequired(let health): registrySummary(health, locale: locale)
            case .triptychControlDirectoryInUse(let path):
                ScholiumL10n.string(
                    "Another registered Triptych already uses the portable control folder at '\(path)'. Choose a Works folder under a different parent.",
                    locale: locale)
            case .overlappingVaults(let first, let second):
                ScholiumL10n.string("Vault folders in one Triptych must be independent. '\(first)' overlaps '\(second)'.", locale: locale)
            case .vaultIdentityMismatch(let id, let existing, let selected):
                ScholiumL10n.string("Vault identity \(id.uuidString) already belongs to '\(existing)', not '\(selected)'.", locale: locale)
            case .duplicateVaultIdentity(let id):
                ScholiumL10n.string("Analyses, Topics, and Works must use different identities. \(id.uuidString) was selected more than once.", locale: locale)
            case .vaultRoleMismatch(let id, let existing, let requested):
                ScholiumL10n.string(
                    "Vault identity \(id.uuidString) is already registered as \(roleName(existing, locale: locale)), not \(roleName(requested, locale: locale)).",
                    locale: locale)
            case .incompleteWorkspace: ScholiumL10n.string("The Triptych is incomplete. Choose Analyses, Topics, and Works again.", locale: locale)
            case .vaultAccessUnavailable(let path):
                ScholiumL10n.string("Scholium no longer has access to '\(path)'. Open Manage Triptychs and choose that folder again.", locale: locale)
            case .portableControlAccessUnavailable(let path):
                ScholiumL10n.string(
                    "Scholium needs access to '\(path)' because the portable .scholium folder sits beside Works. Open Manage Triptychs and authorize that folder again.",
                    locale: locale)
            }
        case let error as TriptychControlError:
            return switch error {
            case .invalidManifest: ScholiumL10n.string("The Triptych manifest is missing or does not match the selected vaults.", locale: locale)
            case .settingsMissing:
                ScholiumL10n.string("The portable Triptych settings are missing. Managed creation is unavailable until they are restored.", locale: locale)
            case .settingsOldSchema(let version): oldSettingsMessage(version: version, locale: locale)
            case .settingsFutureSchema(let version):
                ScholiumL10n.string("The portable Triptych settings use future schema \(String(version)). Their exact bytes were preserved.", locale: locale)
            case .settingsCorrupted:
                ScholiumL10n.string("The current-schema portable Triptych settings are damaged. Their exact bytes were preserved for recovery.", locale: locale)
            case .settingsNeedsReview(let reason):
                ScholiumL10n.string("The current-schema portable Triptych settings need review before settings can be saved: \(reason)", locale: locale)
            case .settingsRevisionConflict:
                ScholiumL10n.string("The Triptych settings changed after they were loaded. Reload the saved settings before trying again.", locale: locale)
            case .controlFileCommitUncertain(let reason):
                ScholiumL10n.string(
                    "Scholium could not prove the final state of a portable control-file replacement. Reread the authoritative file before retrying: \(reason)",
                    locale: locale)
            case .invalidAttachmentCatalog:
                ScholiumL10n.string(
                    "The portable attachment catalog is missing, damaged, or uses an unsupported schema. Its exact bytes were preserved for recovery.",
                    locale: locale)
            case .invalidIdentities:
                ScholiumL10n.string("The portable Note identities are missing or damaged. Their exact bytes were preserved for recovery.", locale: locale)
            case .identitiesRevisionConflict:
                ScholiumL10n.string(
                    "The portable Note identities changed while Scholium was updating them. Reload the workspace before trying again.", locale: locale)
            case .invalidIdentityCandidate(let id):
                ScholiumL10n.string("The selected note identity is no longer a valid candidate: \(id.uuidString)", locale: locale)
            case .identityPathAlreadyAssigned(let path): ScholiumL10n.string("Another note identity is already assigned to \(path).", locale: locale)
            case .identityRebindingNotFound(let id):
                ScholiumL10n.string("The pending note-identity migration no longer exists: \(id.uuidString).", locale: locale)
            }
        case let error as ScholiumApplicationError:
            return switch error {
            case .runtimeShutDown: ScholiumL10n.string("The Scholium application runtime has shut down.", locale: locale)
            case .workspaceShutDown(let id): ScholiumL10n.string("The Scholium workspace \(id.uuidString) has shut down.", locale: locale)
            case .workspaceNotFound(let id): ScholiumL10n.string("No Scholium Triptych matches \(id.uuidString).", locale: locale)
            case .workspaceSelectorNotFound(let selector): ScholiumL10n.string("No Scholium Triptych matches '\(selector)'.", locale: locale)
            case .ambiguousWorkspaceSelector(let selector):
                ScholiumL10n.string("More than one Scholium Triptych is named '\(selector)'. Use its UUID.", locale: locale)
            case .incompleteTriptych(let id): ScholiumL10n.string("The Scholium Triptych \(id.uuidString) does not contain all three vaults.", locale: locale)
            case .vaultNotInWorkspace(let id): ScholiumL10n.string("Vault \(id.uuidString) is not part of this Scholium Triptych.", locale: locale)
            case .workspaceStillLoading(let id):
                ScholiumL10n.string(
                    "Scholium is still loading the complete Triptych \(id.uuidString). This Note and the currently open vault support bounded text Search; Triptych Search and direct links will become available when loading finishes.",
                    locale: locale)
            case .workspaceRegistrationInUse(let id):
                ScholiumL10n.string(
                    "Scholium cannot remove Triptych registration \(id.uuidString) while that Triptych is open. Close its other windows and try again.",
                    locale: locale)
            case .portableControlRecoveryRequired(let path, let reason):
                ScholiumL10n.string(
                    "The portable control folder at \(path) is incompatible or damaged. Preserve the entire folder before Scholium creates current control state. \(reason)",
                    locale: locale)
            case .manifestIdentityMismatch(let expected, let actual):
                ScholiumL10n.string("The portable Triptych identity is \(actual.uuidString), not \(expected.uuidString).", locale: locale)
            case .operationCommittedButRefreshFailed(let operation, let reason):
                ScholiumL10n.string("\(operation) committed successfully, but the workspace snapshot could not be refreshed: \(reason)", locale: locale)
            case .operationCommitUncertain(let operation, let reason):
                ScholiumL10n.string(
                    "Scholium could not prove whether \(operation) committed. Reload the authoritative state before trying another mutation: \(reason)",
                    locale: locale)
            case .noWorkspaceConfigured: ScholiumL10n.string("No Scholium Triptych is configured.", locale: locale)
            case .runtimeConfigurationUnavailable:
                ScholiumL10n.string("This fixed workspace snapshot cannot change Triptych registration or access.", locale: locale)
            }
        case let error as TriptychTransactionError:
            return switch error {
            case .invalidPlan(let detail): ScholiumL10n.string("The note move plan is invalid: \(detail)", locale: locale)
            case .preflightFailed(let note, let detail): preflightMessage(note: note, detail: detail, locale: locale)
            case .transactionRolledBack(let detail):
                ScholiumL10n.string("The operation failed and Scholium restored the affected files: \(detail)", locale: locale)
            case .recoveryRequired(let record):
                ScholiumL10n.string(
                    "The operation did not complete and could not be fully restored. Recovery record \(record.id.uuidString) identifies every affected file.",
                    locale: locale)
            case .recoveryPersistenceFailed(let record, let detail):
                ScholiumL10n.string(
                    "The operation requires recovery, and Scholium could not persist recovery record \(record.id.uuidString): \(detail)", locale: locale)
            }
        case let error as DocumentChangeError:
            return switch error {
            case .unavailable(let reason): ScholiumL10n.string("Changes storage is unavailable: \(reason)", locale: locale)
            case .noteUnavailable: ScholiumL10n.string("The Note identity or saved source is unavailable.", locale: locale)
            case .baselineUnavailable: ScholiumL10n.string("The starting source is unavailable; no comparison was invented.", locale: locale)
            case .noPendingChanges: ScholiumL10n.string("The saved Note has no pending Changes.", locale: locale)
            case .staleCapture: ScholiumL10n.string("A newer comparison was reviewed. Reopen this Note's Changes.", locale: locale)
            case .missingCapture: ScholiumL10n.string("The displayed comparison is no longer retained. Reopen it.", locale: locale)
            case .missingHistory: ScholiumL10n.string("This reviewed batch is unavailable.", locale: locale)
            case .invalidRecord: ScholiumL10n.string("A Changes record is damaged or has an unsupported schema.", locale: locale)
            case .historyChangedCleanupPending(let reason):
                ScholiumL10n.string("Reviewed history changed, but receipt cleanup needs retry: \(reason)", locale: locale)
            }
        case let error as AgentCollaborationError:
            return switch error {
            case .noteNotFound: ScholiumL10n.string("The stable Note identity is not present.", locale: locale)
            case .noteAmbiguous: ScholiumL10n.string("The stable Note identity is ambiguous.", locale: locale)
            case .staleRevision: ScholiumL10n.string("The Note fingerprint is stale.", locale: locale)
            case .pathOccupied: ScholiumL10n.string("The requested Note path is occupied.", locale: locale)
            case .invalidRequest(let reason): ScholiumL10n.string("The Note update request is invalid. Diagnostic details: \(reason)", locale: locale)
            case .noChanges: ScholiumL10n.string("The proposed update would not change the Note.", locale: locale)
            case .changeConfirmationUncertain:
                ScholiumL10n.string("The source operation may have committed, but its Agent Change could not be confirmed.", locale: locale)
            }
        case let error as AgentChangeError:
            return switch error {
            case .missing: ScholiumL10n.string("The Agent Change is unavailable.", locale: locale)
            case .invalid: ScholiumL10n.string("The Agent Change is damaged or has an unsupported schema.", locale: locale)
            case .mismatchedBinding: ScholiumL10n.string("The Agent Change belongs to another mutation.", locale: locale)
            case .sourceTooLarge: ScholiumL10n.string("The Agent Change exceeds the supported exact-source size.", locale: locale)
            case .alreadyFinal: ScholiumL10n.string("The Agent Change is already in a final state.", locale: locale)
            case .notConfirmed: ScholiumL10n.string("The Agent Change is not confirmed.", locale: locale)
            case .undoUnavailable: ScholiumL10n.string("Direct Undo is unavailable for this Agent Change.", locale: locale)
            case .unsafeStore(let reason): ScholiumL10n.string("Agent Changes are unavailable: \(reason)", locale: locale)
            }
        case let error as NoteIdentityRecoveryError:
            return switch error {
            case .vaultMismatch(let expected, let current):
                ScholiumL10n.string("Identity recovery belongs to vault \(expected.uuidString), not \(current.uuidString).", locale: locale)
            case .staleResolution:
                ScholiumL10n.string(
                    "The note changed after the identity choices were shown. Review the refreshed choices before confirming its identity.", locale: locale)
            case .identityUnresolved(let path): ScholiumL10n.string("Confirm the note identity before continuing this operation: \(path)", locale: locale)
            case .targetIdentityChanged(let path):
                ScholiumL10n.string(
                    "The note at \(path) no longer has the identity captured when this action began. Refresh Library and try again.", locale: locale)
            }
        case let error as NoteIdentityMigrationError:
            return switch error {
            case .incomplete(let detail):
                ScholiumL10n.string(
                    "The note identity was confirmed, but its app-owned records have not finished moving. Identity-dependent actions remain unavailable. \(detail)",
                    locale: locale)
            }
        case let error as DocumentCreationError:
            return switch error {
            case .invalidSource: ScholiumL10n.string("Provide bounded UTF-8 Markdown without NUL bytes.", locale: locale)
            case .portableIdentityAlreadyExists:
                ScholiumL10n.string("The creation path already belongs to a portable Note identity. Choose a new path.", locale: locale)
            case .reservedIdentityMismatch:
                ScholiumL10n.string("The created note did not receive the stable identity reserved by its authorization.", locale: locale)
            }
        case let error as DocumentImportError:
            return switch error {
            case .unsupportedSource(let path): ScholiumL10n.string("Only regular UTF-8 Markdown files can be imported: \(path)", locale: locale)
            case .commitUncertain(let path, _, let reason):
                ScholiumL10n.string(
                    "The imported copy at \(path) could not be verified. Do not import again until this destination has been reconciled. \(reason)",
                    locale: locale)
            }
        case let error as DocumentAttachmentError:
            return switch error {
            case .unsupportedDocument(let path):
                ScholiumL10n.string("Choose a regular document file rather than image, audio, or video media: \(path)", locale: locale)
            case .noteIdentityChanged(let path):
                ScholiumL10n.string(
                    "The Note identity at \(path) changed before the document could be attached. Reload the workspace and try again.", locale: locale)
            case .unavailable(let filename): ScholiumL10n.string("The attached document is unavailable on this Mac: \(filename)", locale: locale)
            case .cleanupRefused(let path):
                ScholiumL10n.string(
                    "Scholium left the copied document at \(path) in place because it could not prove that the file was created by this attachment.",
                    locale: locale)
            case .preparationCleanupFailed(let operation, let cleanup):
                ScholiumL10n.string(
                    "Document attachment failed, and Scholium could not complete exact cleanup. Do not repeat the operation until the Triptych is inspected. Operation: \(operation) Cleanup: \(cleanup)",
                    locale: locale)
            }
        case let error as ImageAttachmentError:
            return switch error {
            case .unsupportedImage(let path): ScholiumL10n.string("Choose a supported image file: \(path)", locale: locale)
            case .sourceChanged(let path): ScholiumL10n.string("The selected image changed while Scholium was reading it: \(path)", locale: locale)
            case .invalidCatalog:
                ScholiumL10n.string("The portable attachment catalog is damaged or uses an unsupported schema. Its exact bytes were preserved.", locale: locale)
            case .catalogConflict:
                ScholiumL10n.string(
                    "The portable attachment catalog changed while Scholium was updating it. Reload the workspace before trying again.", locale: locale)
            case .catalogCommitUncertain(let reason):
                ScholiumL10n.string(
                    "Scholium could not prove the final state of the portable attachment catalog. The image file was preserved for inspection: \(reason)",
                    locale: locale)
            case .cleanupRefused(let path):
                ScholiumL10n.string(
                    "Scholium left the attachment at \(path) in place because it could not prove that the file was created by this insertion.", locale: locale)
            case .preparationCleanupFailed(let operation, let cleanup):
                ScholiumL10n.string(
                    "Attachment preparation failed, and Scholium could not complete exact cleanup. Do not repeat the insertion until the vault is inspected. Operation: \(operation) Cleanup: \(cleanup)",
                    locale: locale)
            }
        case let error as AgentChatPDFPageSelectionFailure:
            return switch error {
            case .invalidRange: ScholiumL10n.string("Enter valid PDF page numbers, such as 1–5, 8.", locale: locale)
            case .tooManyPages: ScholiumL10n.string("Choose up to 20 pages for one image input.", locale: locale)
            case .unavailable: ScholiumL10n.string("The retained PDF is unavailable or locked. Replace it and try again.", locale: locale)
            }
        case let error as ZoteroUseCaseError:
            return switch error {
            case .appUnavailable: ScholiumL10n.string("Zotero is not responding on this Mac. Open Zotero and try again.", locale: locale)
            case .apiDisabled:
                ScholiumL10n.string(
                    "Zotero local API access is disabled. In Zotero Advanced settings, enable Allow other applications on this computer to communicate with Zotero.",
                    locale: locale)
            case .itemMissing(let key): ScholiumL10n.string("Zotero item \(key) was not found.", locale: locale)
            case .invalidResponse: ScholiumL10n.string("Zotero returned metadata Scholium could not read.", locale: locale)
            case .invalidItemKey:
                ScholiumL10n.string("The selected Zotero item has an invalid item key. Refresh Zotero and choose the item again.", locale: locale)
            case .invalidAnalysisReference: ScholiumL10n.string("The Zotero source can be confirmed only for an Analysis in this Triptych.", locale: locale)
            }
        case let error as FrontmatterPatchRefusal:
            return switch error {
            case .invalidYAML(let detail, _): ScholiumL10n.string("The complete YAML frontmatter is invalid: \(detail)", locale: locale)
            case .nonBlockMappingRoot:
                ScholiumL10n.string("This YAML operation requires a block mapping. Open Source to edit this frontmatter.", locale: locale)
            case .ambiguousStructure(let detail, _):
                ScholiumL10n.string("Scholium refused an ambiguous YAML edit: \(detail) Open Source to edit it directly.", locale: locale)
            case .unsupportedExistingValue(let key):
                ScholiumL10n.string(
                    "Scholium can only replace or remove a uniquely bounded ordinary YAML value for ‘\(key)’. Open Source to edit this value.", locale: locale)
            case .semanticMismatch(let key):
                ScholiumL10n.string(
                    "Scholium could not prove that the encoded YAML preserves the requested value for ‘\(key)’. No replacement source was accepted.",
                    locale: locale)
            }
        case let error as ParagraphAnchorError:
            return switch error {
            case .unsupportedParagraph:
                ScholiumL10n.string("Choose a complete ordinary paragraph outside lists, quotations, definitions, and protected source.", locale: locale)
            case .invalidIdentifier: ScholiumL10n.string("A paragraph identifier must contain only ASCII letters, numbers, and hyphens.", locale: locale)
            case .duplicateIdentifier(let id):
                ScholiumL10n.string("The paragraph identifier ^\(id) occurs more than once. Resolve the ambiguity first.", locale: locale)
            case .partialAnchor: ScholiumL10n.string("The selection cuts through a paragraph identity. Select the complete paragraph.", locale: locale)
            }
        case let error as MarkdownEditorDeltaError:
            return switch error {
            case .invalidRange: ScholiumL10n.string("The editor returned an invalid UTF-16 change range.", locale: locale)
            case .overlappingRanges: ScholiumL10n.string("The editor returned overlapping document changes.", locale: locale)
            case .oversizedResult: ScholiumL10n.string("The edited Markdown document exceeds the supported bridge size.", locale: locale)
            }
        case let error as ExactSourceComparisonError:
            return switch error {
            case .exactRevisionUnavailable(let revision):
                ScholiumL10n.string("Comparison is unavailable because exact revision \(revision.sha256) is not retained.", locale: locale)
            case .nonUTF8Revision(let revision):
                ScholiumL10n.string("Comparison is unavailable because revision \(revision.sha256) is not valid UTF-8 Markdown.", locale: locale)
            case .fingerprintMismatch(let expected, let observed):
                ScholiumL10n.string(
                    "Comparison is unavailable because retained bytes \(observed.sha256) do not match recorded revision \(expected.sha256).", locale: locale)
            }
        case let error as StyleUseCaseError:
            return switch error {
            case .unavailable(let reason):
                ScholiumL10n.string(
                    "Appearance settings are unavailable: \(reason) Reveal the managed Styles folder in Finder and repair or remove the invalid settings file before making changes.",
                    locale: locale)
            case .invalidConfiguration(let reason):
                ScholiumL10n.string("Could not load appearance configuration: \(reason) The current appearance has been retained.", locale: locale)
            case .configurationChanged:
                ScholiumL10n.string(
                    "The appearance configuration changed outside Scholium. Reload it before saving. Your draft has been retained.", locale: locale)
            }
        case let error as CSSSnippetSanitizationError:
            return switch error {
            case .tooLarge: ScholiumL10n.string("The CSS snippet is larger than 1 MB.", locale: locale)
            case .forbiddenConstruct(let construct): ScholiumL10n.string("The CSS snippet contains a forbidden construct: \(construct).", locale: locale)
            case .malformed(let reason): ScholiumL10n.string("The CSS snippet is malformed: \(reason).", locale: locale)
            case .unsupportedSelector(let selector): ScholiumL10n.string("The selector is not supported by Scholium: \(selector).", locale: locale)
            case .unsupportedProperty(let property): ScholiumL10n.string("The CSS property is not supported by Scholium: \(property).", locale: locale)
            }
        case let error as SearchIndexError:
            return switch error {
            case .sqlite(let detail): ScholiumL10n.string("The search index failed: \(detail)", locale: locale)
            case .corruptDatabase: ScholiumL10n.string("The generated search index is corrupt and must be rebuilt.", locale: locale)
            case .incompatibleSchema: ScholiumL10n.string("The generated search index uses an incompatible schema and must be rebuilt.", locale: locale)
            case .invalidDocuments(let detail): ScholiumL10n.string("The search index input is invalid: \(detail)", locale: locale)
            }
        case let error as SavedSearchStoreError:
            return switch error {
            case .unreadable(let detail):
                ScholiumL10n.string("Scholium could not safely load Saved Searches. The existing file was left unchanged. \(detail)", locale: locale)
            }
        case let error as SearchTermGroupError:
            return switch error {
            case .invalid: ScholiumL10n.string("Use a name of up to 80 characters and 1–24 terms, each on one line and up to 512 characters.", locale: locale)
            case .unreadable: ScholiumL10n.string("Term groups could not be read. Their stored data has been preserved.", locale: locale)
            case .changed: ScholiumL10n.string("This term group changed elsewhere. Reload before editing it.", locale: locale)
            case .insertion:
                ScholiumL10n.string("Place the caret between complete conditions or inside an empty text group before inserting terms.", locale: locale)
            }
        case let error as DocumentExportImageError:
            return switch error {
            case .unavailable(let path):
                ScholiumL10n.string(
                    "The image at \(path) is missing or cannot be accessed. Restore access or remove the image reference, then export again.", locale: locale)
            case .unsupported(let path):
                ScholiumL10n.string(
                    "The image at \(path) is unsupported, damaged, or exceeds the export size limit. Replace it with a PNG, JPEG, GIF, or WebP image up to 10 MiB, then export again.",
                    locale: locale)
            case .totalSizeExceeded:
                ScholiumL10n.string("The Note's local images exceed the 80 MiB export limit. Remove or reduce some images, then export again.", locale: locale)
            }
        case let error as WorkspaceHydrationError:
            return switch error {
            case .staleSnapshot: ScholiumL10n.string("The Note changed before its source finished loading. Refresh and try again.", locale: locale)
            }
        case let error as WorkspaceGraphQueryError:
            return switch error {
            case .graphUnavailable: ScholiumL10n.string("The Triptych graph is not ready.", locale: locale)
            case .noteNotFound(let note):
                ScholiumL10n.string("The workspace note was not found: \(note.vaultID.uuidString.lowercased()):\(note.relativePath)", locale: locale)
            }
        case let error as NoteRestructureError:
            return switch error {
            case .unavailable(let detail): ScholiumL10n.string("This Note cannot be reorganized. Diagnostic details: \(detail)", locale: locale)
            case .propertyConflicts:
                ScholiumL10n.string("Choose which authored YAML entry to keep for each conflicting property before reviewing the merge.", locale: locale)
            }
        case let error as PortableControlAccessError:
            return switch error {
            case .invalidContainer(let expected, let selected):
                ScholiumL10n.string("Choose the folder containing Works. Expected '\(expected)', but received '\(selected)'.", locale: locale)
            }
        case let error as MarkdownRelativePathError:
            return switch error {
            case .invalid(let path): ScholiumL10n.string("Invalid Markdown vault-relative path: \(path)", locale: locale)
            case .markdownRequired(let path): ScholiumL10n.string("Scholium note operations require a .md path: \(path)", locale: locale)
            }
        case let error as VaultRelativeFolderPathError:
            return switch error {
            case .invalid(let path): ScholiumL10n.string("Invalid vault-relative folder path: \(path)", locale: locale)
            }
        case let error as AttachmentRelativePathError:
            return switch error {
            case .invalid(let path): ScholiumL10n.string("Invalid attachment vault-relative path: \(path)", locale: locale)
            }
        case let error as ExternalAttachmentReferenceError:
            return switch error {
            case .invalidFilename(let name): ScholiumL10n.string("Invalid external attachment filename: \(name)", locale: locale)
            }
        case let error as WindowSessionStoreError:
            return switch error {
            case .identityMismatch: ScholiumL10n.string("The stored window session does not match the requested window.", locale: locale)
            }
        case let error as MarkdownEditorSession.SessionError:
            return switch error {
            case .unavailable: ScholiumL10n.string("The Markdown editor is not ready.", locale: locale)
            case .invalidResult: ScholiumL10n.string("The Markdown editor returned an invalid document.", locale: locale)
            case .selectionTooLong: ScholiumL10n.string("Select at most 2,000 characters for one source-anchored comment.", locale: locale)
            case .staleRequest: ScholiumL10n.string("The Markdown editor request belonged to a replaced document or session.", locale: locale)
            case .citationFailed(let message): ScholiumL10n.dynamicString(message)
            case .bridgeRejected(let message):
                ScholiumL10n.string("The Markdown editor could not complete this request. Diagnostic details: \(message)", locale: locale)
            }
        case let error as DocumentControllerError:
            return switch error {
            case .saveFailed(let detail):
                ScholiumL10n.string("Scholium kept the current editor open because it could not safely save this note. \(detail)", locale: locale)
            case .editorUnavailable:
                ScholiumL10n.string("Scholium kept the current editor open because it could not retrieve the complete Markdown buffer.", locale: locale)
            case .changedDuringSave:
                ScholiumL10n.string("Scholium kept the current editor open because the note continued changing while it was being saved.", locale: locale)
            case .documentUnavailable:
                ScholiumL10n.string(
                    "Scholium kept the exact editor buffer open because this document is no longer available through the active Triptych.", locale: locale)
            }
        default:
            return error.localizedDescription
        }
    }

    static func registrySummary(_ health: WorkspaceRegistryHealth, locale: Locale = .current) -> String {
        switch health {
        case .healthy:
            ScholiumL10n.string("The Triptych registry is available.", locale: locale)
        case .malformedCurrentSchema:
            ScholiumL10n.string("The Triptych registry is damaged and needs to be preserved before relinking.", locale: locale)
        case .unsupportedNewerSchema:
            ScholiumL10n.string("The Triptych registry was created by a newer version of Scholium.", locale: locale)
        case .ioFailure:
            ScholiumL10n.string("Scholium could not read the Triptych registry.", locale: locale)
        }
    }

    static func registryDetails(_ health: WorkspaceRegistryHealth, locale: Locale = .current) -> String {
        switch health {
        case .healthy:
            ScholiumL10n.string("The registry file is readable and uses the supported schema.", locale: locale)
        case .malformedCurrentSchema(let reason):
            ScholiumL10n.string("The registry could not be decoded as the supported schema. \(reason)", locale: locale)
        case .unsupportedNewerSchema(let version):
            ScholiumL10n.string("The registry uses schema \(String(version)), but this Scholium version supports an earlier schema.", locale: locale)
        case .ioFailure(let reason):
            ScholiumL10n.string("The registry could not be read. \(reason)", locale: locale)
        }
    }

    private static func roleName(_ role: VaultRole, locale: Locale) -> String {
        switch role {
        case .sourceCorpus: ScholiumL10n.string("Analyses", locale: locale)
        case .topicKnowledge: ScholiumL10n.string("Topics", locale: locale)
        case .draftProject: ScholiumL10n.string("Works", locale: locale)
        case .other: ScholiumL10n.string("Other", locale: locale)
        }
    }

    private static func oldSettingsMessage(version: Int?, locale: Locale) -> String {
        if let version {
            return ScholiumL10n.string(
                "The portable Triptych settings use an unsupported old schema (\(String(version))). Their exact bytes were preserved.", locale: locale)
        }
        return ScholiumL10n.string("The portable Triptych settings have no schema version. Their exact bytes were preserved.", locale: locale)
    }

    private static func preflightMessage(note: VaultQualifiedNoteID?, detail: String, locale: Locale) -> String {
        if let note {
            return ScholiumL10n.string("Scholium did not change any files because \(note.relativePath) failed preflight: \(detail)", locale: locale)
        }
        return ScholiumL10n.string("Scholium did not change any files because preflight failed: \(detail)", locale: locale)
    }
}
