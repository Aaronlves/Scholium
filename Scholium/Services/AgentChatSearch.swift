import Foundation
import ScholiumContracts

/// A read-only projection of public conversation content; no index or runtime requests.
enum AgentChatSearch {
    static func query(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ text: String, query: String) -> Bool {
        match(text, query: query) != nil
    }

    static func passage(in message: AgentChatMessage, query: String) -> String? {
        guard let match = firstMatch(in: message, query: query) else { return nil }
        return snippet(match.text, range: match.range)
    }

    static func contains(_ message: AgentChatMessage, query: String) -> Bool {
        firstMatch(in: message, query: query) != nil
    }

    static func contains(_ conversation: AgentChatConversation, query: String) -> Bool {
        query.isEmpty || matches(conversation.title, query: query)
            || conversation.messages.contains { contains($0, query: query) }
    }

    private typealias Match = (text: String, range: NSRange)

    private static func match(_ text: String, query: String) -> Match? {
        guard let range = matchedRange(in: text, query: query) else { return nil }
        return (text, range)
    }

    /// Native search avoids a Swift index scan for absent text. Only actual
    /// candidates need Character-boundary validation, preserving String search
    /// semantics when a scalar is also part of an extended grapheme cluster.
    static func matchedRange(in text: String, query: String) -> NSRange? {
        guard !text.isEmpty, !query.isEmpty else { return nil }
        let source = text as NSString
        var remaining = NSRange(location: 0, length: source.length)
        while remaining.length > 0 {
            let candidate = source.range(of: query, options: .caseInsensitive, range: remaining)
            guard candidate.location != NSNotFound else { return nil }
            if characterRange(candidate, in: text) != nil { return candidate }
            // Advance from the start, retaining overlapping later candidates.
            let next = candidate.location + 1
            remaining = NSRange(location: next, length: source.length - next)
        }
        return nil
    }

    /// Visit the retained public fields in their existing passage order. A
    /// predicate stops at the first match without building a field array or
    /// formatting a snippet; a displayed passage uses that same original range.
    private static func firstMatch(in message: AgentChatMessage, query: String) -> Match? {
        guard !query.isEmpty else { return nil }
        if let result = match(message.text, query: query) { return result }
        for quote in message.replyQuotes ?? [] {
            if let result = match(quote.text, query: query) { return result }
        }
        if let target = message.coordinationTarget {
            if let result = match(target.name ?? "", query: query) { return result }
            if let result = match(target.childThreadID, query: query) { return result }
            if let result = match(target.parentThreadID, query: query) { return result }
        }
        for method in message.methods ?? [] {
            if let result = match(method.title, query: query) { return result }
        }
        if let plan = message.plan {
            if let result = match(plan.explanation ?? "", query: query) { return result }
            for step in plan.steps {
                if let result = match(step.step, query: query) { return result }
            }
        }
        if let activity = message.activity {
            if let result = match(activity.subject, query: query) { return result }
            if let result = match(activity.detail, query: query) { return result }
            for file in activity.files {
                if let result = match(file.path, query: query) { return result }
            }
            if let report = activity.delegation {
                if let result = match(report.prompt ?? "", query: query) { return result }
                if let result = match(report.senderThreadID, query: query) { return result }
                for target in report.targets {
                    if let result = match(target.id, query: query) { return result }
                    if let result = match(target.path ?? "", query: query) { return result }
                    if let result = match(target.message ?? "", query: query) { return result }
                }
            }
        }
        for material in message.attachments {
            if let result = match(material.relativePath, query: query) { return result }
            if let result = match(material.text, query: query) { return result }
        }
        for material in message.localMaterials {
            if let result = match(material.fileName, query: query) { return result }
            if let result = match(AgentChatLocalMaterialLabels.title(material), query: query) { return result }
            if let result = match(material.text, query: query) { return result }
            for page in material.pages {
                if let result = match(page.text, query: query) { return result }
            }
        }
        return nil
    }

    static func snippet(_ text: String, query: String) -> String {
        guard let match = match(text, query: query) else { return "" }
        return snippet(match.text, range: match.range) ?? ""
    }

    /// Convert a displayed match in its original source. Invalid offsets and
    /// partial Character ranges never supply a passage.
    static func snippet(_ text: String, range: NSRange) -> String? {
        guard let range = characterRange(range, in: text) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -32, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 72, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…")
            + text[start..<end].components(separatedBy: .newlines).joined(separator: " ")
            + (end == text.endIndex ? "" : "…")
    }

    private static func characterRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        let count = text.utf16.count
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
            range.location <= count, range.length <= count - range.location,
            let range = Range(range, in: text),
            let lower = range.lowerBound.samePosition(in: text),
            let upper = range.upperBound.samePosition(in: text)
        else { return nil }
        return lower..<upper
    }
}

/// Only navigation state is mutable. Results always derive from the current public messages.
struct AgentChatFindState {
    var query = ""
    private(set) var messageIDs: [String] = []
    private(set) var selectedID: String?
    var position: Int? { selectedID.flatMap { messageIDs.firstIndex(of: $0) }.map { $0 + 1 } }

    mutating func refresh(messages: [AgentChatMessage], reset: Bool = false) {
        let needle = AgentChatSearch.query(query)
        messageIDs = needle.isEmpty ? [] : messages.compactMap { AgentChatSearch.contains($0, query: needle) ? $0.id : nil }
        if reset || !messageIDs.contains(selectedID ?? "") { selectedID = messageIDs.first }
    }

    mutating func move(backwards: Bool) {
        guard !messageIDs.isEmpty else {
            selectedID = nil
            return
        }
        let index = selectedID.flatMap { messageIDs.firstIndex(of: $0) } ?? (backwards ? 0 : -1)
        selectedID = messageIDs[(index + (backwards ? -1 : 1) + messageIDs.count) % messageIDs.count]
    }
}
