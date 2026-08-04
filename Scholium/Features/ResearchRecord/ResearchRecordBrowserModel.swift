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

enum ResearchLiteratureRecommendationFilter: String, CaseIterable, Hashable, Sendable {
    case unprocessed
    case handled
    case all
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

struct ResearchLiteratureRecommendationOccurrenceID: Hashable, Sendable {
    let recordID: UUID
    let recommendationID: UUID
}

struct ResearchLiteratureRecommendationOccurrence: Identifiable, Equatable, Sendable {
    let parentRecord: PortableResearchRecord
    let recommendation: ResearchLiteratureRecommendation
    let contextTitle: String
    fileprivate let normalizedDOI: String?
    fileprivate let normalizedZoteroItemKey: String?
    fileprivate let normalizedSearchCorpus: String

    var id: ResearchLiteratureRecommendationOccurrenceID {
        ResearchLiteratureRecommendationOccurrenceID(
            recordID: parentRecord.id,
            recommendationID: recommendation.id
        )
    }

    var displayTitle: String {
        recommendation.title ?? recommendation.rawCitation
    }
}

struct ResearchLiteratureRecommendationGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let occurrences: [ResearchLiteratureRecommendationOccurrence]

    var displaysSharedIdentityHeader: Bool { occurrences.count > 1 }
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
        let terms = Self.normalizedTerms(text)
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

    fileprivate static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    fileprivate static func normalizedTerms(_ value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}

/// A reconstructable occurrence index over the recommendation arrays owned by
/// Analyze Research Records. Grouping is deliberately conservative: only an
/// exact normalized DOI or Zotero item key can join occurrences, and an
/// ambiguous bridge never combines conflicting identifiers.
struct ResearchLiteratureRecommendationDerivedIndex: Equatable, Sendable {
    private let occurrences: [ResearchLiteratureRecommendationOccurrence]
    private let occurrencesByID: [
        ResearchLiteratureRecommendationOccurrenceID:
            ResearchLiteratureRecommendationOccurrence
    ]

