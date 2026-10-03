import SwiftUI

/// One compact current status; connection and execution remain controller-owned.
/// Recovery actions stay direct. Full explanations and additional independent
/// states share a bounded native inspection rather than adding more top bars.
struct AgentChatConnectionStatus: View {
    @ObservedObject var controller: AgentChatController
    @Binding var diagnosticsPresentation: AgentChatDiagnosticsPresentation?
    @Environment(\.openSettings) private var openSettings
    @State private var showsDetails = false

    private enum Action: Hashable {
        case retryLocalHistory, retryConnection, connect, signIn, retrySettings
        case retryHistory, newConversation, refreshSkills, continueWithoutResending, settings

        var title: String {
            switch self {
            case .retryLocalHistory, .retryConnection, .retrySettings, .retryHistory:
                ScholiumL10n.string("Retry")
            case .connect: ScholiumL10n.string("Connect Codex")
            case .signIn: ScholiumL10n.string("Sign in with ChatGPT")
            case .newConversation: ScholiumL10n.string("New Conversation")
            case .refreshSkills: ScholiumL10n.string("Refresh Skills")
            case .continueWithoutResending: ScholiumL10n.string("Continue Without Resending")
            case .settings: ScholiumL10n.string("Agent Settings…")
            }
        }
    }

    private struct Status: Identifiable {
        let id: String
        let title: String
        var symbol = "exclamationmark.triangle"
        var isProgress = false
        var explanation: String?
        var error: String?
        var actions: [Action] = []
    }

    private var executionError: String? {
        if queueRecoveryIsResolved { return nil }
        return controller.selectedID.flatMap { controller.executions[$0]?.error }
    }
    private var executionRecovery: AgentChatExecutionRecovery? {
        if controller.selected?.pendingMessageID != nil, !controller.isBusy { return .deliveryUnconfirmed }
        if queueRecoveryIsResolved { return nil }
        return controller.selectedID.flatMap { controller.executions[$0]?.recovery }
    }
    private var queueRecoveryIsResolved: Bool {
        guard controller.selectedID.flatMap({ controller.executions[$0]?.recovery }) == .queuedInputBlocked else { return false }
        guard let message = controller.queuedMessages.first else { return true }
        return controller.queuedMessageBlockReason(message.id) == nil
    }

    private var connectionStatus: Status? {
        guard controller.isLoaded, !controller.isRenewingSettings else { return nil }
        switch controller.connectionState {
        case .disconnected:
            if let error = controller.connectionError {
                return Status(
                    id: "connection", title: ScholiumL10n.string("Connection Failed"),
                    explanation: ScholiumL10n.string("Retry the connection or open Diagnostics."),
                    error: error, actions: [.retryConnection])
            }
            return Status(id: "connection", title: ScholiumL10n.string("Not Connected"), symbol: "network", actions: [.connect])
        case .connecting:
            return Status(id: "connection", title: ScholiumL10n.string("Connecting…"), isProgress: true)
        case .ready:
            guard controller.account == nil else { return nil }
            return Status(
                id: "connection", title: ScholiumL10n.string(controller.connectionError == nil ? "Sign-In Required" : "Sign-In Failed"),
                symbol: "person.crop.circle",
                explanation: controller.connectionError.map { _ in ScholiumL10n.string("Try signing in again or open Diagnostics.") },
                error: controller.connectionError, actions: [.signIn])
        }
    }

    private var statuses: [Status] {
        if !controller.isLoaded {
            guard let error = controller.localHistoryError else { return [] }
            return [
                Status(
                    id: "localHistory", title: ScholiumL10n.string("Chat History Could Not Be Loaded"),
                    explanation: ScholiumL10n.string("Saved history has not been replaced. Retry loading it."),
                    error: error, actions: [.retryLocalHistory])
            ]
        }
        var result: [Status] = []
        if let recovery = executionRecovery {
            var actions: [Action] = recovery == .historyRefreshFailed ? [.retryHistory] : []
            if controller.selected?.pendingMessageID != nil, !controller.isBusy { actions.append(.continueWithoutResending) }
            result.append(Status(id: "execution", title: recovery.title, explanation: recovery.explanation, error: executionError, actions: actions))
        } else if let error = executionError {
            result.append(
                Status(
                    id: "execution", title: ScholiumL10n.string("Conversation Needs Attention"), error: error,
                    actions: controller.connectionState == .disconnected ? [.settings] : []))
        }
        if controller.isRenewingSettings {
            result.append(
                Status(
                    id: "settings", title: ScholiumL10n.string(controller.settingsRenewalError == nil ? "Applying Settings…" : "Settings Could Not Be Applied"),
                    isProgress: controller.settingsRenewalError == nil,
                    error: controller.settingsRenewalError, actions: controller.settingsRenewalError == nil ? [] : [.retrySettings]))
        }
        if let connectionStatus { result.append(connectionStatus) }
        if controller.historyUnavailable {
            result.append(
                Status(
                    id: "history", title: ScholiumL10n.string("Conversation Unavailable"),
                    explanation: ScholiumL10n.string("This conversation is saved here, but unavailable in the connected runtime."),
                    actions: [.retryHistory, .newConversation]))
        }
        if let error = controller.capabilities.workspaceError {
            result.append(
                Status(
                    id: "skills", title: ScholiumL10n.string("Skills Could Not Be Loaded"),
                    error: error, actions: [.refreshSkills]))
        }
        return result
    }

