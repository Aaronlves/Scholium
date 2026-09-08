import ScholiumContracts
import SwiftUI

struct AgentChatChildView: View {
  @ObservedObject var child: AgentChatChildController
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var messageIsFocused = false
  @State private var selectedTab = 0
  let openReference: (URL) -> Bool
  var openAgent: ((String, String) -> Void)? = nil
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: child.snapshot?.metadata.name ?? ScholiumL10n.string("Agent", locale: locale)).font(.headline)
          Text(verbatim: child.parentTitle).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        if child.isWorking {
          if reduceMotion { Image(systemName: "ellipsis") } else { ProgressView().controlSize(.small) }
        }
        Button {
          child.refresh()
        } label: {
          Text("Refresh", bundle: .module)
        }.disabled(child.isWorking || child.isDisconnected)
      }
      if let snapshot = child.snapshot {
        let observed = status(snapshot)
        Text(child.isDisconnected ? ScholiumL10n.string("Last Observed: \(observed)", locale: locale) : observed)
          .foregroundStyle(.secondary)
        if let role = snapshot.metadata.role { Text(verbatim: role).foregroundStyle(.secondary) }
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
      TabView(selection: $selectedTab) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if child.snapshot?.page.nextCursor != nil {
              Button {
                child.loadEarlier()
              } label: {
                Text("Load Earlier Activity", bundle: .module)
              }
              .disabled(child.isWorking || child.isDisconnected)
            }
            if child.snapshot != nil && child.messages.isEmpty {
              Text("No Public Activity", bundle: .module).foregroundStyle(.secondary)
            }
            ForEach(child.messages) { presented in
              let message = presented.value
              VStack(alignment: .leading, spacing: 4) {
                Text(
                  message.role == .user
                    ? ScholiumL10n.string("Request", locale: locale)
                    : message.role == .assistant
                      ? ScholiumL10n.string("Agent", locale: locale)
                      : message.activity?.kind.label(locale: locale) ?? ""
                )
                .font(.caption).foregroundStyle(.secondary)
                if let activity = message.activity, let report = activity.delegation {
                  AgentChatDelegationView(report: report, operationStatus: activity.status,
                    openAgent: openAgent.map { open in { target in open(target, presented.id) } },
                    canOpenAgent: child.canInspectReports)
                } else if let activity = message.activity {
                  Text(activity.status.label(locale: locale)).foregroundStyle(.secondary)
                  if !activity.subject.isEmpty { Text(verbatim: activity.subject).textSelection(.enabled) }
                  if !activity.detail.isEmpty {
                    DisclosureGroup {
                      Text(verbatim: activity.detail).monospaced().textSelection(.enabled)
                    } label: {
                      Text("Operation Details", bundle: .module)
                    }
                  }
                } else {
                  AgentChatMarkdown(text: message.text)
                }
                if presented.hasAdditionalMaterial {
                  Text("Additional material was supplied with this request.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
        }
        .padding(12)
        .tabItem { Text("Agent Activity", bundle: .module) }.tag(0)
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            LabeledContent {
              Text(verbatim: child.childID).monospaced().textSelection(.enabled)
            } label: {
              Text("Agent", bundle: .module)
            }
            .accessibilityElement(children: .combine)
            LabeledContent {
              Text(verbatim: child.parentID).monospaced().textSelection(.enabled)
            } label: {
              Text("Parent Agent", bundle: .module)
            }
            .accessibilityElement(children: .combine)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .tabItem { Text("Details", bundle: .module) }.tag(1)
      }
      .tabViewStyle(.grouped).frame(minHeight: 160)
      .transaction {
        if reduceMotion {
          $0.animation = nil
          $0.disablesAnimations = true
        }
      }
      if child.hasParent {
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Ask Parent", bundle: .module).font(.subheadline)
              Spacer()
              Button {
                child.openParent()
                close()
              } label: {
                Text("Open Parent", bundle: .module)
              }
            }
            AgentChatComposerInput(
              text: Binding(get: { child.draft }, set: child.editDraft),
              isFocused: $messageIsFocused, conversationID: child.id, isEnabled: child.canEdit,
              submit: child.askParent
            )
            .overlay(alignment: .topLeading) {
              if child.draft.isEmpty {
                Text("Message", bundle: .module).foregroundStyle(Color(nsColor: .placeholderTextColor))
                  .padding(.horizontal, 9).padding(.vertical, 6).allowsHitTesting(false).accessibilityHidden(true)
              }
            }
            HStack {
              if let feedback = deliveryFeedback {
                Label {
                  Text(feedback.text)
                } icon: {
                  Image(systemName: feedback.symbol)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .default, value: feedback.symbol)
                }.font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button {
                child.askParent()
              } label: {
                Text("Ask Parent", bundle: .module)
              }
              .disabled(!child.canSend).keyboardShortcut(.return, modifiers: .command)
            }
          }
        }
      }
      HStack {
        Button {
          child.stop()
        } label: {
          Text("Stop Agent", bundle: .module)
        }.disabled(!child.canStop)
        Spacer()
        Button {
          close()
        } label: {
          Text("Done", bundle: .module)
        }.keyboardShortcut(.defaultAction)
      }
    }
    .padding().frame(minWidth: 420, idealWidth: 520, minHeight: 380, idealHeight: 560)
    .task { if child.snapshot == nil && child.error == nil { child.refresh() } }
    .environment(
      \.openURL,
      OpenURLAction { url in
        if AgentChatReference.parse(url) != nil { return openReference(url) ? .handled : .discarded }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
      })
  }

  private var deliveryFeedback: (text: String, symbol: String)? {
    if child.isSending { return (ScholiumL10n.string("Sending to Parent", locale: locale), "paperplane") }
    if let receipt = child.receipt {
      return (
        receipt.label(locale: locale),
        receipt == .received
          ? "checkmark.circle"
          : receipt == .unconfirmed ? "clock" : "exclamationmark.circle"
      )
    }
    if !child.canSend && !child.draft.isEmpty && !(child.isWorking && child.snapshot == nil) {
      return (ScholiumL10n.string("Parent Unavailable", locale: locale), "exclamationmark.circle")
    }
    return nil
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
          Text(ScholiumL10n.string("Ask Parent: \(target.name ?? target.childThreadID)", locale: locale))
        } icon: {
          Image(systemName: "person.2")
        }
        .lineLimit(2)
      }
      .buttonStyle(.plain)
      Menu {
        Button(action: inspect) { Text("Open Agent", bundle: .module) }
        if let openParent { Button(action: openParent) { Text("Open Parent", bundle: .module) } }
        if let remove { Button(action: remove) { Text("Remove Agent Target", bundle: .module) } }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel(Text("Agent Target Actions", bundle: .module))
    }
    .font(.caption).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
  }
}
