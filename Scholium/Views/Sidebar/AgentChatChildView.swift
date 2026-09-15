import ScholiumContracts
import SwiftUI

/// Read-only monitoring of one Agent; execution and parent navigation retain their owners.
struct AgentChatChildView: View {
    @ObservedObject var child: AgentChatChildController
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openReference: (URL) -> Bool
    var openAgent: ((String, String) -> Void)? = nil
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            header
            operationFeedback
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    if child.snapshot?.page.nextCursor != nil {
                        Button {
                            child.loadEarlier()
                        } label: {
                            Text("Load Earlier Activity", bundle: .module)
                        }.disabled(!child.canLoadEarlier)
                    }
                    if child.snapshot != nil && child.messages.isEmpty {
                        Text("No Public Activity", bundle: .module).foregroundStyle(.secondary)
                    }
                    ForEach(child.messages) { presented in
                        message(presented)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                .padding(.trailing, ScholiumGrid.Spacing.labelAccessoryGap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("scholium.chat.childActivity")
            Divider()
            details
            HStack {
                if child.hasParent {
                    Button {
                        child.openParent()
                        close()
                    } label: {
                        Text("Open Parent", bundle: .module)
                    }
                }
                Spacer()
                Button(action: close) { Text("Done", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding().frame(minWidth: 420, idealWidth: 600, minHeight: 420, idealHeight: 600)
        .task { if child.snapshot == nil && child.error == nil { child.refresh() } }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if AgentChatReference.parse(url) != nil { return openReference(url) ? .handled : .discarded }
                if let destination = AgentChatReplySource.externalURL(url) { return .systemAction(destination) }
                return .discarded
            })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(verbatim: child.snapshot?.metadata.name ?? ScholiumL10n.string("Agent", locale: locale))
                .font(.title3.weight(.semibold)).textSelection(.enabled)
            Text(verbatim: child.parentTitle).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).help(Text(verbatim: child.parentTitle))
            HStack(alignment: .firstTextBaseline) {
                if let snapshot = child.snapshot {
                    Text(ScholiumL10n.string("Last Observed: \(status(snapshot))", locale: locale))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Button {
                    child.refresh()
                } label: {
                    Text("Refresh", bundle: .module)
                }
                .disabled(!child.canRefresh)
                Button {
                    child.stop()
                } label: {
                    Text("Stop Agent", bundle: .module)
                }
                .disabled(!child.canStop)
            }
        }
    }

    @ViewBuilder private var operationFeedback: some View {
        if let progressLabel {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if !reduceMotion { ProgressView().controlSize(.small).accessibilityHidden(true) }
                Text(progressLabel)
            }
            .font(.callout).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
        if child.isDisconnected {
            Text("Reconnect and reopen this Agent.", bundle: .module).foregroundStyle(.secondary)
        }
        if let error = child.error { Text(error.label(locale: locale)).textSelection(.enabled) }
        if child.pendingStop != nil {
            Label {
                Text("Interruption Not Yet Confirmed", bundle: .module)
            } icon: {
                Image(systemName: "clock")
            }
            .foregroundStyle(.secondary)
        }
    }

    private func message(_ presented: AgentChatChildController.Message) -> some View {
        let message = presented.value
        return VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            if let activity = message.activity, let report = activity.delegation {
                AgentChatDelegationView(
                    report: report, operationStatus: activity.status,
                    openAgent: openAgent.map { open in { target in open(target, presented.id) } },
                    canOpenAgent: child.canInspectReports)
            } else if let activity = message.activity {
                DisclosureGroup {
                    if !activity.subject.isEmpty { Text(verbatim: activity.subject).monospaced().textSelection(.enabled) }
                    if !activity.detail.isEmpty { Text(verbatim: activity.detail).monospaced().textSelection(.enabled) }
                } label: {
                    HStack {
                        Text(AgentChatActivityProjection.title(activity, locale: locale))
                        Spacer()
                        Text(activity.status.label(locale: locale)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(message.role == .user ? ScholiumL10n.string("Request", locale: locale) : ScholiumL10n.string("Agent", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                AgentChatMarkdown(text: message.text)
                    .font(ScholiumChatAppearance.messageFont)
                    .foregroundStyle(ScholiumChatAppearance.messageForeground)
            }
            if presented.hasAdditionalMaterial {
                Text("Additional material was supplied with this request.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var details: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                LabeledContent {
                    Text(verbatim: child.childID).monospaced().textSelection(.enabled)
                } label: {
                    Text("Agent", bundle: .module)
                }
                LabeledContent {
                    Text(verbatim: child.parentID).monospaced().textSelection(.enabled)
                } label: {
                    Text("Parent Agent", bundle: .module)
                }
                if let role = child.snapshot?.metadata.role { Text(verbatim: role).foregroundStyle(.secondary) }
                if let observedAt = child.observedAt {
                    LabeledContent {
                        Text(observedAt, format: .dateTime.year().month().day().hour().minute().second())
                    } label: {
                        Text("Last Observed", bundle: .module)
                    }
                }
            }.font(.caption)
        } label: {
            Text("Details", bundle: .module)
        }
    }

    private var progressLabel: String? {
        switch child.work {
        case .refresh: ScholiumL10n.string("Reading Agent State…", locale: locale)
        case .loadEarlier: ScholiumL10n.string("Loading Earlier Activity…", locale: locale)
        case .stop:
            child.pendingStop == nil
                ? ScholiumL10n.string("Checking Active Turn…", locale: locale)
                : ScholiumL10n.string("Confirming Interruption…", locale: locale)
        case nil: nil
        }
    }

    private func status(_ snapshot: AgentChatChildHistory.Snapshot) -> String {
        let metadata = snapshot.metadata
        let key: String.LocalizationValue
        switch metadata.status {
        case .notLoaded: key = "Not Running"
        case .idle:
            switch snapshot.page.turns.last?.status {
            case .completed: key = "Completed"
            case .interrupted: key = "Interrupted"
            case .failed: key = "Failed"
            default: key = "Idle"
            }
        case .systemError: key = "Runtime Error"
        case .active: key = "In Progress"
        }
        var values = [ScholiumL10n.string(key, locale: locale)]
        if metadata.activeFlags.contains("waitingOnApproval") {
            values.append(ScholiumL10n.string("Waiting for Approval", locale: locale))
        }
        if metadata.activeFlags.contains("waitingOnUserInput") {
            values.append(ScholiumL10n.string("Input Requested", locale: locale))
        }
        return values.joined(separator: " · ")
    }
}

struct AgentChatCoordinationReferenceView: View {
    let target: AgentChatCoordinationTarget
    let inspect: () -> Void
    let openParent: (() -> Void)?
    var remove: (() -> Void)? = nil
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 6) {
            Button(action: inspect) {
                Label {
                    Text(ScholiumL10n.string("Agent: \(target.name ?? target.childThreadID)", locale: locale))
                } icon: {
                    Image(systemName: "person.2")
                }
                .lineLimit(2)
                .scholiumContentControlInk(
                    resting: .secondaryText,
                    emphasized: .accent
                )
            }
            .buttonStyle(.plain)
            .scholiumActivationPointer()
            .scholiumContentControlPointerFeedback(
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            Menu {
                Button(action: inspect) { Text("Open Agent", bundle: .module) }
                if let openParent { Button(action: openParent) { Text("Open Parent", bundle: .module) } }
                if let remove { Button(action: remove) { Text("Remove Agent Target", bundle: .module) } }
            } label: {
                ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.more.symbol, placement: .action)
                    .accessibilityLabel(Text("Agent Target Actions", bundle: .module))
            }
            .scholiumContentActionMenu().menuIndicator(.hidden).fixedSize()
            .help(Text("Agent Target Actions", bundle: .module))
            .accessibilityLabel(Text("Agent Target Actions", bundle: .module))
        }
        .font(.caption).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
    }
}