    var body: some View {
        let statuses = self.statuses
        if let primary = statuses.first {
            let actions = primary.actions
            let visibleActions = directActions(for: primary, statuses: statuses)
            let connectionActions = visibleActions.filter { !actions.contains($0) }
            let hasDetails = primary.explanation != nil || statuses.count > 1 || statuses.contains { $0.error != nil }
            VStack(alignment: .leading, spacing: ScholiumSidebarLayout.textSpacing) {
                if !hasDetails, actions.count <= 1 {
                    HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                        statusTitle(primary)
                        Spacer(minLength: ScholiumSidebarLayout.textSpacing)
                        actionButtons(actions)
                    }
                } else {
                    HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                        statusTitle(primary)
                        Spacer(minLength: ScholiumSidebarLayout.textSpacing)
                        actionButtons(connectionActions).fixedSize(horizontal: true, vertical: false)
                        Button {
                            showsDetails.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .frame(width: ScholiumGrid.Dimension.preferredCustomTarget, height: ScholiumGrid.Dimension.preferredCustomTarget)
                        }
                        .help("Details").accessibilityLabel("Details")
                        .accessibilityValue(
                            Text(verbatim: statuses.map { [$0.title, $0.explanation].compactMap { $0 }.joined(separator: ". ") }.joined(separator: "\n"))
                        )
                        .popover(isPresented: $showsDetails) { statusDetails(statuses, directActions: visibleActions) }
                    }
                    if !actions.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: ScholiumSidebarLayout.itemSpacing) { actionButtons(actions) }
                                .fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: ScholiumSidebarLayout.textSpacing) { actionButtons(actions) }
                        }
                    }
                }
            }
            .font(.callout)
            .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
            .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
            .padding(.top, ScholiumSidebarLayout.textSpacing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                primary.id == "localHistory"
                    ? "scholium.chat.localHistoryFailure" : primary.id == "execution" ? "scholium.chat.executionRecovery" : "scholium.chat.connectionStatus"
            )
            .onChange(of: statuses.first?.id) { old, new in if old != new { showsDetails = false } }
            .onChange(of: controller.selectedID) { _, _ in showsDetails = false }
        }
    }

    private func directActions(for primary: Status, statuses: [Status]) -> [Action] {
        var actions = primary.actions
        if primary.id != "localHistory", primary.id != "connection", let connection = statuses.first(where: { $0.id == "connection" }) {
            actions += connection.actions
        }
        var seen: Set<Action> = []
        return actions.filter { seen.insert($0).inserted }
    }

    private func statusTitle(_ status: Status) -> some View {
        HStack(spacing: ScholiumSidebarLayout.textSpacing) {
            if status.isProgress {
                ProgressView().controlSize(.mini).accessibilityHidden(true)
            } else {
                Image(systemName: status.symbol).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(verbatim: status.title).font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
    }

    private func statusDetails(_ statuses: [Status], directActions: [Action]) -> some View {
        AgentChatContentScroll(maximumHeight: 240) {
            VStack(alignment: .leading, spacing: ScholiumSidebarLayout.sectionSpacing) {
                ForEach(statuses) { status in
                    VStack(alignment: .leading, spacing: ScholiumSidebarLayout.textSpacing) {
                        Text(verbatim: status.title).font(.callout.weight(.medium))
                        if let explanation = status.explanation { Text(verbatim: explanation).font(.callout).fixedSize(horizontal: false, vertical: true) }
                        let actions = status.actions.filter { !directActions.contains($0) }
                        if !actions.isEmpty { VStack(alignment: .leading) { actionButtons(actions) } }
                        if let error = status.error {
                            AgentChatDiagnosticsButton(controller: controller, presentation: $diagnosticsPresentation, error: error)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ScholiumSidebarLayout.rowInset)
        }
        .frame(width: 300)
        .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
        .accessibilityElement(children: .contain)
    }

    private func actionButtons(_ actions: [Action]) -> some View {
        ForEach(actions, id: \.self) { action in
            Button(action.title) { perform(action) }
                .disabled(!isEnabled(action))
                .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                .accessibilityIdentifier(
                    action == .continueWithoutResending ? "scholium.chat.continueAfterUncertainDelivery" : "scholium.chat.status.\(action)")
        }
    }

    private func isEnabled(_ action: Action) -> Bool {
        switch action {
        case .retryLocalHistory: !controller.isLoadingLocalHistory
        case .signIn: !controller.isBusy
        case .retryHistory: !controller.isBusy && controller.connectionState == .ready
        case .refreshSkills: !controller.isBusy && !controller.capabilities.isRefreshing
        case .continueWithoutResending: controller.selected?.pendingMessageID != nil && !controller.isBusy
        default: true
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .retryLocalHistory: controller.retryLocalHistory()
        case .retryConnection, .connect: controller.connectConfigured()
        case .signIn: controller.login()
        case .retrySettings: controller.renewSettingsWhenIdle()
        case .retryHistory: controller.retryHistory()
        case .newConversation: controller.newConversation()
        case .refreshSkills: controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
        case .continueWithoutResending: controller.confirmContinueAfterUncertainDelivery()
        case .settings:
            SettingsNavigationRequest.select(.agents, agentCategory: .connection)
            openSettings()
        }
    }
}
