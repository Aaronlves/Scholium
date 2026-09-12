import AppKit
import Foundation
import SwiftUI

enum ScholiumHotkeyCategory: String, CaseIterable, Identifiable, Sendable {
    case workspace
    case document

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .workspace: "Workspace"
        case .document: "Document"
        }
    }
}

// One registry owns every Scholium menu shortcut. Standard macOS editing
// remains system-owned; fixed commands participate in conflict validation
// without becoming user-remappable.
enum ScholiumHotkeyCommand: String, CaseIterable, Codable, Identifiable, Sendable {
    case searchResearch
    case toggleLibrary
    case toggleResearchInspector
    case toggleReviewEdit
    case showSource
    case showAttention
    case insertFootnote
    case insertInlineFootnote

    case newWindow
    case closeTab
    case newNote
    case moveToTrash
    case pasteMarkdown
    case find
    case findNext
    case findPrevious
    case useSelectionForFind
    case bold
    case italic
    case insertLink
    case nextTab
    case previousTab
    case goToFrontmatter
    case addSelectionToChat
    case increaseTextSize
    case decreaseTextSize
    case actualTextSize

    static var customizableCommands: [Self] { allCases.filter(\.isCustomizable) }

    var isCustomizable: Bool {
        switch self {
        case .searchResearch, .toggleLibrary, .toggleResearchInspector,
            .toggleReviewEdit, .showSource, .showAttention,
            .insertFootnote, .insertInlineFootnote:
            true
        default: false
        }
    }

    var id: String { rawValue }

    var category: ScholiumHotkeyCategory {
        switch self {
        case .searchResearch, .toggleLibrary, .toggleResearchInspector,
            .showAttention, .newWindow, .newNote, .closeTab, .nextTab, .previousTab:
            .workspace
        default:
            .document
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .newWindow: "New Window"
        case .closeTab: "Close Tab"
        case .newNote: "New Note"
        case .moveToTrash: "Move to Trash…"
        case .pasteMarkdown: "Paste as Markdown"
        case .find: "Find…"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .useSelectionForFind: "Use Selection for Find"
        case .bold: "Bold"
        case .italic: "Italic"
        case .insertLink: "Link"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .goToFrontmatter: "Go to Frontmatter"
        case .addSelectionToChat: "Add Selection to Chat"
        case .increaseTextSize: "Increase Text Size"
        case .decreaseTextSize: "Decrease Text Size"
        case .actualTextSize: "Actual Size (100%)"
        case .searchResearch: "Search Research"
        case .toggleLibrary: "Show or Hide Library"
        case .toggleResearchInspector: "Show or Hide Research Inspector"
        case .toggleReviewEdit: "Switch Review and Edit"
        case .showSource: "Show Source"
        case .showAttention: "Show Attention"
        case .insertFootnote: "Insert Footnote"
        case .insertInlineFootnote: "Insert Inline Footnote"
        }
    }

    var menuPath: LocalizedStringResource {
        switch self {
        case .newWindow: "File → New Window"
        case .closeTab: "File → Close Tab"
        case .newNote: "File → New Note"
        case .moveToTrash: "File → Move to Trash…"
        case .pasteMarkdown: "Edit → Paste as Markdown"
        case .find: "Edit → Find → Find…"
        case .findNext: "Edit → Find → Find Next"
        case .findPrevious: "Edit → Find → Find Previous"
        case .useSelectionForFind: "Edit → Find → Use Selection for Find"
        case .bold: "Format → Bold"
        case .italic: "Format → Italic"
        case .insertLink: "Insert → Link"
        case .nextTab: "Window → Next Tab"
        case .previousTab: "Window → Previous Tab"
        case .goToFrontmatter: "View → Go to Frontmatter"
        case .addSelectionToChat: "Research → Add Selection to Chat"
        case .increaseTextSize: "View → Document Text Size → Increase Text Size"
        case .decreaseTextSize: "View → Document Text Size → Decrease Text Size"
        case .actualTextSize: "View → Document Text Size → Actual Size (100%)"
        case .searchResearch: "View → Search"
        case .toggleLibrary: "View → Sidebar"
        case .toggleResearchInspector: "View → Research Inspector"
        case .toggleReviewEdit: "View → Edit / Review"
        case .showSource: "View → Document Mode → Source"
        case .showAttention: "Window → Notifications"
        case .insertFootnote: "Insert → Footnote"
        case .insertInlineFootnote: "Insert → Inline Footnote"
        }
    }

