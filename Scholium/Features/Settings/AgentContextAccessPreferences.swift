import Combine
import CoreFoundation
import Foundation

enum AgentContextCaller: String, Hashable, Sendable {
    case chat
    case external
}

/// This-Mac read grants. Runtime and Note mutation permissions have separate owners.
@MainActor
final class AgentContextAccessPreferences: ObservableObject {
    static let shared = AgentContextAccessPreferences()
    static let chatStateKey = "scholium.agentContext.chat.allowState"
    static let externalStateKey = "scholium.agentContext.external.allowState"
    static let chatWorkingTextKey = "scholium.agentContext.chat.allowWorkingText"
    static let externalWorkingTextKey = "scholium.agentContext.external.allowWorkingText"

    @Published var chatStateAccess: Bool {
        didSet { save(chatStateAccess, previous: oldValue, key: Self.chatStateKey) }
    }
    @Published var externalStateAccess: Bool {
        didSet { save(externalStateAccess, previous: oldValue, key: Self.externalStateKey) }
    }
    @Published var chatWorkingTextAccess: Bool {
        didSet { save(chatWorkingTextAccess, previous: oldValue, key: Self.chatWorkingTextKey) }
    }
    @Published var externalWorkingTextAccess: Bool {
        didSet { save(externalWorkingTextAccess, previous: oldValue, key: Self.externalWorkingTextKey) }
    }
    /// Every effective grant change revokes captures admitted under an earlier revision.
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var invalidStoredKeys: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var invalid: Set<String> = []
        func load(_ key: String, default defaultValue: Bool) -> Bool {
            guard let stored = defaults.object(forKey: key) else { return defaultValue }
            guard let boolean = stored as? NSNumber,
                CFGetTypeID(boolean) == CFBooleanGetTypeID()
            else {
                invalid.insert(key)
                return false
            }
            return boolean.boolValue
        }
        chatStateAccess = load(Self.chatStateKey, default: true)
        externalStateAccess = load(Self.externalStateKey, default: false)
        chatWorkingTextAccess = load(Self.chatWorkingTextKey, default: false)
        externalWorkingTextAccess = load(Self.externalWorkingTextKey, default: false)
        invalidStoredKeys = invalid
    }

    func allowsState(for caller: AgentContextCaller) -> Bool {
        switch caller {
        case .chat: chatStateAccess
        case .external: externalStateAccess
        }
    }

    func allowsWorkingText(for caller: AgentContextCaller) -> Bool {
        switch caller {
        case .chat: chatWorkingTextAccess
        case .external: externalWorkingTextAccess
        }
    }

    private func save(_ value: Bool, previous: Bool, key: String) {
        if value != previous { revision &+= 1 }
        defaults.set(value, forKey: key)
        invalidStoredKeys.remove(key)
    }
}
