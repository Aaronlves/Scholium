import Foundation
import ScholiumContracts
import SwiftUI

/// Presentation of one retained report. It owns no child runtime or live status.
struct AgentChatDelegationView: View {
    @Environment(\.locale) private var locale
    let report: AgentChatDelegation
    let operationStatus: AgentChatActivity.Status
    var openAgent: ((String) -> Void)? = nil
    var canOpenAgent = true
    var expansion: Binding<Bool>? = nil
    @State private var localExpansion = false

    var body: some View {
        let presentation = AgentChatDelegationPresentation(report: report, operationStatus: operationStatus, locale: locale)
        DisclosureGroup(isExpanded: expansion ?? $localExpansion) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                reportDetails
            }
            .disclosureGroupStyle(AgentChatDisclosureStyle())
        } label: {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(verbatim: presentation.summary).lineLimit(2)
                if let status = presentation.visibleStatus {
                    Text(verbatim: status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .help(Text(verbatim: presentation.summary))
            .accessibilityElement(children: .combine)
        }
        .disclosureGroupStyle(AgentChatDisclosureStyle(symbol: "person.2"))
        .accessibilityIdentifier("scholium.chat.delegation")
    }

    @ViewBuilder private var reportDetails: some View {
        if let prompt = report.prompt, !prompt.isEmpty {
            DisclosureGroup {
                Text(verbatim: prompt).textSelection(.enabled)
            } label: {
                Text("Delegated Request", bundle: .module)
            }
        }
        if report.targets.isEmpty {
            Text("No Agents Reported", bundle: .module).foregroundStyle(.secondary)
        } else {
            Text("Reported Agent States", bundle: .module).font(.caption).foregroundStyle(.secondary)
            ForEach(report.targets) { target in
                let name = AgentChatDelegationPresentation.name(for: target) ?? target.id
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    if let openAgent {
                        Button {
                            openAgent(target.id)
                        } label: {
                            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                Text(verbatim: name)
                                Image(systemName: "chevron.forward").font(.caption).accessibilityHidden(true)
                            }
                            .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canOpenAgent)
                        .help(Text(verbatim: name))
                        .accessibilityLabel(Text(ScholiumL10n.string("Open Agent: \(name)", locale: locale)))
                        .accessibilityValue(target.state?.label(locale: locale) ?? ScholiumL10n.string("State Unavailable", locale: locale))
                        .accessibilityIdentifier("scholium.chat.delegation.open.\(target.id)")
                    } else {
                        Text(verbatim: name).textSelection(.enabled)
                    }
                    Text(target.state?.label(locale: locale) ?? ScholiumL10n.string("State Unavailable", locale: locale)).foregroundStyle(.secondary)
                    if let message = target.message, !message.isEmpty {
                        DisclosureGroup {
                            Text(verbatim: message).textSelection(.enabled)
                        } label: {
                            Text("Agent Report", bundle: .module)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        DisclosureGroup {
            LabeledContent(ScholiumL10n.string("Operation", locale: locale)) {
                Text(verbatim: report.operation.rawValue).textSelection(.enabled)
            }
            LabeledContent(ScholiumL10n.string("Status", locale: locale)) {
                Text(operationStatus.label(locale: locale))
            }
            LabeledContent(ScholiumL10n.string("From Agent", locale: locale)) {
                Text(verbatim: report.senderThreadID).textSelection(.enabled)
            }
            ForEach(report.targets) { target in
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(verbatim: target.id).monospaced().textSelection(.enabled)
                    if let path = target.path {
                        Text(verbatim: path).textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        } label: {
            Text("Details", bundle: .module)
        }
    }
}

/// A compact account of one observation, without inferring an Agent's outcome
/// from the coordination call's outcome or exposing opaque IDs as task names.
struct AgentChatDelegationPresentation {
    let report: AgentChatDelegation
    let operationStatus: AgentChatActivity.Status
    var locale: Locale = .current

    static func name(for target: AgentChatDelegation.Target) -> String? {
        guard let path = target.path?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty, path != target.id, UUID(uuidString: path) == nil
        else { return nil }
        return path
    }

    var summary: String {
        let target: String
        if report.targets.count == 1, let name = Self.name(for: report.targets[0]) {
            target = name
        } else if report.targets.isEmpty {
            target = ScholiumL10n.string("No Agents Reported", locale: locale)
        } else {
            target = ScholiumL10n.string("\(report.targets.count) agents", locale: locale)
        }
        return operationLabel + " · " + target
    }

    var visibleStatus: String? {
        var labels: [String] = []
        // A completed wait/message/spawn call says nothing about completion of
        // its targets. Keep the exact call outcome in Details instead.
        if operationStatus != .completed { labels.append(operationStatus.label(locale: locale)) }
        var issues: [String] = []
        for target in report.targets {
            let issue: String
            switch target.state {
            case .some(let state) where state == .errored || state == .notFound || state == .interrupted:
                issue = state.label(locale: locale)
            case nil: issue = ScholiumL10n.string("State Unavailable", locale: locale)
            default: continue
            }
            if !issues.contains(issue) { issues.append(issue) }
        }
        if !issues.isEmpty {
            labels.append(ScholiumL10n.string("Reported Agent States", locale: locale) + ": " + issues.joined(separator: ", "))
        }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    var operationLabel: String {
        let key: String.LocalizationValue
        switch report.operation {
        case .spawnAgent: key = "Start Agent"
        case .sendInput, .sendMessage: key = "Message Agent"
        case .resumeAgent: key = "Resume Agent"
        case .wait: key = "Wait for Agents"
        case .closeAgent: key = "Close Agent"
        case .followupTask: key = "Assign Follow-up"
        case .interruptAgent: key = "Interrupt Agent"
        case .listAgents: key = "List Agents"
        case .started: key = "Agent Started"
        case .interacted: key = "Agent Interaction"
        case .interrupted: key = "Agent Interrupted"
        case .completed: key = "Agent Finished"
        }
        return ScholiumL10n.string(key, locale: locale)
    }

}
