import Foundation
import ScholiumContracts

/// How the window tells a researcher that an operation needed attention,
/// without turning a durable file truth into an error.
extension WindowModel {
    func presentMarkdownImportOutcome(_ outcome: WindowMarkdownImportBatchOutcome) {
        let failureDetails = outcome.failures
            .map { "\($0.sourceName): \($0.reason)" }
            .joined(separator: " ")

        guard !outcome.documents.isEmpty else {
            let summary = String(
                localized: "No Markdown files were imported.",
                table: "Localizable",
                bundle: .module
            )
            vaultError = failureDetails.isEmpty ? summary : "\(summary) \(failureDetails)"
            return
        }

        vaultError = nil
        let successSummary = String(
            localized: "Imported \(outcome.documents.count) Markdown file\(outcome.documents.count == 1 ? "" : "s") into \(outcome.destinationName).",
            table: "Localizable",
            bundle: .module
        )
        var warnings: [String] = []
        if !outcome.failures.isEmpty {
            warnings.append(
                String(
                    localized: "Some selected files were not imported. The imported files are already committed; do not import them again.",
                    table: "Localizable",
                    bundle: .module
                ))
            warnings.append(failureDetails)
        }
        if !outcome.derivedRefreshWarnings.isEmpty {
            warnings.append(
                String(
                    localized: "Library, Search, or other derived views may be stale. Use Refresh instead of importing the files again.",
                    table: "Localizable",
                    bundle: .module
                ))
            warnings.append(outcome.derivedRefreshWarnings.joined(separator: " "))
        }
        if !outcome.identityRecoveryWarnings.isEmpty {
            warnings.append(
                String(
                    localized:
                        "The file operation completed, but stable note identity recovery is incomplete. Identity-dependent actions remain unavailable until recovery succeeds.",
                    table: "Localizable",
                    bundle: .module
                ))
            warnings.append(outcome.identityRecoveryWarnings.joined(separator: " "))
        }
        if let presentationWarning = outcome.presentationWarning {
            warnings.append(
                String(
                    localized: "This window could not refresh the imported documents. Use Refresh instead of importing the files again.",
                    table: "Localizable",
                    bundle: .module
                ))
            warnings.append(presentationWarning)
        }

        if !warnings.isEmpty {
            reportOperationIssue(([successSummary] + warnings).joined(separator: " "), kind: .warning)
        }
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        guard ScholiumPasteboardWriter.general.writeText(text) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
    }

    @discardableResult
    func reportOperationIssue(
        _ message: String,
        kind: WindowOperationIssueKind,
        detail: String? = nil,
        offersRefresh: Bool = false
    ) -> UUID {
        shellState.reportOperationIssue(message, kind: kind, detail: detail, offersRefresh: offersRefresh)
    }

    /// Presents post-commit repair truth without turning a durable file
    /// operation into a retryable failure. Returns `true` when a warning was
    /// shown so callers do not immediately add a redundant confirmation.
    @discardableResult
    func reportCommittedMutationWarnings<CommittedValue: Sendable>(
        _ outcome: WorkspaceMutationOutcome<CommittedValue>,
        presentationWarning: String? = nil
    ) -> Bool {
        reportCommittedMutationWarnings(
            derivedRefreshWarnings: outcome.derivedRefreshWarning.map { [$0] } ?? [],
            identityRecoveryWarnings: outcome.identityRecoveryWarning.map { [$0] } ?? [],
            presentationWarning: presentationWarning
        )
    }

    @discardableResult
    private func reportCommittedMutationWarnings(
        derivedRefreshWarnings: [String],
        identityRecoveryWarnings: [String],
        presentationWarning: String? = nil
    ) -> Bool {
        var messages: [String] = []
        if !derivedRefreshWarnings.isEmpty {
            messages.append(
                String(
                    localized:
                        "The file operation completed, but Library, Search, or other derived views may be stale. Use Refresh instead of repeating the action.",
                    table: "Localizable",
                    bundle: .module
                ))
            messages.append(derivedRefreshWarnings.joined(separator: " "))
        }
        if !identityRecoveryWarnings.isEmpty {
            messages.append(
                String(
                    localized:
                        "The file operation completed, but stable note identity recovery is incomplete. Identity-dependent actions remain unavailable until recovery succeeds.",
                    table: "Localizable",
                    bundle: .module
                ))
            messages.append(identityRecoveryWarnings.joined(separator: " "))
        }
        if let presentationWarning {
            messages.append(
                String(
                    localized:
                        "The file operation completed, but this window could not refresh its document view. Use Refresh instead of repeating the action.",
                    table: "Localizable",
                    bundle: .module
                ))
            messages.append(presentationWarning)
        }
        guard !messages.isEmpty else { return false }
        reportOperationIssue(
            String(localized: "The File Operation Completed with Warnings"),
            kind: .warning,
            detail: messages.joined(separator: " "),
            offersRefresh: !derivedRefreshWarnings.isEmpty || presentationWarning != nil
        )
        return true
    }
}

private enum ClipboardWorkflowError: LocalizedError {
    case copyFailed(recovery: String?)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let recovery):
            if let recovery {
                return String(localized: "macOS did not accept the text on the clipboard. \(recovery)", table: "Localizable", bundle: .module)
            }
            return String(localized: "macOS did not accept the text on the clipboard. Try copying again.", table: "Localizable", bundle: .module)
        }
    }
}
