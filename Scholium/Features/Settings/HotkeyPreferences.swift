import AppKit
import Foundation
import SwiftUI

enum ScholiumHotkeyCategory: String, CaseIterable, Identifiable, Sendable {
    case workspace
    case document
    case research

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .workspace: "Workspace"
        case .document: "Document"
        case .research: "Research"
        }
    }
}

enum ScholiumHotkeyCommand: String, CaseIterable, Codable, Identifiable, Sendable {
    case searchResearch
    case toggleLibrary
    case toggleResearchInspector
    case toggleReviewEdit
    case showSource
    case commentOnSelection
    case showAttention
    case showTriptychRecords

    var id: String { rawValue }

    var category: ScholiumHotkeyCategory {
        switch self {
        case .searchResearch, .toggleLibrary, .toggleResearchInspector,
             .showAttention:
            .workspace
        case .toggleReviewEdit, .showSource, .commentOnSelection:
            .document
        case .showTriptychRecords:
            .research
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .searchResearch: "Search Research"
        case .toggleLibrary: "Show or Hide Library"
        case .toggleResearchInspector: "Show or Hide Research Inspector"
        case .toggleReviewEdit: "Switch Review and Edit"
        case .showSource: "Show Source"
        case .commentOnSelection: "Comment on Selection"
        case .showAttention: "Show Attention"
        case .showTriptychRecords: "Show Triptych Records"
        }
    }

    var menuPath: LocalizedStringResource {
        switch self {
        case .searchResearch: "View → Search"
        case .toggleLibrary: "View → Sidebar"
        case .toggleResearchInspector: "View → Research Inspector"
        case .toggleReviewEdit: "View → Document Mode"
        case .showSource: "View → Document Mode → Source"
        case .commentOnSelection: "Insert → Comment on Selection"
        case .showAttention: "Window → Notifications"
        case .showTriptychRecords: "Research → Triptych Records"
        }
    }

    var defaultBinding: ScholiumHotkeyBinding? {
        switch self {
        case .searchResearch:
            ScholiumHotkeyBinding(key: "f", modifiers: [.shift, .command])
        case .toggleLibrary:
            ScholiumHotkeyBinding(key: "s", modifiers: [.control, .command])
        case .toggleResearchInspector:
            ScholiumHotkeyBinding(key: "b", modifiers: [.option, .command])
        case .toggleReviewEdit:
            ScholiumHotkeyBinding(key: "r", modifiers: [.command])
        case .showSource, .commentOnSelection, .showAttention,
             .showTriptychRecords:
            nil
        }
    }
}

struct ScholiumHotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }

    static func from(_ flags: NSEvent.ModifierFlags) -> Self {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: Self = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    var displayPrefix: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct ScholiumHotkeyBinding: Codable, Hashable, Sendable {
    let key: String
    let modifiers: ScholiumHotkeyModifiers

    init?(key: String, modifiers: ScholiumHotkeyModifiers) {
        let normalized = key.lowercased()
        guard normalized.count == 1,
              let character = normalized.first,
              Self.allowedCharacters.contains(character) else { return nil }
        self.key = normalized
        self.modifiers = modifiers
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key.first!)
    }

    var displayName: String {
        modifiers.displayPrefix + key.uppercased()
    }

    var isStructurallyValid: Bool {
        key.count == 1
            && key.first.map(Self.allowedCharacters.contains) == true
            && modifiers.contains(.command)
    }

    private static let allowedCharacters = Set(
        "abcdefghijklmnopqrstuvwxyz0123456789-=[];',./\\`".map { $0 }
    )
}

enum ScholiumHotkeyValidationIssue: Equatable, Sendable {
    case commandRequired
    case systemReserved
    case conflict(ScholiumHotkeyCommand)

