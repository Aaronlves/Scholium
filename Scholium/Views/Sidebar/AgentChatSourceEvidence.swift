import Foundation
import ScholiumContracts

/// A reply-local projection; no new source store, citation authority or runtime state.
struct AgentChatReplySourceContext {
    let messages: [AgentChatMessage]
    init(reply: AgentChatMessage, history: [AgentChatMessage]) {
        guard let turn = reply.turnID, let end = history.firstIndex(where: { $0.id == reply.id }) else {
            messages = []
            return
        }
        messages = history[..<end].filter { $0.turnID == turn }
    }
    var attachments: [AgentChatAttachment] {
        var seen: Set<UUID> = []
        return messages.filter { $0.role == .user }.flatMap(\.attachments).filter { seen.insert($0.id).inserted }
    }
    var localMaterials: [AgentChatLocalMaterial] {
        var seen: Set<UUID> = []
        return messages.filter { $0.role == .user }.flatMap(\.localMaterials).filter { seen.insert($0.id).inserted }
    }
    var hasMaterials: Bool { !attachments.isEmpty || !localMaterials.isEmpty }

    func evidence(for url: URL) -> AgentChatSourceEvidence {
        let completed = messages.compactMap(\.activity).filter { $0.status == .completed }
        if let citation = try? ZoteroReference(url: url) {
            let reports: [ZoteroReadReport] = completed.compactMap { activity in
                guard activity.source == .runtime, activity.kind == .tool,
                    case .zoteroReadReport(let report) = activity.sourceObservation, report.matches(citation)
                else { return nil }
                return report
            }
            return reports.isEmpty ? .unrecorded : .zotero(reports)
        }
        if let reference = AgentChatReference.parse(url) {
            let observed: [AgentChatSourceObservation.NoteRead] = completed.compactMap { activity in
                guard activity.source == .scholium, activity.kind == .read,
                    case .noteRead(let read) = activity.sourceObservation,
                    read.noteID == reference.noteID, read.startLine > 0, read.lineCount >= 0,
                    read.lineCount <= 1_000, read.startLine < Int.max - read.lineCount
                else { return nil }
                return read
            }
            let matching = observed.filter { reference.revision == nil || $0.fingerprint.sha256 == reference.revision }
            guard let last = matching.last else { return observed.isEmpty ? .unrecorded : .differentRevision }
            return .note(.init(reads: matching.filter { $0.fingerprint == last.fingerprint }, citedLine: reference.line))
        }
        let access: [AgentChatSourceObservation.WebAccess] = completed.compactMap { activity in
            guard activity.source == .runtime, activity.kind == .webSearch,
                case .webAccess(let access) = activity.sourceObservation,
                Self.webIdentity(access.url) == Self.webIdentity(url), Self.webIdentity(url) != nil
            else { return nil }
            return access
        }
        return access.isEmpty ? .unrecorded : .web(access)
    }
    private static func webIdentity(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        parts.fragment = nil
        return parts.url
    }
}

enum AgentChatSourceEvidence {
    case unrecorded
    case differentRevision
    case note(AgentChatNoteReadCoverage)
    case web([AgentChatSourceObservation.WebAccess])
    case zotero([ZoteroReadReport])
}

struct AgentChatNoteReadCoverage {
    let reads: [AgentChatSourceObservation.NoteRead]
    let citedLine: Int?
    var ranges: [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for read in reads.filter({ $0.lineCount > 0 }).sorted(by: { $0.startLine < $1.startLine }) {
            let next = read.startLine...(read.startLine + read.lineCount - 1)
            if let last = result.last, next.lowerBound <= last.upperBound + 1 {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, next.upperBound)
            } else {
                result.append(next)
            }
        }
        return result
    }
    var coversCitedLine: Bool { citedLine.map { line in ranges.contains { $0.contains(line) } } ?? true }
    var coversWholeSource: Bool {
        guard ranges.count == 1, let range = ranges.first, range.lowerBound == 1 else { return false }
        return reads.contains { $0.reachedEnd && $0.startLine + $0.lineCount - 1 == range.upperBound }
    }
    var lineDescription: String {
        ranges.map { $0.lowerBound == $0.upperBound ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: ", ")
    }
}
