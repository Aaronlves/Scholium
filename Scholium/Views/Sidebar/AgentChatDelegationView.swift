import ScholiumContracts
import SwiftUI

/// Presentation of one retained report. It owns no child runtime or live status.
struct AgentChatDelegationView: View {
  @Environment(\.locale) private var locale
  let report: AgentChatDelegation
  let operationStatus: AgentChatActivity.Status
  var openAgent: ((String) -> Void)? = nil
  var canOpenAgent = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Label(operationLabel, systemImage: "person.2")
        Spacer(minLength: 0)
        Text(operationStatus.label(locale: locale)).foregroundStyle(.secondary)
      }
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
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
              Text(verbatim: target.path ?? target.id).textSelection(.enabled)
              Spacer(minLength: 8)
              if let openAgent {
                Button { openAgent(target.id) } label: { Text("Open Agent", bundle: .module) }
                  .disabled(!canOpenAgent)
                  .accessibilityValue(target.path ?? target.id)
              }
            }
            Text(stateLabel(target.state)).foregroundStyle(.secondary)
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
        LabeledContent(ScholiumL10n.string("From Agent", locale: locale)) {
          Text(verbatim: report.senderThreadID).textSelection(.enabled)
        }
        ForEach(report.targets) { target in
          Text(verbatim: target.id).monospaced().textSelection(.enabled)
        }
      } label: {
        Text("Details", bundle: .module)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var operationLabel: String {
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

  private func stateLabel(_ state: AgentChatDelegation.State?) -> String {
    let key: String.LocalizationValue
    switch state {
    case .pendingInit: key = "Starting"
    case .running: key = "In Progress"
    case .interrupted: key = "Interrupted"
    case .completed: key = "Completed"
    case .errored: key = "Failed"
    case .shutdown: key = "Closed"
    case .notFound: key = "Agent Not Found"
    case nil: key = "State Unavailable"
    }
    return ScholiumL10n.string(key, locale: locale)
  }
}
