import Foundation
import Observation
import ScholiumContracts

enum ResearchRecordDateFilter: String, CaseIterable, Equatable, Sendable {
    case any
    case today
    case pastSevenDays
    case pastThirtyDays
}

enum ResearchRecordParticipantFilter: Hashable, Sendable {
    case author(PortableResearchStatementAuthor)
    case note(UUID)
}

struct ResearchRecordNoteOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let role: ResearchActionTargetRole
    let isTombstone: Bool
}

struct ResearchRecordParticipantOption: Identifiable, Equatable, Sendable {
    let filter: ResearchRecordParticipantFilter
    let title: String
    let isTombstone: Bool

    var id: ResearchRecordParticipantFilter { filter }
}

struct ResearchRecordIndexEntry: Identifiable, Equatable, Sendable {
    let record: PortableResearchRecord
    let contextTitle: String
    let actionID: ResearchActionID
    let skillID: String?
    let skillVersion: String?
    let noteParticipants: [PortableResearchNoteRevision]
    let authorParticipants: [PortableResearchStatementAuthor]
    fileprivate let normalizedSearchCorpus: String

    var id: UUID { record.id }
    var finishedAt: Date { record.finishedAt }
    var isPinned: Bool { record.isPinned }
}

extension PortableResearchRecord {
    var researchRecordContextParticipant: PortableResearchNoteRevision? {
        if let primaryNoteID,
           let primary = participatingNotes.first(where: {
               $0.noteID == primaryNoteID
           }) {
            return primary
        }
        let liveParticipants = participatingNotes.filter { !$0.isTombstone }
        return liveParticipants.count == 1 ? liveParticipants.first : nil
    }

    var researchRecordContextTitle: String? {
        if let primary = researchRecordContextParticipant {
            return primary.title
        }
        let liveTitles = participatingNotes
            .filter { !$0.isTombstone }
            .map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return liveTitles.isEmpty ? nil : liveTitles.joined(separator: ", ")
    }
}

/// A disposable in-memory projection of finished portable records. The index
/// owns no files, authorization, or record mutation; rebuilding from the same
/// portable records yields the same ordered entries.
struct ResearchRecordDerivedIndex: Equatable, Sendable {
    private(set) var entries: [ResearchRecordIndexEntry]
    private let recordsByID: [UUID: PortableResearchRecord]

