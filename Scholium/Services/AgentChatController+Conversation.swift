import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

@MainActor
extension AgentChatController {
    @discardableResult
    func quoteReply(_ messageID: String, selection: AgentChatReplySelection?, in conversationID: UUID) -> Bool {
        guard selectedID == conversationID, let conversation = selected, conversation.isAvailable == true,
            let message = conversation.messages.first(where: { $0.id == messageID }), message.role == .assistant,
            message.phase != .commentary, !message.text.isEmpty,
            !isBusy || message.turnID != currentTurnID
        else { return false }
        let text: String
        if let selection {
            guard let passage = AgentChatReplyQuotation.passage(selection, in: message.text) else { return false }
            text = passage
        } else {
            text = message.text
        }
        guard
            !(conversation.draftReplyQuotes ?? []).contains(where: {
                $0.conversationID == conversationID && $0.messageID == messageID && $0.text == text
            })
        else { return true }
        update(in: conversationID) {
            $0.draftReplyQuotes = ($0.draftReplyQuotes ?? []) + [.init(conversationID: conversationID, messageID: messageID, text: text)]
        }
        persist()
        return true
    }

    func removeReplyQuote(_ id: UUID, in conversationID: UUID) {
        update(in: conversationID) {
            $0.draftReplyQuotes?.removeAll { $0.id == id }
            if $0.draftReplyQuotes?.isEmpty == true { $0.draftReplyQuotes = nil }
        }
        persist()
    }

    /// A selection action creates an ordinary conversation without moving the visible Chat or consuming its draft.
    func beginSelectionInquiry(_ inquiry: AgentChatSelectionInquiry, attachment: AgentChatAttachment) -> UUID? {
        guard isLoaded, let question = inquiry.question, !question.isEmpty else { return nil }
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.preferences = selected?.preferences ?? .init()
        conversation.title = inquiry.title
        conversation.draft = question + "\n\n" + ScholiumL10n.string("Return an explanation or proposal only. Do not modify files or Notes.")
        conversation.attachments = [attachment]
        conversations.insert(conversation, at: 0)
        executions[conversation.id] = .init()
        persist()
        let message = draftMessage(conversation)
        if canSend(message: message, in: conversation) {
            send(message, in: conversation, consumesDraft: true)
        }
        return conversation.id
    }

    func selectionResultError(in id: UUID) -> String? {
        if let error = executions[id]?.error ?? connectionError { return error }
        if connectionState == .disconnected { return ScholiumL10n.string("Connect in Chat to send this instruction.") }
        if connectionState == .ready, account == nil { return ScholiumL10n.string("Sign in to continue.") }
        if let conversation = conversation(id), !selectionIsAvailable(conversation.preferences) {
            return ScholiumL10n.string("Choose an available model and reasoning level.")
        }
        return nil
    }

    func newConversation() {
        guard isLoaded else { return }
        let conversation = AgentChatConversation(triptychID: triptychID)
        conversations.insert(conversation, at: 0)
        executions[conversation.id] = .init()
        selectedID = conversation.id
        persist()
    }

    func select(_ id: UUID) {
        guard conversation(id) != nil else { return }
        selectedID = id
        refreshHistory(in: id)
    }

