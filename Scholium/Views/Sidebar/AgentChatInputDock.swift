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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let requestID: String?
    let requestTitle: String
    let requestCount: Int
    let isActive: Bool
    let isReadingHistory: Bool
    let isEditingDraft: Bool
    @Binding var composerIsFocused: Bool
    var onRequestExpanded: () -> Void = {}
    @ViewBuilder let request: () -> Request
    @ViewBuilder let composer: () -> Composer
    @State private var presentation = AgentChatInputDockState()
    @FocusState private var requestHasFocus: Bool

    private var expanded: Bool { requestID != nil && presentation.isExpanded }
    private var mayExpandRequest: Bool { isActive && !isEditingDraft && !isReadingHistory }
    private var isAwaitingAutomaticExpansion: Bool {
        !expanded && presentation.requestID == nil && requestID != nil && mayExpandRequest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumSidebarLayout.itemSpacing) {
            if requestID != nil && (!expanded || requestCount > 1) && !isAwaitingAutomaticExpansion {
                HStack {
                    if !expanded {
                        Button {
                            composerIsFocused = false
                            withAnimation(ScholiumMotion.disclosure(reduceMotion: reduceMotion)) {
                                presentation.isExpanded = true
                            }
                        } label: {
                            Text(requestTitle)
                        }
                        .buttonStyle(ScholiumContentActionButtonStyle())
                        .accessibilityLabel(Text(requestTitle))
                        .accessibilityIdentifier("scholium.chat.openPendingRequest")
                    }
                    Spacer(minLength: 0)
                    if requestCount > 1 { Text("\(requestCount) pending").font(.caption).foregroundStyle(.secondary) }
                }
            }
            // Keep the native editor mounted: hiding the draft must not discard Undo,
            // selection, or the native text-input session. Hidden content is inert.
            composer()
                .frame(height: expanded ? 0 : nil)
                .opacity(expanded ? 0 : 1)
                .clipped()
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
        .padding(ScholiumSidebarLayout.rowInset)
        .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 24))
        .tint(nil as Color?)
        .onChange(of: requestID, initial: true) { previousID, id in
            let restoreDraft: Bool
            if previousID != id && id != nil && mayExpandRequest {
                restoreDraft = withAnimation(ScholiumMotion.disclosure(reduceMotion: reduceMotion)) {
                    presentation.receive(id, mayExpand: true)
                }
            } else {
                restoreDraft = presentation.receive(id, mayExpand: mayExpandRequest)
            }
            if restoreDraft && isActive && !isReadingHistory {
                composerIsFocused = true
            } else if expanded {
                composerIsFocused = false
            }
        }
        .onChange(of: expanded) { _, value in
            if value { onRequestExpanded() }
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

    var body: some View {
        ScrollView {
            content()
                .padding(ScholiumSidebarLayout.textSpacing)
        }
        .frame(maxHeight: maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
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
