import SwiftUI

/// View-local disclosure only; requests and drafts remain controller-owned.
struct AgentChatInputDockState {
  private(set) var requestID: String?
  var isExpanded = false

  mutating func receive(_ id: String?, mayExpand: Bool) -> Bool {
    guard requestID != id else { return false }
    let restoreDraft = isExpanded && id == nil
    requestID = id
    isExpanded = id != nil && mayExpand
    return restoreDraft
  }
}

struct AgentChatInputDock<Request: View, Composer: View>: View {
  let requestID: String?
  let requestTitle: String
  let requestCount: Int
  let isActive: Bool
  let isReadingHistory: Bool
  let isEditingDraft: Bool
  @Binding var composerIsFocused: Bool
  @ViewBuilder let request: () -> Request
  @ViewBuilder let composer: () -> Composer
  @State private var presentation = AgentChatInputDockState()
  @FocusState private var requestHasFocus: Bool

  private var expanded: Bool { requestID != nil && presentation.isExpanded }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if requestID != nil && !expanded {
        HStack {
          Button(requestTitle) {
            composerIsFocused = false
            presentation.isExpanded = true
          }.accessibilityIdentifier("scholium.chat.openPendingRequest")
          Spacer(minLength: 0)
          if requestCount > 1 { Text("\(requestCount) pending").font(.caption).foregroundStyle(.secondary) }
        }
      }
      // Keep the native editor mounted: hiding the draft must not discard Undo,
      // selection, or the native text-input session. Hidden content is inert.
      composer()
        .frame(height: expanded ? 0 : nil)
        .opacity(expanded ? 0 : 1)
        .disabled(expanded)
        .allowsHitTesting(!expanded)
        .accessibilityHidden(expanded)
      request()
        .frame(height: expanded ? nil : 0, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(expanded ? 1 : 0)
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .disabled(!expanded)
        .focusable(expanded)
        .focusEffectDisabled()
        .focused($requestHasFocus)
    }
    .buttonStyle(.borderless)
    .padding(12)
    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 24))
    .padding(ScholiumSidebarLayout.edgeInset)
    .tint(nil as Color?)
    .onChange(of: requestID, initial: true) { _, id in
      if presentation.receive(id, mayExpand: isActive && !isEditingDraft && !isReadingHistory), isActive {
        composerIsFocused = true
      } else if expanded {
        composerIsFocused = false
      }
    }
    .onChange(of: expanded) { _, value in
      requestHasFocus = value && isActive
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.inputDock")
  }

}

/// Short requests fit their content; long requests retain a bounded native viewport.
struct AgentChatContentScroll<Content: View>: View {
  var maximumHeight: CGFloat = 240
  @ViewBuilder let content: () -> Content
  @State private var contentHeight: CGFloat = 1

  var body: some View {
    ScrollView {
      content()
        .padding(4)
        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeight = $0 }
    }.frame(height: min(maximumHeight, contentHeight))
  }
}

/// Shared, noninteractive acknowledgement state for questions and permissions.
struct AgentChatSubmissionStatus: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let failure: String?

  var body: some View {
    if let failure {
      Text(failure).font(.caption).foregroundStyle(.secondary)
    } else {
      HStack(spacing: 8) {
        if reduceMotion {
          Image(systemName: "ellipsis").accessibilityHidden(true)
        } else {
          ProgressView().controlSize(.small).accessibilityHidden(true)
        }
        Text("Waiting for Confirmation…", bundle: .module)
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