    init(records: [PortableResearchRecord]) {
        let occurrences = records.flatMap { record in
            record.literatureRecommendations.map { recommendation in
                Self.makeOccurrence(record: record, recommendation: recommendation)
            }
        }.sorted(by: Self.ordersOccurrences)
        self.occurrences = occurrences
        occurrencesByID = Dictionary(
            occurrences.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func occurrence(
        id: ResearchLiteratureRecommendationOccurrenceID
    ) -> ResearchLiteratureRecommendationOccurrence? {
        occurrencesByID[id]
    }

    func unprocessedCount(noteID: UUID?) -> Int {
        scopedOccurrences(noteID: noteID).count {
            $0.recommendation.disposition.status == .unprocessed
        }
    }

    func query(
        text: String,
        noteID: UUID?,
        status: ResearchLiteratureRecommendationFilter
    ) -> [ResearchLiteratureRecommendationGroup] {
        let scoped = scopedOccurrences(noteID: noteID)
        var compatibilityCheckCount = 0
        let grouped = Self.group(
            scoped,
            compatibilityCheckCount: &compatibilityCheckCount
        )
        let terms = ResearchRecordDerivedIndex.normalizedTerms(text)
        return grouped.compactMap { group in
            let visibleOccurrences = group.occurrences.filter { occurrence in
                let hasStatus = switch status {
                case .unprocessed:
                    occurrence.recommendation.disposition.status == .unprocessed
                case .handled:
                    occurrence.recommendation.disposition.status == .handled
                case .all:
                    true
                }
                return hasStatus
                    && terms.allSatisfy(occurrence.normalizedSearchCorpus.contains)
            }
            guard !visibleOccurrences.isEmpty else { return nil }
            return ResearchLiteratureRecommendationGroup(
                id: group.id,
                title: group.title,
                occurrences: visibleOccurrences
            )
        }
    }

    func groupingCompatibilityCheckCount(noteID: UUID?) -> Int {
        var count = 0
        _ = Self.group(
            scopedOccurrences(noteID: noteID),
            compatibilityCheckCount: &count
        )
        return count
    }

    private func scopedOccurrences(
        noteID: UUID?
    ) -> [ResearchLiteratureRecommendationOccurrence] {
        guard let noteID else { return occurrences }
        return occurrences.filter { occurrence in
            occurrence.parentRecord.participatingNotes.contains {
                $0.noteID == noteID
            }
        }
    }

    private static func makeOccurrence(
        record: PortableResearchRecord,
        recommendation: ResearchLiteratureRecommendation
    ) -> ResearchLiteratureRecommendationOccurrence {
        let doi = normalizedDOI(recommendation.doi)
        let zoteroItemKey = normalizedZoteroItemKey(recommendation.zoteroItemKey)
        let searchable = [
            recommendation.rawCitation,
            recommendation.title,
            recommendation.authors.joined(separator: " "),
            recommendation.year.map(String.init),
            recommendation.doi,
            recommendation.zoteroItemKey,
            recommendation.sourceLocators.joined(separator: " "),
            recommendation.reason,
            recommendation.uncertainty,
            recommendation.disposition.researcherNote,
            record.researchRecordContextTitle,
            record.sourceReference?.displayName,
            record.method?.packageID,
            record.method?.version,
        ].compactMap { $0 }.joined(separator: "\n")
        return ResearchLiteratureRecommendationOccurrence(
            parentRecord: record,
            recommendation: recommendation,
            contextTitle: record.researchRecordContextTitle ?? "Analyze",
            normalizedDOI: doi,
            normalizedZoteroItemKey: zoteroItemKey,
            normalizedSearchCorpus: ResearchRecordDerivedIndex.normalized(searchable)
        )
    }

    private struct RecommendationIdentitySignature {
        let doi: String?
        let zoteroItemKey: String?
        let title: String?
        let authors: [String]?
        let year: Int?

        init(_ occurrence: ResearchLiteratureRecommendationOccurrence) {
            doi = occurrence.normalizedDOI
            zoteroItemKey = occurrence.normalizedZoteroItemKey
            title = normalizedOptional(occurrence.recommendation.title)
            authors = normalizedAuthors(occurrence.recommendation.authors)
            year = occurrence.recommendation.year
        }

        private init(
            doi: String?,
            zoteroItemKey: String?,
            title: String?,
            authors: [String]?,
            year: Int?
        ) {
            self.doi = doi
            self.zoteroItemKey = zoteroItemKey
            self.title = title
            self.authors = authors
            self.year = year
        }

        func merging(_ other: Self) -> Self? {
            guard valuesDoNotConflict(doi, other.doi),
                  valuesDoNotConflict(zoteroItemKey, other.zoteroItemKey),
                  valuesDoNotConflict(title, other.title),
                  valuesDoNotConflict(authors, other.authors),
                  valuesDoNotConflict(year, other.year) else {
                return nil
            }
            return Self(
                doi: doi ?? other.doi,
                zoteroItemKey: zoteroItemKey ?? other.zoteroItemKey,
                title: title ?? other.title,
                authors: authors ?? other.authors,
                year: year ?? other.year
            )
        }
    }

    private struct RecommendationCluster {
        var occurrences: [ResearchLiteratureRecommendationOccurrence]
        var signature: RecommendationIdentitySignature
    }

    private static func group(
        _ occurrences: [ResearchLiteratureRecommendationOccurrence],
        compatibilityCheckCount: inout Int
    ) -> [ResearchLiteratureRecommendationGroup] {
        var clusters: [Int: RecommendationCluster] = [:]
        var doiOwners: [String: Set<Int>] = [:]
        var zoteroOwners: [String: Set<Int>] = [:]
        var nextClusterID = 0

        func register(_ cluster: RecommendationCluster, id: Int) {
            if let doi = cluster.signature.doi {
                doiOwners[doi, default: []].insert(id)
            }
            if let key = cluster.signature.zoteroItemKey {
                zoteroOwners[key, default: []].insert(id)
            }
        }

        func unregister(_ cluster: RecommendationCluster, id: Int) {
            if let doi = cluster.signature.doi {
                doiOwners[doi]?.remove(id)
                if doiOwners[doi]?.isEmpty == true { doiOwners.removeValue(forKey: doi) }
            }
            if let key = cluster.signature.zoteroItemKey {
                zoteroOwners[key]?.remove(id)
                if zoteroOwners[key]?.isEmpty == true {
                    zoteroOwners.removeValue(forKey: key)
                }
            }
        }

        for occurrence in occurrences {
            let occurrenceSignature = RecommendationIdentitySignature(occurrence)
            var candidateIDs: Set<Int> = []
            if let doi = occurrenceSignature.doi {
                candidateIDs.formUnion(doiOwners[doi] ?? [])
            }
            if let key = occurrenceSignature.zoteroItemKey {
                candidateIDs.formUnion(zoteroOwners[key] ?? [])
            }
            let compatibleIDs = candidateIDs.sorted().filter { id in
                guard let cluster = clusters[id] else { return false }
                compatibilityCheckCount += 1
                return occurrenceSignature.merging(cluster.signature) != nil
            }
            guard !compatibleIDs.isEmpty else {
                let id = nextClusterID
                nextClusterID += 1
                let cluster = RecommendationCluster(
                    occurrences: [occurrence],
                    signature: occurrenceSignature
                )
                clusters[id] = cluster
                register(cluster, id: id)
                continue
            }

            var combinedSignature: RecommendationIdentitySignature? = occurrenceSignature
            for id in compatibleIDs {
                guard let current = combinedSignature,
                      let signature = clusters[id]?.signature else {
                    combinedSignature = nil
                    break
                }
                combinedSignature = current.merging(signature)
            }
            guard let mergedSignature = combinedSignature else {
                let id = nextClusterID
                nextClusterID += 1
                let cluster = RecommendationCluster(
                    occurrences: [occurrence],
                    signature: occurrenceSignature
                )
                clusters[id] = cluster
                register(cluster, id: id)
                continue
            }

            var mergedOccurrences = [occurrence]
            for id in compatibleIDs {
                guard let cluster = clusters.removeValue(forKey: id) else { continue }
                unregister(cluster, id: id)
                mergedOccurrences.append(contentsOf: cluster.occurrences)
            }
            let id = compatibleIDs[0]
            let cluster = RecommendationCluster(
                occurrences: mergedOccurrences,
                signature: mergedSignature
            )
            clusters[id] = cluster
            register(cluster, id: id)
        }

        return clusters.values.map { cluster in
            let occurrences = cluster.occurrences.sorted(by: ordersOccurrences)
            let title = occurrences.lazy.compactMap(\.recommendation.title).first
                ?? occurrences[0].recommendation.rawCitation
            return ResearchLiteratureRecommendationGroup(
                id: clusterID(occurrences),
                title: title,
                occurrences: occurrences
            )
        }.sorted { lhs, rhs in
            let leftDate = lhs.occurrences.first?.parentRecord.finishedAt ?? .distantPast
            let rightDate = rhs.occurrences.first?.parentRecord.finishedAt ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private static func valuesDoNotConflict<Value: Equatable>(
        _ lhs: Value?,
        _ rhs: Value?
    ) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return ResearchRecordDerivedIndex.normalized(value)
    }

    private static func normalizedAuthors(_ values: [String]) -> [String]? {
        guard !values.isEmpty else { return nil }
        return values.map {
            ResearchRecordDerivedIndex.normalized(
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func clusterID(
        _ occurrences: [ResearchLiteratureRecommendationOccurrence]
    ) -> String {
        occurrences.map {
            "\($0.parentRecord.id.uuidString.lowercased()):\($0.recommendation.id.uuidString.lowercased())"
        }.joined(separator: "|")
    }

    private static func normalizedDOI(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !value.isEmpty else { return nil }
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"]
            where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedZoteroItemKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value.uppercased()
    }

    private static func ordersOccurrences(
        _ lhs: ResearchLiteratureRecommendationOccurrence,
        _ rhs: ResearchLiteratureRecommendationOccurrence
    ) -> Bool {
        if lhs.parentRecord.finishedAt != rhs.parentRecord.finishedAt {
            return lhs.parentRecord.finishedAt > rhs.parentRecord.finishedAt
        }
        if lhs.parentRecord.id != rhs.parentRecord.id {
            return lhs.parentRecord.id.uuidString < rhs.parentRecord.id.uuidString
        }
        return lhs.recommendation.id.uuidString < rhs.recommendation.id.uuidString
    }
}

@MainActor
@Observable
final class ResearchRecordBrowserModel {
    private(set) var visibleEntries: [ResearchRecordIndexEntry] = []
    private(set) var visibleRecommendationGroups: [
        ResearchLiteratureRecommendationGroup
    ] = []
    private(set) var selectedRecord: PortableResearchRecord?
    private(set) var selectedRecommendationOccurrence:
        ResearchLiteratureRecommendationOccurrence?
    private(set) var noteOptions: [ResearchRecordNoteOption] = []
    private(set) var skillOptions: [String] = []
    private(set) var actionOptions: [ResearchActionID] = []
    private(set) var participantOptions: [ResearchRecordParticipantOption] = []
    private(set) var rebuildingGeneration = 0
    private(set) var pinningRecordIDs: Set<UUID> = []
    private(set) var mutatingRecordIDs: Set<UUID> = []
    private(set) var mutatingRecommendationIDs: Set<
        ResearchLiteratureRecommendationOccurrenceID
    > = []
    private(set) var comparingNoteID: UUID?
    private(set) var comparison: ResearchRecordComparison?
    private(set) var contextNoteID: UUID?
    private(set) var unprocessedRecommendationCount = 0

    var selectedRecordID: UUID? {
        didSet {
            if oldValue != selectedRecordID { cancelComparison() }
            selectedRecord = selectedRecordID.flatMap(index.record(id:))
        }
    }
    var selectedRecommendationID: ResearchLiteratureRecommendationOccurrenceID? {
        didSet {
            selectedRecommendationOccurrence = selectedRecommendationID.flatMap(
                recommendationIndex.occurrence(id:)
            )
        }
    }
    var scope: ResearchRecordsScope = .triptych { didSet { refilter() } }
    var viewKind: ResearchRecordsViewKind = .records
    var searchText = "" { didSet { refilterRecords() } }
    var recommendationSearchText = "" { didSet { refilterRecommendations() } }
    var recommendationFilter: ResearchLiteratureRecommendationFilter = .unprocessed {
        didSet { refilterRecommendations() }
    }
    var dateFilter: ResearchRecordDateFilter = .any { didSet { refilterRecords() } }
    var skillFilterID: String? { didSet { refilterRecords() } }
    var actionFilterID: ResearchActionID? { didSet { refilterRecords() } }
    var participantFilter: ResearchRecordParticipantFilter? {
        didSet { refilterRecords() }
    }
    private(set) var errorMessage = ""
    private(set) var isComparisonError = false
    var isShowingError = false

    var canScopeToNote: Bool { contextNoteID != nil }

    private var index = ResearchRecordDerivedIndex(records: [])
    private var recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(records: [])
    private var currentRecords: [PortableResearchRecord] = []
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonGeneration: UInt64 = 0
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
        request: ResearchRecordsWindowRequest
    ) {
        if refreshesClockOnOpen { now = Date() }
        self.triptychID = triptychID
        searchText = ""
        recommendationSearchText = ""
        recommendationFilter = .unprocessed
        dateFilter = .any
        skillFilterID = nil
        actionFilterID = nil
        participantFilter = nil
        apply(request)
        rebuild(records: records)
    }

    func receive(
        triptychID: UUID,
        records: [PortableResearchRecord]
    ) {
        guard self.triptychID == triptychID else { return }
        rebuild(records: records)
    }

    func apply(_ request: ResearchRecordsWindowRequest) {
        guard triptychID == nil || request.triptychID == triptychID else { return }
        contextNoteID = request.noteID
        scope = request.noteID == nil ? .triptych : .thisNote
        viewKind = request.initialView
        refilter()
    }

    func select(_ id: UUID?) {
        selectedRecordID = id
    }

    func selectRecommendation(_ id: ResearchLiteratureRecommendationOccurrenceID?) {
        selectedRecommendationID = id
    }

    func openParentRecord(_ id: UUID) {
        viewKind = .records
        clearAllFilters()
        selectedRecordID = id
        refilterRecords()
    }

    func openRecommendation(recordID: UUID, recommendationID: UUID) {
        let occurrenceID = ResearchLiteratureRecommendationOccurrenceID(
            recordID: recordID,
            recommendationID: recommendationID
        )
        guard recommendationIndex.occurrence(id: occurrenceID) != nil else { return }
        recommendationSearchText = ""
        recommendationFilter = .all
        viewKind = .recommendations
        selectedRecommendationID = occurrenceID
    }

    func clearAllFilters() {
        searchText = ""
        dateFilter = .any
        skillFilterID = nil
        actionFilterID = nil
        participantFilter = nil
    }

    func clearRecommendationFilters() {
        recommendationSearchText = ""
        recommendationFilter = .unprocessed
    }

    func dismissError() {
        isShowingError = false
        errorMessage = ""
        isComparisonError = false
    }

    func presentError(_ message: String) {
        errorMessage = message
        isComparisonError = false
        isShowingError = true
    }

    func deletePermanently(
        recordID: UUID,
        update: @MainActor (UUID) async throws -> Void
    ) async {
        guard !mutatingRecordIDs.contains(recordID),
              !pinningRecordIDs.contains(recordID) else { return }
        mutatingRecordIDs.insert(recordID)
        dismissError()
        cancelComparison()
        defer { mutatingRecordIDs.remove(recordID) }
        do {
            try await update(recordID)
            rebuild(records: currentRecords.filter { $0.id != recordID })
        } catch {
            present(error)
        }
    }

    func compare(
        recordID: UUID,
        noteID: UUID,
        load: @escaping @MainActor (
            UUID,
            UUID
        ) async throws -> ResearchRecordComparison
    ) {
        cancelComparison()
        dismissError()
        comparingNoteID = noteID
        let generation = comparisonGeneration
        comparisonTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await load(recordID, noteID)
                try Task.checkCancellation()
                guard generation == comparisonGeneration else { return }
                comparison = result
            } catch is CancellationError {
                guard generation == comparisonGeneration else { return }
                comparison = nil
            } catch {
                guard generation == comparisonGeneration else { return }
                comparison = nil
                comparingNoteID = nil
                isComparisonError = true
                presentComparison(error)
            }
        }
    }

    func cancelComparison() {
        comparisonGeneration &+= 1
        comparisonTask?.cancel()
        comparisonTask = nil
        comparingNoteID = nil
        comparison = nil
    }

    func refreshClock(_ now: Date, calendar: Calendar? = nil) {
        self.now = now
        if let calendar { self.calendar = calendar }
        refilterRecords()
    }

    func setPinned(
        recordID: UUID,
        update: @MainActor (UUID, Bool) async throws -> PortableResearchRecord
    ) async {
        guard !pinningRecordIDs.contains(recordID),
              !mutatingRecordIDs.contains(recordID),
              let current = index.record(id: recordID) else { return }
        pinningRecordIDs.insert(recordID)
        dismissError()
        defer { pinningRecordIDs.remove(recordID) }
        do {
            replaceRecord(try await update(recordID, !current.isPinned))
        } catch {
            present(error)
        }
    }

    func setRecommendationDisposition(
        occurrenceID: ResearchLiteratureRecommendationOccurrenceID,
        status: ResearchLiteratureRecommendationDispositionStatus,
        update: @MainActor (
            UUID,
            UUID,
            ResearchLiteratureRecommendationDispositionStatus
        ) async throws -> PortableResearchRecord
    ) async {
        guard mutatingRecommendationIDs.insert(occurrenceID).inserted else { return }
        dismissError()
        defer { mutatingRecommendationIDs.remove(occurrenceID) }
        do {
            replaceRecord(try await update(
                occurrenceID.recordID,
                occurrenceID.recommendationID,
                status
            ))
        } catch {
            present(error)
        }
    }

    func setRecommendationNote(
        occurrenceID: ResearchLiteratureRecommendationOccurrenceID,
        note: String?,
        update: @MainActor (
            UUID,
            UUID,
            String?
        ) async throws -> PortableResearchRecord
    ) async throws {
        guard mutatingRecommendationIDs.insert(occurrenceID).inserted else { return }
        dismissError()
        defer { mutatingRecommendationIDs.remove(occurrenceID) }
        replaceRecord(try await update(
            occurrenceID.recordID,
            occurrenceID.recommendationID,
            note
        ))
    }

    private func replaceRecord(_ updated: PortableResearchRecord) {
        guard let currentIndex = currentRecords.firstIndex(where: {
            $0.id == updated.id
        }) else { return }
        currentRecords[currentIndex] = updated
        rebuild(records: currentRecords)
    }

    private func rebuild(records: [PortableResearchRecord]) {
        currentRecords = records
        index = ResearchRecordDerivedIndex(records: records)
        recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(records: records)
        rebuildingGeneration &+= 1
        rebuildOptions()
        refilter()
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func presentComparison(_ error: Error) {
        guard let comparisonError = error as? ResearchRecordComparisonError else {
            present(error)
            return
        }
        errorMessage = switch comparisonError {
        case .participantNotFound:
            String(
                localized: "This note is not part of the selected Research Record.",
                table: "Localizable",
                bundle: .module
            )
        case .endingRevisionUnavailable:
            String(
                localized: "Comparison is unavailable because the record has no exact ending revision.",
                table: "Localizable",
                bundle: .module
            )
        case .exactRevisionUnavailable(let fingerprint):
            String(
                localized: "Comparison is unavailable because exact revision \(fingerprint.sha256) is not retained.",
                table: "Localizable",
                bundle: .module
            )
        case .nonUTF8Revision(let fingerprint):
            String(
                localized: "Comparison is unavailable because revision \(fingerprint.sha256) is not valid UTF-8 Markdown.",
                table: "Localizable",
                bundle: .module
            )
        case .fingerprintMismatch(let expected, let observed):
            String(
                localized: "Comparison is unavailable because retained bytes \(observed.sha256) do not match recorded revision \(expected.sha256).",
                table: "Localizable",
                bundle: .module
            )
        }
        isShowingError = true
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
        if scope == .thisNote, contextNoteID == nil { scope = .triptych }
        refilterRecords()
        refilterRecommendations()
    }

    private func refilterRecords() {
        let selectedID = selectedRecordID
        visibleEntries = index.query(
            text: searchText,
            noteID: scopedNoteID,
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

    private func refilterRecommendations() {
        let selectedID = selectedRecommendationID
        let noteID = scopedNoteID
        visibleRecommendationGroups = recommendationIndex.query(
            text: recommendationSearchText,
            noteID: noteID,
            status: recommendationFilter
        )
        unprocessedRecommendationCount = recommendationIndex.unprocessedCount(noteID: noteID)
        let visibleIDs = Set(visibleRecommendationGroups.flatMap {
            $0.occurrences.map(\.id)
        })
        if let selectedID, visibleIDs.contains(selectedID) {
            selectedRecommendationID = selectedID
        } else {
            selectedRecommendationID = visibleRecommendationGroups.first?.occurrences.first?.id
        }
    }

    private var scopedNoteID: UUID? {
        scope == .thisNote ? contextNoteID : nil
    }
}