    var defaultBinding: ScholiumHotkeyBinding? {
        switch self {
        case .newWindow:
            ScholiumHotkeyBinding(key: "n", modifiers: [.command])
        case .closeTab:
            ScholiumHotkeyBinding(key: "w", modifiers: [.shift, .command])
        case .newNote:
            ScholiumHotkeyBinding(key: "n", modifiers: [.shift, .command])
        case .moveToTrash:
            ScholiumHotkeyBinding(key: "\u{7f}", modifiers: [.command])
        case .pasteMarkdown:
            ScholiumHotkeyBinding(key: "v", modifiers: [.shift, .command])
        case .find:
            ScholiumHotkeyBinding(key: "f", modifiers: [.command])
        case .findNext:
            ScholiumHotkeyBinding(key: "g", modifiers: [.command])
        case .findPrevious:
            ScholiumHotkeyBinding(key: "g", modifiers: [.shift, .command])
        case .useSelectionForFind:
            ScholiumHotkeyBinding(key: "e", modifiers: [.command])
        case .bold:
            ScholiumHotkeyBinding(key: "b", modifiers: [.command])
        case .italic:
            ScholiumHotkeyBinding(key: "i", modifiers: [.command])
        case .insertLink:
            ScholiumHotkeyBinding(key: "k", modifiers: [.command])
        case .nextTab:
            ScholiumHotkeyBinding(key: "\t", modifiers: [.control])
        case .previousTab:
            ScholiumHotkeyBinding(key: "\t", modifiers: [.control, .shift])
        case .goToFrontmatter:
            ScholiumHotkeyBinding(key: "f", modifiers: [.option, .shift, .command])
        case .addSelectionToChat:
            ScholiumHotkeyBinding(key: "l", modifiers: [.shift, .command])
        case .increaseTextSize:
            ScholiumHotkeyBinding(key: "=", modifiers: [.command])
        case .decreaseTextSize:
            ScholiumHotkeyBinding(key: "-", modifiers: [.command])
        case .actualTextSize:
            ScholiumHotkeyBinding(key: "0", modifiers: [.command])
        case .searchResearch:
            ScholiumHotkeyBinding(key: "f", modifiers: [.shift, .command])
        case .toggleLibrary:
            ScholiumHotkeyBinding(key: "s", modifiers: [.control, .command])
        case .toggleResearchInspector:
            ScholiumHotkeyBinding(key: "b", modifiers: [.option, .command])
        case .toggleReviewEdit:
            ScholiumHotkeyBinding(key: "r", modifiers: [.command])
        case .insertFootnote:
            ScholiumHotkeyBinding(key: "n", modifiers: [.option, .command])
        case .insertInlineFootnote:
            ScholiumHotkeyBinding(key: "n", modifiers: [.option, .shift, .command])
        case .showSource, .showAttention:
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
            Self.allowedCharacters.contains(character) || character == "\t" || character == "\u{7f}"
        else { return nil }
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
            && modifiers.subtracting([.control, .option, .shift, .command]).isEmpty
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
            String(localized: "Include the Command key in a Scholium shortcut.", table: "Localizable", bundle: .module)
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
        guard command.isCustomizable else { return command.defaultBinding }
        let payload = decode(data)
        if payload.disabled.contains(command.rawValue) { return nil }
        guard let override = payload.overrides[command.rawValue] else { return command.defaultBinding }
        guard !systemReservedBindings.contains(override),
            !ScholiumHotkeyCommand.customizableCommands.contains(where: { peer in
                peer != command && !payload.disabled.contains(peer.rawValue)
                    && (payload.overrides[peer.rawValue] ?? peer.defaultBinding) == override
            })
        else { return nil }
        return override
    }

    @MainActor
    static func isMenuShortcut(_ event: NSEvent, defaults: UserDefaults = .standard) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = ScholiumHotkeyModifiers.from(event.modifierFlags)
        let key =
            event.characters(byApplyingModifiers: .command)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        let data = defaults.data(forKey: defaultsKey) ?? defaultData
        return ScholiumHotkeyCommand.allCases.contains {
            guard let binding = binding(for: $0, data: data) else { return false }
            return binding.key == key && binding.modifiers == modifiers
        }
    }

    static func data(
        setting binding: ScholiumHotkeyBinding?,
        for command: ScholiumHotkeyCommand,
        in data: Data
    ) -> Data {
        guard command.isCustomizable else { return data }
        if let binding, validationIssue(for: binding, command: command, data: data) != nil {
            return data
        }
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
        guard binding.isStructurallyValid else { return .systemReserved }
        if systemReservedBindings.contains(binding) { return .systemReserved }
        let payload = decode(data)
        if let conflict = ScholiumHotkeyCommand.customizableCommands.first(where: {
            $0 != command && !payload.disabled.contains($0.rawValue)
                && (payload.overrides[$0.rawValue] ?? $0.defaultBinding) == binding
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
            ScholiumHotkeyCommand(rawValue: rawCommand)?.isCustomizable == true
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

    // Fixed application commands are derived from the same menu registry.
    // Only system-owned and field-local bindings are enumerated separately.
    private static let systemReservedBindings: Set<ScholiumHotkeyBinding> = {
        func binding(
            _ key: String,
            _ modifiers: ScholiumHotkeyModifiers = [.command]
        ) -> ScholiumHotkeyBinding {
            ScholiumHotkeyBinding(key: key, modifiers: modifiers)!
        }
        return Set(ScholiumHotkeyCommand.allCases.filter { !$0.isCustomizable }.compactMap(\.defaultBinding)).union([
            binding(","), binding("q"), binding("h"), binding("m"),
            binding("w"), binding("o"), binding("p"),
            binding("s"), binding("a"), binding("x"), binding("c"),
            binding("v"), binding("z"), binding("u"), binding("t"),
            binding("z", [.shift, .command]),
            binding("s", [.shift, .command]),
            binding("f", [.control, .command]),
            binding("h", [.option, .command]),
            binding("m", [.option, .command]),
            binding("w", [.option, .command]),
            binding("r", [.shift, .command]),  // Chat selection quotation
        ])
    }()
}

extension View {
    func scholiumKeyboardShortcut(_ command: ScholiumHotkeyCommand) -> some View {
        modifier(ScholiumMenuShortcutModifier(command: command))
    }
}

private struct ScholiumMenuShortcutModifier: ViewModifier {
    let command: ScholiumHotkeyCommand
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var data = ScholiumHotkeyPreferences.defaultData

    func body(content: Content) -> some View {
        if let binding = ScholiumHotkeyPreferences.binding(for: command, data: data) {
            content.keyboardShortcut(binding.keyEquivalent, modifiers: binding.modifiers.eventModifiers)
        } else {
            content
        }
    }
}
