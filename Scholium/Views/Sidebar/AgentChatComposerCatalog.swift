import Foundation
import ScholiumContracts

/// Local candidates only. Catalog construction and matching neither execute
/// commands nor prepare materials; the composer retains action admission.
enum AgentChatComposerCatalog {
    typealias Candidate = AgentChatComposerCandidate

    static func commands(isBusy: Bool, hasChanges: Bool, hasAgents: Bool) -> [Candidate] {
        var candidates: [Candidate] = [
            command("context", "Context", "text.alignleft", .context),
            command("usage", "Account Usage", "chart.bar", .usage),
            command("find", "Find in Conversation", "magnifyingglass", .find),
            command("outline", "Conversation Outline", "list.bullet", .outline),
        ]
        if hasChanges { candidates.append(command("changes", "Conversation Changes", "pencil.line", .changes)) }
        if hasAgents { candidates.append(command("agents", "Agents", "person.2", .agents)) }
        candidates.append(command("skills", "Skills", "square.stack", .methods))
        if !isBusy {
            candidates += AgentChatPreferences.WebSearch.allCases.map { mode in
                let id: String
                switch mode {
                case .runtimeDefault: id = "web-default"
                case .disabled: id = "web-off"
                case .cached: id = "web-cached"
                case .live: id = "web-live"
                }
                return Candidate(
                    id: id, title: "/" + id,
                    detail: ScholiumL10n.string("Web Search") + " · " + AgentChatControlLabels.webSearch(mode),
                    symbol: "globe", action: .webSearch(mode))
            }
        }
        return candidates
    }

    static func materials(preorderedNotes notes: [WorkspaceCatalogNote]) -> [Candidate] {
        let noteCandidates = notes.map { note in
            Candidate(
                id: "material:note:" + note.id, title: note.title, detail: note.reference.relativePath,
                symbol: "doc.text", action: .note(note))
        }
        return noteCandidates + [
            .init(
                id: "material:file", title: ScholiumL10n.string("Choose File…"), detail: "",
                symbol: "folder", action: .file),
            .init(
                id: "material:note-picker", title: ScholiumL10n.string("Choose Note…"), detail: "",
                symbol: "doc.text", action: .notePicker),
            .init(
                id: "material:selection", title: ScholiumL10n.string("Add Selection to Chat"), detail: "",
                symbol: "text.badge.plus", action: .selection),
        ]
    }

    static func skills(methods: [AgentChatMethod], canRefresh: Bool) -> [Candidate] {
        var candidates = methods.filter { !$0.isProtected && $0.enabled }.map { method in
            Candidate(
                id: "skill:" + method.id, title: method.selection.title, detail: method.description,
                symbol: "square.stack", action: .method(method.selection))
        }
        if canRefresh {
            candidates.append(
                .init(
                    id: "skill-action:refresh", title: ScholiumL10n.string("Refresh Skills"), detail: "",
                    symbol: "arrow.clockwise", action: .refreshMethods))
        }
        candidates.append(
            .init(
                id: "skill-action:manage", title: ScholiumL10n.string("Manage Skills…"), detail: "",
                symbol: "gearshape", action: .manageMethods))
        return candidates
    }

    static func matching(_ candidates: [Candidate], query: String) -> [Candidate] {
        let needle = AgentChatSearch.query(query)
        guard !needle.isEmpty else { return candidates }
        var exact: [Candidate] = []
        var prefix: [Candidate] = []
        var other: [Candidate] = []
        for candidate in candidates {
            var isExact = false
            var isPrefix = false
            var contains = false
            // One search per field establishes presence and prefix together.
            // Compare only matching fields to retain Foundation's exact tier.
            for field in [candidate.title, candidate.id, candidate.detail] {
                guard let range = field.range(of: needle, options: .caseInsensitive) else { continue }
                if field.compare(needle, options: .caseInsensitive) == .orderedSame {
                    isExact = true
                    break
                }
                isPrefix = isPrefix || range.lowerBound == field.startIndex
                contains = true
            }
            if isExact {
                exact.append(candidate)
            } else if isPrefix {
                prefix.append(candidate)
            } else if contains {
                other.append(candidate)
            }
        }
        return exact + prefix + other
    }

    private static func command(
        _ id: String, _ label: String.LocalizationValue, _ symbol: String, _ action: Candidate.Action
    ) -> Candidate {
        .init(id: id, title: "/" + id, detail: ScholiumL10n.string(label), symbol: symbol, action: action)
    }
}