    init(records: [PortableResearchRecord]) {
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: {
            first,
            second in
            if first.finishedAt != second.finishedAt {
                return first.finishedAt > second.finishedAt ? first : second
            }
            return first.id.uuidString < second.id.uuidString ? first : second
        })
        recordsByID = unique
        entries = unique.values.map(Self.makeEntry).sorted(by: Self.ordersEntries)
    }

    func record(id: UUID) -> PortableResearchRecord? {
        recordsByID[id]
    }

    func replacing(_ record: PortableResearchRecord) -> Self {
        var records = Array(recordsByID.values)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        return Self(records: records)
    }

    func query(
        text: String,
        noteID: UUID?,
        dateFilter: ResearchRecordDateFilter,
        skillID: String?,
        actionID: ResearchActionID?,
        participant: ResearchRecordParticipantFilter?,
        now: Date,
        calendar: Calendar
    ) -> [ResearchRecordIndexEntry] {
        let terms = Self.normalized(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let startOfToday = calendar.startOfDay(for: now)
        let cutoff: Date? = switch dateFilter {
        case .any: nil
        case .today: startOfToday
        case .pastSevenDays: calendar.date(byAdding: .day, value: -7, to: now)
        case .pastThirtyDays: calendar.date(byAdding: .day, value: -30, to: now)
        }

        return entries.filter { entry in
            if let noteID,
               !entry.noteParticipants.contains(where: { $0.noteID == noteID }) {
                return false
            }
            if let cutoff, entry.finishedAt < cutoff { return false }
            if let skillID, entry.skillID != skillID { return false }
            if let actionID, entry.actionID != actionID { return false }
            if let participant {
                switch participant {
                case .author(let author):
                    guard entry.authorParticipants.contains(author) else { return false }
                case .note(let noteID):
                    guard entry.noteParticipants.contains(where: {
                        $0.noteID == noteID
                    }) else { return false }
                }
            }
            return terms.allSatisfy(entry.normalizedSearchCorpus.contains)
        }
    }

    private static func makeEntry(
        _ record: PortableResearchRecord
    ) -> ResearchRecordIndexEntry {
        let actionID = record.kind == .discussion
            ? ResearchActionID.discuss
            : record.action?.actionID ?? .discuss
        let contextTitle = record.researchRecordContextTitle
        let authors = Set(record.statements.map(\.author)).sorted {
            $0.rawValue < $1.rawValue
        }
        let searchableParts = [
            contextTitle,
            actionID.rawValue,
            record.method?.packageID,
            record.method?.version,
            record.sourceReference?.displayName,
        ].compactMap { $0 }
            + record.participatingNotes.flatMap {
                [$0.title, $0.role.rawValue]
            }
            + record.statements.flatMap {
                [$0.author.rawValue, $0.kind.rawValue, $0.attribution, $0.text]
            }
            + record.actuallyUsedMaterials.flatMap {
                [$0.title, $0.role.rawValue]
            }

        return ResearchRecordIndexEntry(
            record: record,
            contextTitle: contextTitle ?? actionID.rawValue,
            actionID: actionID,
            skillID: record.method?.packageID,
            skillVersion: record.method?.version,
            noteParticipants: record.participatingNotes,
            authorParticipants: authors,
            normalizedSearchCorpus: normalized(searchableParts.joined(separator: "\n"))
        )
    }

    private static func ordersEntries(
        _ lhs: ResearchRecordIndexEntry,
        _ rhs: ResearchRecordIndexEntry
    ) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

@MainActor
@Observable
final class ResearchRecordBrowserModel {
    private(set) var visibleEntries: [ResearchRecordIndexEntry] = []
    private(set) var selectedRecord: PortableResearchRecord?
    private(set) var noteOptions: [ResearchRecordNoteOption] = []
    private(set) var skillOptions: [String] = []
    private(set) var actionOptions: [ResearchActionID] = []
    private(set) var participantOptions: [ResearchRecordParticipantOption] = []
    private(set) var rebuildingGeneration = 0
    private(set) var pinningRecordIDs: Set<UUID> = []
    var selectedRecordID: UUID? {
        didSet { selectedRecord = selectedRecordID.flatMap(index.record(id:)) }
    }
    var searchText = "" { didSet { refilter() } }
    var noteFilterID: UUID? { didSet { refilter() } }
    var dateFilter: ResearchRecordDateFilter = .any { didSet { refilter() } }
    var skillFilterID: String? { didSet { refilter() } }
    var actionFilterID: ResearchActionID? { didSet { refilter() } }
    var participantFilter: ResearchRecordParticipantFilter? {
        didSet { refilter() }
    }
    private(set) var errorMessage = ""
    var isShowingError = false

    private var index = ResearchRecordDerivedIndex(records: [])
    private var triptychID: UUID?
    private var now: Date
    private var calendar: Calendar
    private let refreshesClockOnOpen: Bool

    init(
        now: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.now = now ?? Date()
        self.calendar = calendar
        refreshesClockOnOpen = now == nil
    }

    func prepareForOpen(
        triptychID: UUID,
        records: [PortableResearchRecord],
        initialNoteID: UUID?
    ) {
        if refreshesClockOnOpen { now = Date() }
        self.triptychID = triptychID
        searchText = ""
        noteFilterID = initialNoteID
        dateFilter = .any
        skillFilterID = nil
        actionFilterID = nil
        participantFilter = nil
        rebuild(records: records)
    }

    func receive(
        triptychID: UUID,
        records: [PortableResearchRecord],
        currentNoteID: UUID?
    ) {
        if self.triptychID != triptychID {
            prepareForOpen(
                triptychID: triptychID,
                records: records,
                initialNoteID: currentNoteID
            )
        } else {
            rebuild(records: records)
        }
    }

    func select(_ id: UUID?) {
        selectedRecordID = id
    }

    func clearAllFilters() {
        searchText = ""
        noteFilterID = nil
        dateFilter = .any
        skillFilterID = nil
        actionFilterID = nil
        participantFilter = nil
    }

    func dismissError() {
        isShowingError = false
        errorMessage = ""
    }

    func refreshClock(_ now: Date, calendar: Calendar? = nil) {
        self.now = now
        if let calendar { self.calendar = calendar }
        refilter()
    }

    func setPinned(
        recordID: UUID,
        update: @MainActor (UUID, Bool) async throws -> PortableResearchRecord
    ) async {
        guard !pinningRecordIDs.contains(recordID),
              let current = index.record(id: recordID) else { return }
        pinningRecordIDs.insert(recordID)
        dismissError()
        defer { pinningRecordIDs.remove(recordID) }
        do {
            let updated = try await update(recordID, !current.isPinned)
            index = index.replacing(updated)
            rebuildOptions()
            refilter()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func rebuild(records: [PortableResearchRecord]) {
        index = ResearchRecordDerivedIndex(records: records)
        rebuildingGeneration &+= 1
        rebuildOptions()
        refilter()
    }

    private func rebuildOptions() {
        var notesByID: [UUID: ResearchRecordNoteOption] = [:]
        for entry in index.entries {
            for note in entry.noteParticipants {
                let candidate = ResearchRecordNoteOption(
                    id: note.noteID,
                    title: note.title,
                    role: note.role,
                    isTombstone: note.isTombstone
                )
                guard let current = notesByID[note.noteID] else {
                    notesByID[note.noteID] = candidate
                    continue
                }
                if current.isTombstone && !candidate.isTombstone {
                    notesByID[note.noteID] = candidate
                } else if current.isTombstone == candidate.isTombstone,
                          candidate.title.localizedStandardCompare(current.title)
                            == .orderedAscending {
                    notesByID[note.noteID] = candidate
                }
            }
        }
        noteOptions = notesByID.values.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        skillOptions = Set(index.entries.compactMap(\.skillID)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        actionOptions = Set(index.entries.map(\.actionID)).sorted {
            $0.rawValue < $1.rawValue
        }
        let authorOptions = Set(index.entries.flatMap(\.authorParticipants)).sorted {
            $0.rawValue < $1.rawValue
        }.map {
            ResearchRecordParticipantOption(
                filter: .author($0),
                title: $0.rawValue,
                isTombstone: false
            )
        }
        participantOptions = authorOptions + noteOptions.map {
            ResearchRecordParticipantOption(
                filter: .note($0.id),
                title: $0.title,
                isTombstone: $0.isTombstone
            )
        }
    }

    private func refilter() {
        let selectedID = selectedRecordID
        visibleEntries = index.query(
            text: searchText,
            noteID: noteFilterID,
            dateFilter: dateFilter,
            skillID: skillFilterID,
            actionID: actionFilterID,
            participant: participantFilter,
            now: now,
            calendar: calendar
        )
        if let selectedID,
           visibleEntries.contains(where: { $0.id == selectedID }) {
            selectedRecordID = selectedID
        } else {
            selectedRecordID = visibleEntries.first?.id
        }
    }
}
