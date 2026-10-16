import ScholiumContracts
import SwiftUI

struct WritingAssistanceModelSettingsContent: View {
    @Environment(\.agentChatSettingsController) private var controller
    @ObservedObject private var preferences: WritingAssistancePreferences

    init(preferences: WritingAssistancePreferences) {
        self.preferences = preferences
    }

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
    @Environment(\.agentChatSettingsController) private var controller
    @ObservedObject private var preferences: WritingAssistancePreferences

    init(preferences: WritingAssistancePreferences) {
        self.preferences = preferences
    }

    var body: some View {
        Section {
            Toggle(isOn: $preferences.continuationEnabled) {
                Text(ScholiumL10n.WritingAssistance.enable)
            }
            .accessibilityIdentifier("scholium.settings.writingContinuation.enabled")
            if let controller {
                WritingContinuationEffortSettings(controller: controller, preferences: preferences)
                    .id(controller.triptychID)
            } else {
                WritingContinuationEffortPicker(preferences: preferences, efforts: [])
                Text(ScholiumL10n.WritingAssistance.openTriptych)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(ScholiumL10n.WritingAssistance.effortExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

private struct WritingContinuationEffortSettings: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var preferences: WritingAssistancePreferences

    private var connected: Bool { controller.connectionState == .ready && controller.account != nil }
    private var model: AgentChatModel? {
        connected ? controller.writingAssistanceModels.first { $0.model == preferences.model } : nil
    }

    var body: some View {
        WritingContinuationEffortPicker(preferences: preferences, efforts: model.map { controller.continuationEfforts(for: $0) } ?? [])
        if !connected {
            Text(ScholiumL10n.WritingAssistance.connect)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model == nil {
            Text(ScholiumL10n.WritingAssistance.unavailableModel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WritingContinuationEffortPicker: View {
    @ObservedObject var preferences: WritingAssistancePreferences
    let efforts: [String]
    private var effectiveAutomatic: String {
        efforts.first.map(AgentChatControlLabels.effort) ?? ScholiumL10n.string("Unavailable")
    }
    private var unavailableSelection: Bool {
        guard let effort = preferences.continuationEffort else { return false }
        return !preferences.continuationEffortIsValid || !efforts.contains(effort)
    }

    var body: some View {
        Picker(selection: $preferences.continuationEffort) {
            Text(ScholiumL10n.WritingAssistance.automaticEffort(effectiveAutomatic))
                .tag(Optional<String>.none)
            if unavailableSelection, let selected = preferences.continuationEffort {
                if preferences.continuationEffortIsValid {
                    Text("Unavailable: \(AgentChatControlLabels.effort(selected))", bundle: .module)
                        .tag(Optional(selected)).disabled(true)
                } else {
                    Text(ScholiumL10n.WritingAssistance.invalidEffort)
                        .tag(Optional(selected)).disabled(true)
                }
            }
            ForEach(efforts, id: \.self) { effort in
                Text(verbatim: AgentChatControlLabels.effort(effort)).tag(Optional(effort))
            }
        } label: {
            Text(ScholiumL10n.WritingAssistance.effort)
        }
        .disabled(efforts.isEmpty)
        .accessibilityIdentifier("scholium.settings.writingContinuation.effort")
        .id(SettingsSection.writingEffort)
        if unavailableSelection {
            Text(ScholiumL10n.WritingAssistance.unavailableEffort)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
