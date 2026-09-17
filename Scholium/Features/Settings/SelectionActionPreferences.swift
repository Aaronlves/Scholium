import AppKit
import Combine

struct SelectionActionDefinition: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var prompt: String
    var isEnabled = true
    var inquiry: AgentChatSelectionInquiry { .init(title: name, question: prompt) }
}

/// One app-local preference owner; custom instructions are neither Skills nor vault data.
@MainActor
final class SelectionActionPreferences: ObservableObject {
    static let shared = SelectionActionPreferences()
    static let maximumCount = 5
    static let key = "scholium.selectionActions"
    @Published private(set) var actions: [SelectionActionDefinition]
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let persisted = defaults.object(forKey: Self.key) else {
            actions = Self.defaultActions
            return
        }
        guard let data = persisted as? Data,
            let objects = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            actions = []
            loadError = ScholiumL10n.string("Selection actions could not be loaded. Restore defaults to replace these settings.")
            return
        }
        var usable: [SelectionActionDefinition] = []
        for object in objects {
            guard usable.count < Self.maximumCount,
                let bytes = try? JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed),
                let action = try? JSONDecoder().decode(SelectionActionDefinition.self, from: bytes),
                Self.validationError([action]) == nil, !usable.contains(where: { $0.id == action.id })
            else { continue }
            usable.append(action)
        }
        actions = usable
        if usable.count != objects.count {
            loadError = ScholiumL10n.string(
                "Some selection actions could not be loaded. Available actions are retained. Save your changes or restore defaults to replace these settings.")
        }
    }

    static var defaultActions: [SelectionActionDefinition] {
        zip(
            ["Concepts", "Argument", "Evidence"],
            [AgentChatSelectionInquiry.clarifyConcepts, .examineArgument, .checkEvidence]
        ).map {
            .init(name: ScholiumL10n.string($0.0), prompt: $0.1.question ?? "")
        }
    }
    static func validationError(_ actions: [SelectionActionDefinition]) -> String? {
        guard actions.count <= maximumCount, Set(actions.map(\.id)).count == actions.count else {
            return ScholiumL10n.string("Use up to five selection actions.")
        }
        for action in actions {
            let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Measure the actual native label rather than truncating Unicode or assuming Latin width.
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let limit = ("概念概念概念" as NSString).size(withAttributes: [.font: font]).width
            guard !name.isEmpty, name.count <= 32, !name.contains(where: \.isNewline),
                (name as NSString).size(withAttributes: [.font: font]).width <= limit
            else {
                return ScholiumL10n.string("Use a short name, up to six Chinese characters or a similar width.")
            }
            guard !action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action.prompt.utf8.count <= 16_384
            else {
                return ScholiumL10n.string("Enter an instruction of up to 16 KB.")
            }
        }
        return nil
    }
    func save(_ value: [SelectionActionDefinition]) throws {
        if let error = Self.validationError(value) { throw ValidationFailure(message: error) }
        defaults.set(try JSONEncoder().encode(value), forKey: Self.key)
        actions = value
        loadError = nil
    }
    func restoreDefaults() {
        defaults.removeObject(forKey: Self.key)
        actions = Self.defaultActions
        loadError = nil
    }
    private struct ValidationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
