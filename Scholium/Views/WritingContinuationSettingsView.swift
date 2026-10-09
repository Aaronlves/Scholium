import ScholiumContracts
import SwiftUI

struct WritingAssistanceModelSettingsContent: View {
    @Environment(\.agentChatSettingsController) private var controller
    @ObservedObject private var preferences = WritingAssistancePreferences.shared

    var body: some View {
        Section {
            if let error = preferences.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                Button("Restore Writing Assistance Defaults") { preferences.restoreDefaults() }
            }
            if let controller {
                WritingAssistanceModelSettings(controller: controller, preferences: preferences)
                    .id(controller.triptychID)
            } else {
                WritingAssistanceModelPicker(preferences: preferences, models: [], connected: false)
                Text(ScholiumL10n.WritingAssistance.openTriptych)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(ScholiumL10n.WritingAssistance.contextAndAllowance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(ScholiumL10n.WritingAssistance.model)
        } footer: {
            Text("This Mac", bundle: .module)
        }
        .id(SettingsSection.writingModel)
    }
}

struct WritingContinuationSettingsContent: View {
    @ObservedObject private var preferences = WritingAssistancePreferences.shared

    var body: some View {
        Section {
            Toggle(isOn: $preferences.continuationEnabled) {
                Text(ScholiumL10n.WritingAssistance.enable)
            }
            .accessibilityIdentifier("scholium.settings.writingContinuation.enabled")
            Text(ScholiumL10n.WritingAssistance.trigger)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Writing Continuation")
        } footer: {
            Text("This Mac", bundle: .module)
        }
        .id(SettingsSection.writingContinuation)
    }
}

private struct WritingAssistanceModelSettings: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var preferences: WritingAssistancePreferences

    private var connected: Bool { controller.connectionState == .ready && controller.account != nil }
    private var models: [AgentChatModel] { controller.writingAssistanceModels }

    var body: some View {
        WritingAssistanceModelPicker(preferences: preferences, models: models, connected: connected)
        if !connected {
            Text(ScholiumL10n.WritingAssistance.connect)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !models.contains(where: { $0.model == preferences.model }) {
            Text(ScholiumL10n.WritingAssistance.unavailableModel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WritingAssistanceModelPicker: View {
    @ObservedObject var preferences: WritingAssistancePreferences
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
            Text("Model")
        }
        .disabled(availableModels.isEmpty)
        .accessibilityIdentifier("scholium.settings.writingContinuation.model")
    }
}
