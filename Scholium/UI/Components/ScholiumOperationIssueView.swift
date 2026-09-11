import SwiftUI

/// Persistent feedback for an operation in this window. No global overlay or expiry.
struct ScholiumOperationIssueView: View {
    let issue: WindowOperationIssue
    let refresh: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                issue.message, systemImage: issue.kind == .error ? "xmark.octagon" : (issue.kind == .information ? "info.circle" : "exclamationmark.triangle")
            )
            .font(ScholiumTypography.interface(.body))
            .scholiumForeground(issue.kind == .error ? .destructive : (issue.kind == .information ? .information : .attention))
            if let detail = issue.detail {
                Text(detail).font(ScholiumTypography.interface(.small)).textSelection(.enabled)
            }
            HStack {
                if issue.offersRefresh { Button("Retry Refresh", action: refresh) }
                Button("Dismiss", action: dismiss)
            }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.operationIssue")
    }
}
