import SwiftUI

private struct AgentChatMessageActionScopeKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    fileprivate var agentChatMessageActionScope: UUID? {
        get { self[AgentChatMessageActionScopeKey.self] }
        set { self[AgentChatMessageActionScopeKey.self] = newValue }
    }
}

/// Reveals the existing native footer controls without changing their layout,
/// keyboard traversal, accessibility elements, or action ownership.
struct AgentChatMessageActionVisibility<Content: View, Actions: View>: View {
    var alignment: HorizontalAlignment = .leading
    var actionsAbove = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @State private var isHovered = false
    @State private var scope = UUID()
    @FocusedValue(\.agentChatMessageActionScope) private var focusedScope
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    private var showsActions: Bool {
        isHovered || focusedScope == scope || voiceOverEnabled || switchControlEnabled
    }

    var body: some View {
        VStack(alignment: alignment, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            if actionsAbove { actionRow }
            content()
            if !actionsAbove { actionRow }
        }
        .overlay {
            AgentChatMessagePointerReader(isHovered: $isHovered)
                .accessibilityHidden(true)
        }
        .onDisappear { isHovered = false }
    }

    private var actionRow: some View {
        actions()
            .focusedValue(\.agentChatMessageActionScope, scope)
            // Conceal drawing only; native focus and accessibility remain intact.
            .mask { Rectangle().opacity(showsActions ? 1 : 0).accessibilityHidden(true) }
    }
}

/// Reuses the native full-frame pointer owner across embedded WebKit content.
/// Its hitTest remains nil; text selection and button activation keep their owners.
private struct AgentChatMessagePointerReader: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> ScholiumPointerTrackingView {
        let view = ScholiumPointerTrackingView()
        view.stateDidChange = { hovering, _ in isHovered = hovering }
        return view
    }

    func updateNSView(_ view: ScholiumPointerTrackingView, context: Context) {
        view.stateDidChange = { hovering, _ in isHovered = hovering }
    }

    static func dismantleNSView(_ view: ScholiumPointerTrackingView, coordinator: Void) {
        view.invalidate()
    }
}
