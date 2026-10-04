import AppKit
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
                            .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxHeight: 196)
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize)
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
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .presentationSizing(.fitted)
        .background(AccountUsageSheetFit(quotas: quotas, error: error, isRefreshing: isRefreshing))
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

/// Keep the existing native sheet fitted as runtime content arrives or clears.
private struct AccountUsageSheetFit: NSViewRepresentable {
    let quotas: [AgentChatQuota]
    let error: String?
    let isRefreshing: Bool

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak view] _ in if let view { Self.refit(view) } }
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) { Self.refit(view) }

    static func dismantleNSView(_ view: WindowAttachmentView, coordinator: ()) { view.onWindowAttachment = nil }

    private static func refit(_ view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, window.sheetParent != nil, let content = window.contentView else { return }
            content.layoutSubtreeIfNeeded()
            let size = content.fittingSize
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                abs(content.bounds.width - size.width) > 0.5 || abs(content.bounds.height - size.height) > 0.5
            else { return }
            window.setContentSize(size)
        }
    }
}
