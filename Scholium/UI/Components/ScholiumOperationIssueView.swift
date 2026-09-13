import SwiftUI

/// Persistent feedback for an operation in this window. No global overlay or expiry.
struct ScholiumOperationIssueView: View {
    let issue: WindowOperationIssue
    let refresh: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ScholiumDocumentStatusNotice(
            issue.message,
            detail: issue.detail ?? "",
            kind: issue.kind == .error ? .destructive : (issue.kind == .information ? .information : .attention)
        ) {
            if issue.offersRefresh { Button("Retry Refresh", action: refresh) }
            Button("Dismiss", action: dismiss)
        }
        .accessibilityIdentifier("scholium.operationIssue")
    }
}
