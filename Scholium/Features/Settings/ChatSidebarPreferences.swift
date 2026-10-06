import Combine
import CoreFoundation
import Foundation

/// This-Mac presentation preference, independent of Chat runtime and external Agents.
@MainActor
final class ChatSidebarPreferences: ObservableObject {
    static let shared = ChatSidebarPreferences()
    static let enabledKey = "scholium.chat.sidebarEnabled"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let boolean = defaults.object(forKey: Self.enabledKey) as? NSNumber
        let valid = boolean.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        isEnabled = valid ? boolean!.boolValue : false
    }
}

enum ChatSidebarPresentationError: LocalizedError {
    case hidden

    var errorDescription: String? {
        ScholiumL10n.string("Chat is hidden. Turn on Show Chat in Sidebar in Settings to continue.")
    }
}
