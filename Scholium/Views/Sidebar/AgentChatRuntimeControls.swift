import ScholiumContracts
import SwiftUI

struct AgentChatModelMenu: View {
  @Environment(\.locale) private var locale
  let models: [AgentChatModel]
  let preferences: AgentChatPreferences
  let selectedModel: AgentChatModel?
  let isEnabled: Bool
  let selectModel: (String?) -> Void
  let selectEffort: (String?) -> Void

  var body: some View {
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
      if let selectedModel, !selectedModel.efforts.isEmpty {
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
      }
    } label: {
      Text(
        preferences.model == nil
          ? ScholiumL10n.string("Runtime Default", locale: locale)
          : selectedModel?.name ?? preferences.model ?? ""
      )
      .lineLimit(1)
    }
    .disabled(!isEnabled)
    .accessibilityLabel("Model and Reasoning")
    .accessibilityValue(
      [
        selectedModel?.name ?? preferences.model ?? ScholiumL10n.string("Runtime Default", locale: locale),
        preferences.effort.map(AgentChatControlLabels.effort),
      ].compactMap { $0 }.joined(separator: ", "))
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
  @State private var isExpanded: Bool

  init(plan: AgentChatPlan) {
    self.plan = plan
    _isExpanded = State(initialValue: plan.runStatus.isActive)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
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
        Label("Plan", systemImage: "list.bullet")
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
}

struct AgentChatContextView: View {
  let usage: AgentChatContextUsage?
  let quotas: [AgentChatQuota]
  let quotaError: String?
  let isRefreshing: Bool
  let canRefresh: Bool
  let canCompact: Bool
  let compact: () -> Void
  let refresh: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedTab = 0

  var body: some View {
    TabView(selection: $selectedTab) {
      VStack(alignment: .leading, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let usage {
              if let fraction = AgentChatContextPresentation.fraction(usage) {
                HStack {
                  Text("Last reported context use")
                  Spacer()
                  Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
                ProgressView(value: fraction)
                  .tint(.secondary).accessibilityLabel("Context Usage")
                  .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
              } else {
                Text("Context size unavailable").foregroundStyle(.secondary)
              }
              DisclosureGroup("Token details") {
                LabeledContent {
                  Text(usage.lastTurnTokens.formatted()).monospacedDigit()
                } label: {
                  Text("Latest Turn", bundle: .module)
                }
                .accessibilityElement(children: .combine)
                if let capacity = usage.capacity {
                  LabeledContent {
                    Text(capacity.formatted()).monospacedDigit()
                  } label: {
                    Text("Context Window", bundle: .module)
                  }
                  .accessibilityElement(children: .combine)
                }
                LabeledContent {
                  Text(usage.totalTokens.formatted()).monospacedDigit()
                } label: {
                  Text("Total Tokens", bundle: .module)
                }
                .accessibilityElement(children: .combine)
              }
            } else {
              Text("Not Available", bundle: .module).foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Button(action: compact) { Text("Compact Context", bundle: .module) }.disabled(!canCompact)
      }.padding(12)
        .tabItem { Text("Context", bundle: .module) }.tag(0)
      VStack(alignment: .leading, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let quotaError {
              Text(quotaError).foregroundStyle(.secondary)
            } else if quotas.isEmpty {
              Text("Not Available", bundle: .module).foregroundStyle(.secondary)
            }
            ForEach(quotas) { quota in
              VStack(alignment: .leading, spacing: 8) {
                Text(quota.name).font(.subheadline)
                if let primary = quota.primary { quotaWindow(primary) }
                if let secondary = quota.secondary { quotaWindow(secondary) }
                if quota.primary == nil && quota.secondary == nil {
                  Text("Not Available", bundle: .module).foregroundStyle(.secondary)
                }
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Button(action: refresh) {
          Label {
            Text("Refresh", bundle: .module)
          } icon: {
            Image(systemName: "arrow.clockwise")
          }
        }
        .disabled(isRefreshing || !canRefresh)
      }.padding(12)
        .tabItem { Text("Account Usage", bundle: .module) }.tag(1)
    }
    .tabViewStyle(.grouped)
    .transaction {
      if reduceMotion {
        $0.animation = nil
        $0.disablesAnimations = true
      }
    }
    .font(.callout).padding(16).frame(width: 320, height: selectedTab == 0 ? 240 : 300).tint(nil as Color?)
  }

  private func quotaWindow(_ window: AgentChatQuota.Window) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if let minutes = window.durationMinutes {
          Text("\(minutes) min")
        }
        Spacer()
        Text("\(window.usedPercent)% used")
      }
      ProgressView(value: Double(min(window.usedPercent, 100)), total: 100)
        .accessibilityLabel("Account Usage")
        .accessibilityValue(Text("\(window.usedPercent)% used"))
      if let reset = window.resetsAt {
        LabeledContent("Resets", value: reset.formatted(date: .abbreviated, time: .shortened))
          .foregroundStyle(.secondary)
      }
    }
  }
}
