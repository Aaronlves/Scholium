import ScholiumContracts
import SwiftUI

struct AgentChatConfigurationMenu: View {
    @Environment(\.locale) private var locale
    let models: [AgentChatModel]
    let preferences: AgentChatPreferences
    let selectedModel: AgentChatModel?
    var selectedEffort: String? = nil
    let permission: AgentChatPermission
    let isEnabled: Bool
    let canSelectModel: Bool
    let selectModel: (String?) -> Void
    let selectEffort: (String?) -> Void
    let selectPermission: (AgentChatPermission) -> Void
    let selectWebSearch: (AgentChatPreferences.WebSearch) -> Void

    var body: some View {
        Menu {
            Menu {
                Picker(
                    "Model",
                    selection: Binding(
                        get: { preferences.model ?? "" },
                        set: { selectModel($0.isEmpty ? nil : $0) })
                ) {
                    Text("Runtime Default", bundle: .module).tag("")
                    if let model = preferences.model, !models.contains(where: { $0.model == model }) {
                        Text("Unavailable: \(model)").tag(model)
                    }
                    ForEach(models) { model in Text(model.name).tag(model.model) }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Model", bundle: .module)
            }.disabled(!canSelectModel)
            if let selectedModel, !selectedModel.efforts.isEmpty {
                Menu {
                    Picker(
                        "Reasoning",
                        selection: Binding(
                            get: { preferences.effort ?? "" },
                            set: { selectEffort($0.isEmpty ? nil : $0) })
                    ) {
                        Text("Runtime Default", bundle: .module).tag("")
                        ForEach(selectedModel.efforts, id: \.self) { effort in
                            Text(AgentChatControlLabels.effort(effort)).tag(effort)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("Reasoning", bundle: .module)
                }.disabled(!canSelectModel)
            }
            Divider()
            Menu {
                Picker("Permission", selection: Binding(get: { permission }, set: selectPermission)) {
                    Text("Ask for Approval", bundle: .module).tag(AgentChatPermission.ask)
                    Text("Full Access", bundle: .module).tag(AgentChatPermission.fullAccess)
                }
                .pickerStyle(.inline)
            } label: {
                Text("Permission", bundle: .module)
            }
            Menu {
                Picker("Web Search", selection: Binding(get: { preferences.webSearch }, set: selectWebSearch)) {
                    ForEach(AgentChatPreferences.WebSearch.allCases, id: \.self) { mode in
                        Text(AgentChatControlLabels.webSearch(mode)).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Web Search", bundle: .module)
            }
        } label: {
            Text(verbatim: modelLabel).lineLimit(1).truncationMode(.tail)
                .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
        }
        .scholiumContentActionMenu()
        .disabled(!isEnabled)
        .help(Text("Chat Settings", bundle: .module) + Text(verbatim: ": " + modelLabel))
        .accessibilityLabel(Text("Chat Settings", bundle: .module))
        .accessibilityIdentifier("scholium.chat.configuration")
        .accessibilityValue(
            [
                selectedModel?.name ?? preferences.model ?? ScholiumL10n.string("Runtime Default", locale: locale),
                (selectedEffort ?? preferences.effort).map(AgentChatControlLabels.effort),
                permissionLabel,
                AgentChatControlLabels.webSearch(preferences.webSearch),
            ].compactMap { $0 }.joined(separator: ", "))
    }

    private var permissionLabel: String {
        permission == .ask
            ? ScholiumL10n.string("Ask for Approval", locale: locale)
            : ScholiumL10n.string("Full Access", locale: locale)
    }

    private var modelLabel: String {
        [
            selectedModel?.name ?? preferences.model ?? ScholiumL10n.string("Runtime Default", locale: locale),
            (selectedEffort ?? preferences.effort).map(AgentChatControlLabels.effort),
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

enum AgentChatControlLabels {
    static func effort(_ value: String) -> String {
        switch value {
        case "none": String(localized: "None", bundle: .module)
        case "minimal": String(localized: "Minimal", bundle: .module)
        case "low": String(localized: "Low", bundle: .module)
        case "medium": String(localized: "Medium", bundle: .module)
        case "high": String(localized: "High", bundle: .module)
        case "xhigh": String(localized: "Extra High", bundle: .module)
        case "max": String(localized: "Maximum", bundle: .module)
        case "ultra": String(localized: "Ultra", bundle: .module)
        default: value
        }
    }

    static func webSearch(_ value: AgentChatPreferences.WebSearch) -> String {
        switch value {
        case .runtimeDefault: String(localized: "Runtime Default", bundle: .module)
        case .disabled: String(localized: "Off", bundle: .module)
        case .cached: String(localized: "Cached", bundle: .module)
        case .live: String(localized: "Live", bundle: .module)
        }
    }
}

struct AgentChatPlanView: View {
    let plan: AgentChatPlan
    @Environment(\.locale) private var locale
    @State private var isExpanded: Bool
    @Binding private var savedExpansion: Bool?

    init(plan: AgentChatPlan, savedExpansion: Binding<Bool?> = .constant(nil)) {
        self.plan = plan
        _savedExpansion = savedExpansion
        _isExpanded = State(initialValue: savedExpansion.wrappedValue ?? false)
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: {
                    isExpanded = $0
                    savedExpansion = $0
                })
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let explanation = plan.explanation, !explanation.isEmpty {
                    Text(explanation).foregroundStyle(.secondary).textSelection(.enabled)
                }
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                    Label {
                        Text(step.step).textSelection(.enabled)
                    } icon: {
                        Image(
                            systemName: step.status == .completed
                                ? "checkmark.circle"
                                : step.status == .inProgress ? "circle.dotted" : "circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(
                        step.status == .completed
                            ? String(localized: "Completed", bundle: .module)
                            : step.status == .inProgress && plan.runStatus.isActive
                                ? String(localized: "In Progress", bundle: .module)
                                : step.status == .inProgress
                                    ? String(localized: "Not Confirmed", bundle: .module)
                                    : String(localized: "Pending", bundle: .module))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        } label: {
            HStack {
                Label {
                    if !isExpanded, plan.runStatus.isActive,
                        let current = plan.steps.first(where: { $0.status == .inProgress })
                    {
                        Text(verbatim: ScholiumL10n.string("Plan", locale: locale) + ": " + current.step).lineLimit(2)
                    } else {
                        Text("Plan", bundle: .module)
                    }
                } icon: {
                    Image(systemName: ScholiumSidebarItem.plan.symbol)
                }
                Spacer(minLength: 6)
                Text("\(plan.steps.filter { $0.status == .completed }.count)/\(plan.steps.count)")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("Completed steps")
                if plan.runStatus == .interrupted || plan.runStatus == .failed {
                    Text(plan.runStatus.label).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }
}

enum AgentChatContextPresentation {
    static func fraction(_ usage: AgentChatContextUsage?) -> Double? {
        guard let usage, let capacity = usage.capacity, capacity > 0, usage.lastTurnTokens >= 0 else { return nil }
        return min(1, Double(usage.lastTurnTokens) / Double(capacity))
    }

    static func summary(_ usage: AgentChatContextUsage?) -> String {
        let title = String(localized: "Last reported context use", bundle: .module)
        guard let usage, let capacity = usage.capacity, let fraction = fraction(usage) else {
            return title + "\n" + String(localized: "Context size unavailable", bundle: .module)
        }
        let used = fraction.formatted(.percent.precision(.fractionLength(0)))
        let remaining = (1 - fraction).formatted(.percent.precision(.fractionLength(0)))
        let tokens = usage.lastTurnTokens.formatted()
        let limit = capacity.formatted()
        return title + "\n"
            + String(localized: "\(used) used (\(remaining) left)", bundle: .module) + "\n"
            + String(localized: "\(tokens) / \(limit) tokens", bundle: .module)
    }
}

struct AgentChatContextView: View {
    let usage: AgentChatContextUsage?
    var ledger: AgentChatContextLedger? = nil
    let canCompact: Bool
    let compact: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            occupancy
            if usage != nil || ledger?.isEmpty == false {
                DisclosureGroup("Details") {
                    AgentChatContentScroll {
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            if let usage {
                                LabeledContent {
                                    Text(usage.totalTokens.formatted()).monospacedDigit().textSelection(.enabled)
                                } label: {
                                    Text("Total Tokens", bundle: .module)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            if let ledger, !ledger.isEmpty {
                                AgentChatContextLedgerView(ledger: ledger)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                }
            }
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button(action: compact) { Text("Compact Context", bundle: .module) }
                    .buttonStyle(.bordered)
                    .disabled(!canCompact)
            }
        }
        .font(.callout).padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: 320).fixedSize(horizontal: false, vertical: true).tint(nil as Color?)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.contextDetails")
    }

    @ViewBuilder private var occupancy: some View {
        if let usage, let capacity = usage.capacity, let fraction = AgentChatContextPresentation.fraction(usage) {
            let used = fraction.formatted(.percent.precision(.fractionLength(0)))
            let remaining = (1 - fraction).formatted(.percent.precision(.fractionLength(0)))
            HStack(alignment: .firstTextBaseline) {
                Text("\(used) used", bundle: .module).font(.title2.weight(.semibold))
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text("\(remaining) left", bundle: .module).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            ProgressView(value: fraction)
                .tint(.secondary)
                .accessibilityLabel("Last reported context use")
                .accessibilityValue(used)
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("\(usage.lastTurnTokens.formatted()) / \(capacity.formatted()) tokens", bundle: .module)
                    .monospacedDigit().textSelection(.enabled)
                Text("Last reported context use", bundle: .module)
            }
            .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Context size unavailable", bundle: .module).font(.headline)
            if let usage, usage.lastTurnTokens >= 0 {
                LabeledContent {
                    Text(usage.lastTurnTokens.formatted()).monospacedDigit().textSelection(.enabled)
                } label: {
                    Text("Latest Turn", bundle: .module)
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
