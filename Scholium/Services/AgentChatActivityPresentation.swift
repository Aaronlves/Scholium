import Foundation
import ScholiumContracts

struct AgentChatActivityNoteTarget: Equatable {
    let noteID: UUID
    let vaultID: UUID
    let title: String

    var url: URL {
        AgentChatReference.url(noteID: noteID, vaultID: vaultID)
    }
}

/// A projection of public runtime events and App receipts, never a source writer.
enum AgentChatActivityProjection {
    static func title(_ activity: AgentChatActivity, locale: Locale = .current) -> String {
        let running = activity.status == .running
        let completed = activity.status == .completed
        let key: String.LocalizationValue
        if activity.kind == .tool, case .webAccess = activity.sourceObservation {
            key = running ? "Checking a web source" : completed ? "Checked a web source" : "Web source check"
        } else if let action = activity.commandAction {
            switch action.kind {
            case .read: key = running ? "Reading file" : completed ? "Read file" : "File reading"
            case .search: key = running ? "Searching files" : completed ? "Searched files" : "File search"
            case .listFiles: key = running ? "Browsing files" : completed ? "Browsed files" : "File browsing"
            }
        } else {
            switch activity.kind {
            case .read: key = running ? "Reading note" : completed ? "Read note" : "Note reading"
            case .readAttachment: key = running ? "Reading attachment" : completed ? "Read attachment" : "Attachment reading"
            case .search: key = running ? "Searching the library" : completed ? "Searched the library" : "Library search"
            case .create: key = running ? "Creating note" : completed ? "Created note" : "Note creation"
            case .update: key = running ? "Revising note" : completed ? "Revised note" : "Note revision"
            case .trash: key = running ? "Moving note to Trash" : completed ? "Moved note to Trash" : "Note removal"
            case .webSearch: key = running ? "Searching the web" : completed ? "Searched the web" : "Web search"
            case .files: key = running ? "Updating files" : completed ? "Updated files" : "File update"
            case .compaction: key = running ? "Organizing conversation" : completed ? "Organized conversation" : "Conversation organization"
            case .delegation: key = "Agent Collaboration"
            case .command: key = running ? "Running command" : completed ? "Ran command" : "Run Command"
            case .tool: key = running ? "Using tool" : completed ? "Used tool" : "Use Tool"
            }
        }
        return ScholiumL10n.string(key, locale: locale)
    }

    /// Resolves only an exact App-owned Note identity. A path or runtime file
    /// report is not enough to turn a technical subject into a Note link.
    static func noteTarget(
        _ activity: AgentChatActivity,
        catalog: @autoclosure () -> AgentChatNoteCatalog
    ) -> AgentChatActivityNoteTarget? {
        guard activity.source == .scholium, activity.files.count == 1,
            let file = activity.files.first, let noteID = file.noteID,
            let note = catalog().note(noteID)
        else { return nil }
        let title = note.title.isEmpty ? (file.path as NSString).lastPathComponent : note.title
        guard !title.isEmpty else { return nil }
        return .init(noteID: noteID, vaultID: note.reference.vaultID, title: title)
    }

    static func withLocalizedFailure(_ value: AgentChatActivity?) -> AgentChatActivity? {
        guard var activity = value else { return nil }
        if activity.kind == .delegation && activity.delegation == nil {
            activity.detail = ScholiumL10n.string("The delegated-work report could not be read.")
        }
        return activity
    }

    static func afterConnectionLoss(_ activity: AgentChatActivity) -> AgentChatActivity {
        guard activity.status.isActive else { return activity }
        var result = activity
        result.status =
            activity.status == .running && (activity.source == .runtime || activity.kind.isMutation)
            ? .uncertain : .interrupted
        return result
    }
}

extension AgentChatActivity.Kind {
    var isMutation: Bool { [.create, .update, .trash, .files].contains(self) }
    var symbol: String {
        switch self {
        case .read, .readAttachment: "doc.text.magnifyingglass"
        case .search, .webSearch: "magnifyingglass"
        case .create: "doc.badge.plus"
        case .update, .files: "pencil.line"
        case .trash: "trash"
        case .command: "terminal"
        case .tool: "gearshape.2"
        case .compaction: "arrow.down.right.and.arrow.up.left"
        case .delegation: "person.2"
        }
    }
}

extension AgentChatActivity.Status {
    var label: String { label(locale: .current) }
    func label(locale: Locale) -> String {
        let key: String.LocalizationValue
        switch self {
        case .running: key = "In Progress"
        case .waitingForApproval: key = "Waiting for Approval"
        case .waitingForInput: key = "Input Requested"
        case .completed: key = "Completed"
        case .failed: key = "Failed"
        case .declined: key = "Declined"
        case .interrupted: key = "Interrupted"
        case .uncertain: key = "Outcome Uncertain"
        }
        return ScholiumL10n.string(key, locale: locale)
    }
    var symbol: String {
        switch self {
        case .running: "ellipsis"
        case .waitingForApproval: "hand.raised"
        case .waitingForInput: "questionmark.bubble"
        case .completed: "checkmark"
        case .failed, .uncertain: "exclamationmark.triangle"
        case .declined: "xmark"
        case .interrupted: "stop"
        }
    }
}