    var message: String {
        switch self {
        case .commandRequired:
            String(localized: "Include the Command key in a Scholium hotkey.", table: "Localizable", bundle: .module)
        case .systemReserved:
            String(localized: "This shortcut is reserved for a standard macOS command.", table: "Localizable", bundle: .module)
        case .conflict(let command):
            String(
                localized: "This shortcut is already assigned to \(String(localized: command.title)).",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

enum ScholiumHotkeyPreferences {
    static let defaultsKey = "scholium.hotkeys.v1"

    private struct Payload: Codable {
        var overrides: [String: ScholiumHotkeyBinding] = [:]
        var disabled: Set<String> = []
    }

    static func binding(
        for command: ScholiumHotkeyCommand,
        data: Data
    ) -> ScholiumHotkeyBinding? {
        let payload = decode(data)
        if payload.disabled.contains(command.rawValue) { return nil }
        return payload.overrides[command.rawValue] ?? command.defaultBinding
    }

    static func data(
        setting binding: ScholiumHotkeyBinding?,
        for command: ScholiumHotkeyCommand,
        in data: Data
    ) -> Data {
        var payload = decode(data)
        payload.overrides.removeValue(forKey: command.rawValue)
        payload.disabled.remove(command.rawValue)

        if binding == command.defaultBinding {
            return encode(payload)
        }
        if let binding {
            payload.overrides[command.rawValue] = binding
        } else {
            payload.disabled.insert(command.rawValue)
        }
        return encode(payload)
    }

    static func isCustomized(
        _ command: ScholiumHotkeyCommand,
        data: Data
    ) -> Bool {
        let payload = decode(data)
        return payload.overrides[command.rawValue] != nil
            || payload.disabled.contains(command.rawValue)
    }

    static func validationIssue(
        for binding: ScholiumHotkeyBinding,
        command: ScholiumHotkeyCommand,
        data: Data
    ) -> ScholiumHotkeyValidationIssue? {
        guard binding.modifiers.contains(.command) else { return .commandRequired }
        if systemReservedBindings.contains(binding) { return .systemReserved }
        if let conflict = ScholiumHotkeyCommand.allCases.first(where: {
            $0 != command && self.binding(for: $0, data: data) == binding
        }) {
            return .conflict(conflict)
        }
        return nil
    }

    static var defaultData: Data { Data() }

    private static func decode(_ data: Data) -> Payload {
        guard !data.isEmpty,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload() }

        let validOverrides = payload.overrides.filter { rawCommand, binding in
            ScholiumHotkeyCommand(rawValue: rawCommand) != nil
                && binding.isStructurallyValid
        }
        let validDisabled = payload.disabled.filter {
            ScholiumHotkeyCommand(rawValue: $0) != nil
        }
        return Payload(
            overrides: validOverrides,
            disabled: Set(validDisabled)
        )
    }

    private static func encode(_ payload: Payload) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }

    private static let systemReservedBindings: Set<ScholiumHotkeyBinding> = {
        func binding(
            _ key: String,
            _ modifiers: ScholiumHotkeyModifiers = [.command]
        ) -> ScholiumHotkeyBinding {
            ScholiumHotkeyBinding(key: key, modifiers: modifiers)!
        }
        return [
            binding(","), binding("q"), binding("h"), binding("m"),
            binding("w"), binding("n"), binding("o"), binding("p"),
            binding("s"), binding("a"), binding("x"), binding("c"),
            binding("v"), binding("z"), binding("f"), binding("g"),
            binding("b"), binding("i"), binding("u"), binding("t"),
            binding("k"),
            binding("z", [.shift, .command]),
            binding("g", [.shift, .command]),
            binding("n", [.shift, .command]),
            binding("s", [.shift, .command]),
            binding("w", [.shift, .command]),
            binding("f", [.control, .command]),
        ]
    }()
}

extension View {
    @ViewBuilder
    func scholiumKeyboardShortcut(_ binding: ScholiumHotkeyBinding?) -> some View {
        if let binding {
            keyboardShortcut(binding.keyEquivalent, modifiers: binding.modifiers.eventModifiers)
        } else {
            self
        }
    }
}