    func setArchived(_ id: UUID, archived: Bool) {
        guard isLoaded, canArchive(id), let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].archivedAt = archived ? Date() : nil
        executions[id]?.admissionID = nil
        persist()
    }

    func deleteConversation(_ id: UUID) {
        guard isLoaded, canArchive(id), let index = conversations.firstIndex(where: { $0.id == id }),
            conversations[index].archivedAt != nil
        else { return }
        executions[id]?.admissionID = nil
        conversations.remove(at: index)
        executions.removeValue(forKey: id)
        if selectedID == id { selectedID = nil }
        persist()
    }

    func setUnread(_ id: UUID, unread: Bool) {
        guard isLoaded, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        guard (conversations[index].unreadAt != nil) != unread else { return }
        conversations[index].unreadAt = unread ? Date() : nil
        persist()
    }

    func setImportant(_ id: UUID, important: Bool) {
        guard isLoaded, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].importantAt = important ? Date() : nil
        persist()
    }

    func connectConfigured(using defaults: UserDefaults? = nil, automatically: Bool = false) {
        guard connectionState == .disconnected, isLoaded else { return }
        let defaults = defaults ?? connectionDefaults
        connectionDefaults = defaults
        automaticConnection = true
        if !automatically { reconnectAttempt = 0 }
        let executable =
            defaults.string(forKey: "agent.codex.executable").flatMap { $0.isEmpty ? nil : $0 }
            ?? suggestedRuntimePath
        let helper =
            defaults.string(forKey: "agent.scholium.helper").flatMap { $0.isEmpty ? nil : $0 }
            ?? suggestedHelperPath
        guard let executable, let executableURL = ScholiumAgentIntegrationResources.executableURL(at: executable) else {
            connectionError = String(localized: "Codex was not found. Open Agent settings to locate your installation.")
            return
        }
        guard let helper, let helperURL = ScholiumAgentIntegrationResources.executableURL(at: helper) else {
            connectionError = String(
                localized: "Scholium’s connection helper is unavailable. Reinstall Scholium or check the custom helper in Advanced settings.")
            return
        }
        let home = defaults.string(forKey: "agent.codex.home") ?? ""
        connect(
            executable: executableURL,
            home: home.isEmpty ? runtimeHome : URL(fileURLWithPath: home),
            helper: helperURL, signInIfNeeded: !automatically)
    }

    func editDraft(_ text: String) {
        guard let selectedID else { return }
        editDraft(text, in: selectedID)
    }
    func editDraft(_ text: String, in conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
            conversations[index].isAvailable == true,
            conversations[index].draft != text
        else { return }
        conversations[index].draft = text
        conversations[index].updatedAt = Date()
        persist()
    }
    func setPermission(_ value: AgentChatPermission) {
        guard !isBusy, selected?.isAvailable == true else { return }
        update { $0.permission = value }
        persist()
    }
    func setModel(_ model: String?) {
        guard !isBusy, selected?.isAvailable == true,
            model == nil || models.contains(where: { $0.model == model })
        else { return }
        update {
            if $0.preferences.model != model { $0.contextUsage = nil }
            $0.preferences.model = model
            $0.preferences.effort = nil
        }
        persist()
    }
    func setEffort(_ effort: String?) {
        guard !isBusy, selected?.isAvailable == true,
            effort == nil || selectedModel?.efforts.contains(effort!) == true
        else { return }
        update { $0.preferences.effort = effort }
        persist()
    }
    func setWebSearch(_ mode: AgentChatPreferences.WebSearch) {
        guard !isBusy, let selected, selected.isAvailable == true, selected.preferences.webSearch != mode else { return }
        update { $0.preferences.webSearch = mode }
        persist()
        if selected.threadID != nil, connectionState == .ready { renewSettingsWhenIdle() }
    }

    func renewSettingsWhenIdle() {
        guard connectionState == .ready, settingsRenewalTask == nil, let runtime,
            let executable = connectedExecutable, let home = connectedHome, let helper = helperURL
        else { return }
        let id = UUID()
        let connection = connectionID
        settingsRenewalID = id
        isRenewingSettings = true
        settingsRenewalError = nil
        settingsRenewalTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.settingsRenewalID == id { self.settingsRenewalTask = nil } }
            do {
                while true {
                    try Task.checkCancellation()
                    guard self.settingsRenewalID == id, self.connectionID == connection else { return }
                    if !self.hasActiveExecutions && !self.capabilities.isChanging,
                        try await runtime.chatIsIdleForSettingsRenewal()
                    {
                        try Task.checkCancellation()
                        guard self.settingsRenewalID == id, self.connectionID == connection,
                            !self.hasActiveExecutions, !self.capabilities.isChanging
                        else { continue }
                        await self.closeConnection(retainingAutomaticConnection: true, forSettingsRenewal: true)
                        guard !Task.isCancelled, self.settingsRenewalID == id else { return }
                        self.beginConnection(executable: executable, home: home, helper: helper, signInIfNeeded: false)
                        await self.connectionTask?.value
                        guard self.settingsRenewalID == id else { return }
                        self.isRenewingSettings = false
                        self.settingsRenewalID = nil
                        self.settingsRenewalTask = nil
                        return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
            } catch {
                guard self.settingsRenewalID == id else { return }
                self.settingsRenewalError = error.localizedDescription
            }
        }
    }

    func cancelSettingsRenewal() {
        settingsRenewalID = nil
        settingsRenewalTask?.cancel()
        settingsRenewalTask = nil
        isRenewingSettings = false
        settingsRenewalError = nil
    }
    func rename(_ value: String, in id: UUID? = nil) {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = id ?? selectedID, !title.isEmpty else { return }
        update(in: id) { $0.title = title }
        persist()
    }
    func toggleMethod(_ method: AgentChatMethodSelection) {
        guard isLoaded, selected?.isAvailable == true else { return }
        let wasSelected = selected?.selectedMethods?.contains(where: { $0.id == method.id }) == true
        guard wasSelected || (method.name != "scholium-core-protocol" && capabilities.contains(method)) else { return }
        update {
            var selections = $0.selectedMethods ?? []
            if wasSelected { selections.removeAll { $0.id == method.id } } else { selections.append(method) }
            $0.selectedMethods = selections.isEmpty ? nil : selections
        }
        persist()
    }
    func attach(_ attachment: AgentChatAttachment) {
        _ = attachContext([attachment])
    }

    /// A provider-neutral handoff shared by selection and related-material discovery.
    /// It stages context for the researcher; it never sends a message or replaces a draft.
    @discardableResult
    func attachContext(_ attachments: [AgentChatAttachment]) -> Bool {
        guard isLoaded else { return false }
        if selected == nil || selected?.isAvailable == false {
            newConversation()
        }
        guard let selectedID else { return false }
        return attachContext(attachments, to: selectedID)
    }

    @discardableResult
    func attachContext(_ attachments: [AgentChatAttachment], to conversationID: UUID) -> Bool {
        guard isLoaded, conversations.contains(where: { $0.id == conversationID && $0.isAvailable == true }) else { return false }
        update(in: conversationID) { conversation in
            for attachment in attachments
            where !conversation.attachments.contains(where: {
                $0.noteID == attachment.noteID && $0.fingerprint == attachment.fingerprint && $0.sourceLine == attachment.sourceLine
                    && $0.sourceRange == attachment.sourceRange && $0.text == attachment.text
                    && $0.extent == attachment.extent && $0.source == attachment.source
            }) {
                conversation.attachments.append(attachment)
            }
        }
        persist()
        presentContext(in: conversationID)
        return true
    }
    func prepareSelectionInquiry(
        _ attachments: [AgentChatAttachment], inquiry: AgentChatSelectionInquiry,
        to conversationID: UUID
    ) -> Bool {
        guard selectedID == conversationID, !attachments.isEmpty,
            attachContext(attachments, to: conversationID)
        else { return false }
        if let question = inquiry.question {
            let draft = selected?.draft ?? ""
            editDraft(draft.isEmpty ? question : draft + "\n\n" + question, in: conversationID)
        }
        return true
    }

    func removeAttachment(_ id: UUID) {
        update { $0.attachments.removeAll { $0.id == id } }
        persist()
    }

    func update(_ change: (inout AgentChatConversation) -> Void) {
        guard let selectedID else { return }
        update(in: selectedID, change)
    }

    func update(in id: UUID, _ change: (inout AgentChatConversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let previous = conversations[index]
        change(&conversations[index])
        if conversations[index] != previous { conversations[index].updatedAt = Date() }
    }

    private func historySnapshot() -> [AgentChatConversation] {
        var snapshot = conversations
        for index in snapshot.indices {
            guard let messageID = pendingDraftConsumption[snapshot[index].id],
                let message = snapshot[index].messages.first(where: { $0.id == messageID })
            else { continue }
            consumeDraft(message, from: &snapshot[index])
        }
        return snapshot
    }

    /// Both ordinary updates and write-ahead saves use this one ordered writer.
    /// Edits during a send preparation therefore cannot overwrite the durable
    /// pending-message state with an older, unconsumed draft snapshot.
    private func enqueueHistorySave() -> Task<Void, Error> {
        let snapshot = historySnapshot()
        let previous = persistenceTask
        let saveHistory = saveHistory
        let operation = Task { @MainActor in
            await previous?.value
            try await saveHistory(snapshot)
        }
        persistenceTask = Task { [weak self] in
            do { try await operation.value } catch {
                self?.connectionError = String(localized: "Conversation not saved: \(error.localizedDescription)")
            }
        }
        return operation
    }

    func persist() {
        guard isLoaded else { return }
        _ = enqueueHistorySave()
    }

    func flushPersistence() async throws {
        guard isLoaded else { return }
        try await saveNow()
    }

    func saveNow() async throws {
        try await enqueueHistorySave().value
    }
}
