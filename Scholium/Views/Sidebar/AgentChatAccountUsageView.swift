import ScholiumContracts
import SwiftUI

/// Runtime-reported account limits, separate from conversation context usage.
struct AgentChatAccountUsageView: View {
    let quotas: [AgentChatQuota]
    let error: String?
    let isRefreshing: Bool
    let canRefresh: Bool
    let refresh: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Text("Account Usage", bundle: .module).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    if let error {
                        Text(verbatim: error).foregroundStyle(.secondary).textSelection(.enabled)
                    } else if quotas.isEmpty && !isRefreshing {
                        Text("Not Available", bundle: .module).foregroundStyle(.secondary)
                    }
                    ForEach(quotas) { quota in
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            Text(verbatim: quota.name).font(.subheadline)
                            if let primary = quota.primary { quotaWindow(primary) }
                            if let secondary = quota.secondary { quotaWindow(secondary) }
                            if quota.primary == nil && quota.secondary == nil {
                                Text("Not Available", bundle: .module).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button(action: refresh) {
                    Label {
                        Text("Refresh", bundle: .module)
                    } icon: {
                        Image(systemName: ScholiumSidebarAction.retry.symbol)
                    }
                }
                .disabled(isRefreshing || !canRefresh)
                if isRefreshing {
                    if !reduceMotion {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                    }
                    Text("Loading…", bundle: .module).foregroundStyle(.secondary)
                }
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Button(action: close) { Text("Done", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.callout)
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: 360, height: 300)
        .tint(nil as Color?)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.accountUsage")
    }

    private func quotaWindow(_ window: AgentChatQuota.Window) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack {
                if let minutes = window.durationMinutes {
                    Text("\(minutes) min", bundle: .module)
                }
                Spacer()
                Text("\(window.usedPercent)% used", bundle: .module).monospacedDigit()
            }
            ProgressView(value: Double(min(window.usedPercent, 100)), total: 100)
                .accessibilityLabel(Text("Account Usage", bundle: .module))
                .accessibilityValue(Text("\(window.usedPercent)% used", bundle: .module))
            if let reset = window.resetsAt {
                LabeledContent {
                    Text(reset, format: .dateTime.year().month().day().hour().minute())
                } label: {
                    Text("Resets", bundle: .module)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
