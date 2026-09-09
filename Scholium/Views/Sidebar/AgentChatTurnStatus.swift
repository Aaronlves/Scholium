import ScholiumContracts
import SwiftUI

/// A presentation of observed work, not an interpretation of private reasoning.
struct AgentChatTurnPresentation: Equatable {
  enum State: Equatable {
    case working, responding, reading, searching, writing, organizing
    case waitingForInput, waitingForApproval, stopping, completed, interrupted, failed, uncertain
  }
  let state: State
  var timing = AgentChatTurnTiming()

  var isWorking: Bool {
    switch state {
    case .working, .responding, .reading, .searching, .writing, .organizing: true
    default: false
    }
  }
  var titleKey: String.LocalizationValue {
    switch state {
    case .working: "Considering your question…"
    case .responding: "Composing a reply…"
    case .reading: "Reading material…"
    case .searching: "Looking through material…"
    case .writing: "Revising notes…"
    case .organizing: "Organizing the discussion…"
    case .waitingForInput: "Waiting for your response"
    case .waitingForApproval: "Waiting for your permission"
    case .stopping: "Stopping…"
    case .completed: "Turn complete"
    case .interrupted: "Turn stopped"
    case .failed: "Turn did not complete"
    case .uncertain: "Turn status unconfirmed"
    }
  }
  func seconds(at now: Date) -> Int? {
    if isWorking {
      guard let start = timing.startedAt, now >= start else { return nil }
      return Int(exactly: now.timeIntervalSince(start).rounded(.down))
    }
    if state == .completed || state == .interrupted || state == .failed { return timing.completedSeconds }
    return nil
  }
}

struct AgentChatTurnStatus: View {
  let presentation: AgentChatTurnPresentation
  var animates = true
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.controlActiveState) private var activeState

  var body: some View {
    TimelineView(.animation(minimumInterval: 1, paused: !presentation.isWorking || !animates || activeState == .inactive)) { context in
      HStack(spacing: 6) {
        if presentation.state == .completed, let seconds = presentation.seconds(at: context.date) {
          Text(String(format: ScholiumL10n.string("Turn took %lld s", locale: locale), seconds))
        } else {
          Text(ScholiumL10n.string(presentation.titleKey, locale: locale))
          if let seconds = presentation.seconds(at: context.date) {
            Text(String(format: ScholiumL10n.string("· %lld s", locale: locale), seconds))
              .accessibilityHidden(true)
          }
        }
      }
      .font(.callout).monospacedDigit().foregroundStyle(.secondary)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(ScholiumL10n.string(presentation.titleKey, locale: locale))
      .accessibilityValue(!presentation.isWorking && presentation.seconds(at: context.date) != nil
        ? String(format: ScholiumL10n.string("Turn took %lld s", locale: locale), presentation.seconds(at: context.date)!) : "")
      .help("Elapsed time for this turn, including tools and waits.")
    }
  }
}
