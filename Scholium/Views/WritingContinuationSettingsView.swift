import ScholiumContracts
import SwiftUI

struct WritingContinuationSettingsView: View {
    @Environment(\.agentChatSettingsController) private var controller
    @ObservedObject private var preferences = WritingContinuationPreferences.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.enabled) {
                    Text(ScholiumL10n.WritingAssistance.enable)
                }
                .accessibilityIdentifier("scholium.settings.writingContinuation.enabled")

                if let controller {
                    WritingContinuationModelSettings(controller: controller, preferences: preferences)
                        .id(controller.triptychID)
                } else {
                    WritingContinuationModelPicker(preferences: preferences, models: [], connected: false)
                    Text(ScholiumL10n.WritingAssistance.openTriptych)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("This Mac", bundle: .module)
            } footer: {
                Text(ScholiumL10n.WritingAssistance.contextAndAllowance)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("scholium.settings.writingContinuation")
    }
}

private struct WritingContinuationModelSettings: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var preferences: WritingContinuationPreferences

    private var connected: Bool { controller.connectionState == .ready && controller.account != nil }
    private var continuationModels: [AgentChatModel] { controller.writingContinuationModels }

    var body: some View {
        WritingContinuationModelPicker(preferences: preferences, models: continuationModels, connected: connected)
        if !connected {
            Text(ScholiumL10n.WritingAssistance.connect)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !continuationModels.contains(where: { $0.model == preferences.model }) {
            Text(ScholiumL10n.WritingAssistance.unavailableModel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WritingContinuationModelPicker: View {
    @ObservedObject var preferences: WritingContinuationPreferences
    let models: [AgentChatModel]
    let connected: Bool

    private var availableModels: [AgentChatModel] { connected ? models : [] }

    var body: some View {
        Picker(selection: $preferences.model) {
            if !availableModels.contains(where: { $0.model == preferences.model }) {
                Text(verbatim: preferences.model).tag(preferences.model).disabled(true)
            }
            ForEach(availableModels) { model in
                Text(verbatim: model.name).tag(model.model)
            }
        } label: {
            Text(ScholiumL10n.WritingAssistance.model)
        }
        .disabled(!preferences.enabled || availableModels.isEmpty)
        .accessibilityIdentifier("scholium.settings.writingContinuation.model")
    }
}
