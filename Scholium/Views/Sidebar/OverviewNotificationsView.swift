import ScholiumContracts
import SwiftUI

/// Borrows the existing notification session; the sidebar owns no second queue.
struct OverviewNotificationsView: View {
    @ObservedObject var session: AttentionPopoverSession
    let scope: VaultQualifiedNoteID
    let open: () -> Void
    @Environment(\.locale) private var locale
    @AppStorage(AttentionPreferences.dismissalLedgerKey) private var dismissalLedgerData = Data()

    var body: some View {
        let summary = session.noteSummary(
            for: scope,
            ledger: AttentionPreferences.decodeLedger(dismissalLedgerData),
            locale: locale
        )
        if let summary {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "bell").accessibilityHidden(true)
                    Text(summary.message).multilineTextAlignment(.leading).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if summary.count > 0 {
                        Text(summary.count.formatted()).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color).accessibilityHidden(true)
                }
                .font(ScholiumTypography.interface(.control))
                .foregroundStyle(ScholiumNativeColorRole.label.color)
                .padding(.vertical, 4)
            }
            .buttonStyle(.accessoryBar)
            .help(summary.message)
            .accessibilityLabel(Text("Notifications"))
            .accessibilityValue(summary.message + ", " + summary.count.formatted())
            .accessibilityIdentifier("scholium.researchOverview.notifications")
            .scholiumAttentionPopover(anchor: .inspector, session: session)
        }
    }
}
