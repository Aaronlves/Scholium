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

private enum ResearchRecordBrowserSearchError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let reason): reason
        }
    }
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
    let methodName: String?
    let noteParticipants: [PortableResearchNoteRevision]
    let authorParticipants: [PortableResearchStatementAuthor]

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
        let terms = Self.normalizedTerms(text)
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
            record.method?.displayName,
            record.method?.practiceNames.joined(separator: " "),
        ].compactMap { $0 }.joined(separator: "\n")
        return ResearchLiteratureRecommendationOccurrence(
            parentRecord: record,
            recommendation: recommendation,
            contextTitle: record.researchRecordContextTitle ?? "Analyze",
            normalizedDOI: doi,
            normalizedZoteroItemKey: zoteroItemKey,
            normalizedSearchCorpus: normalized(searchable)
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
        return normalized(value)
    }

    private static func normalizedAuthors(_ values: [String]) -> [String]? {
        guard !values.isEmpty else { return nil }
        return values.map {
            normalized(
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

    fileprivate static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func normalizedTerms(_ value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
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
    private(set) var methodOptions: [String] = []
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
    private(set) var focusedStatementID: UUID?
    private(set) var unprocessedRecommendationCount = 0

    var selectedRecordID: UUID? {
        didSet {
            if oldValue != selectedRecordID { cancelComparison() }
            selectedRecord = selectedRecordID.flatMap { recordsByID[$0] }
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
    var methodFilterName: String? { didSet { refilterRecords() } }
    var actionFilterID: ResearchActionID? { didSet { refilterRecords() } }
    var participantFilter: ResearchRecordParticipantFilter? {
        didSet { refilterRecords() }
    }
    private(set) var errorMessage = ""
    private(set) var isComparisonError = false
    private var isRecordSearchError = false
    var isShowingError = false

    var canScopeToNote: Bool { contextNoteID != nil }

    private var allEntries: [ResearchRecordIndexEntry] = []
    private var recordsByID: [UUID: PortableResearchRecord] = [:]
    private var recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(records: [])
    private var currentRecords: [PortableResearchRecord] = []
    private var currentFingerprints: [UUID: DocumentFingerprint] = [:]
    private var activeRecordLocator: ResearchRecordsWindowRequest?
    @ObservationIgnored private var recordSearch: (@MainActor @Sendable (
        SearchRequest
    ) async throws -> SearchResponse)?
    @ObservationIgnored private var recordSearchTask: Task<Void, Never>?
    @ObservationIgnored private var recordSearchGeneration: UInt64 = 0
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonGeneration: UInt64 = 0
    private var triptychID: UUID?

    init() {}

    func bindRecordSearch(
        _ search: @escaping @MainActor @Sendable (
            SearchRequest
        ) async throws -> SearchResponse
    ) {
        recordSearch = search
        refilterRecords()
    }

    #if DEBUG
    func waitForRecordSearchForTesting() async {
        await recordSearchTask?.value
    }
    #endif

    func prepareForOpen(
        triptychID: UUID,
        records: [PortableResearchRecord],
        fingerprints: [UUID: DocumentFingerprint] = [:],
        request: ResearchRecordsWindowRequest
    ) {
        self.triptychID = triptychID
        searchText = ""
        recommendationSearchText = ""
        recommendationFilter = .unprocessed
        dateFilter = .any
        methodFilterName = nil
        actionFilterID = nil
        participantFilter = nil
        currentFingerprints = fingerprints
        rebuild(records: records)
        apply(request)
    }

    func receive(
        triptychID: UUID,
        records: [PortableResearchRecord],
        fingerprints: [UUID: DocumentFingerprint] = [:]
    ) {
        guard self.triptychID == triptychID else { return }
        currentFingerprints = fingerprints
        rebuild(records: records)
        if let activeRecordLocator {
            applyRecordLocator(activeRecordLocator)
        }
    }

    func apply(_ request: ResearchRecordsWindowRequest) {
        guard triptychID == nil || request.triptychID == triptychID else { return }
        activeRecordLocator = request.recordID == nil ? nil : request
        if request.recordID == nil { focusedStatementID = nil }
        contextNoteID = request.noteID
        scope = request.noteID == nil ? .triptych : .thisNote
        viewKind = request.initialView
        refilter()
        applyRecordLocator(request)
    }

    func select(_ id: UUID?) {
        activeRecordLocator = nil
        focusedStatementID = nil
        selectedRecordID = id
    }

    func selectRecommendation(_ id: ResearchLiteratureRecommendationOccurrenceID?) {
        selectedRecommendationID = id
    }

    func openParentRecord(_ id: UUID) {
        activeRecordLocator = nil
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
        methodFilterName = nil
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
        isRecordSearchError = false
    }

    func presentError(_ message: String) {
        errorMessage = message
        isComparisonError = false
        isRecordSearchError = false
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
        } catch ScholiumApplicationError.operationCommittedButRefreshFailed {
            currentFingerprints[recordID] = nil
            rebuild(records: currentRecords.filter { $0.id != recordID })
            presentError(
                "The Research Record was deleted, but the workspace refresh failed. Scholium removed the committed Record from this window."
            )
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

    func setPinned(
        recordID: UUID,
        update: @MainActor (UUID, Bool) async throws -> PortableResearchRecord
    ) async {
        guard !pinningRecordIDs.contains(recordID),
              !mutatingRecordIDs.contains(recordID),
              let current = recordsByID[recordID] else { return }
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

    func acceptUpdatedRecord(_ record: PortableResearchRecord) {
        replaceRecord(record)
    }

    private func replaceRecord(_ updated: PortableResearchRecord) {
        guard let currentIndex = currentRecords.firstIndex(where: {
            $0.id == updated.id
        }) else { return }
        currentRecords[currentIndex] = updated
        rebuild(records: currentRecords)
    }

    private func rebuild(records: [PortableResearchRecord]) {
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: {
            first,
            second in
            if first.finishedAt != second.finishedAt {
                return first.finishedAt > second.finishedAt ? first : second
            }
            return first.id.uuidString < second.id.uuidString ? first : second
        })
        recordsByID = unique
        currentRecords = Array(unique.values)
        allEntries = currentRecords.map(Self.makeEntry).sorted(by: Self.ordersEntries)
        recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(
            records: currentRecords
        )
        rebuildingGeneration &+= 1
        rebuildOptions()
        refilter()
    }

    private func applyRecordLocator(_ request: ResearchRecordsWindowRequest) {
        guard let recordID = request.recordID else { return }
        guard let record = currentRecords.first(where: { $0.id == recordID }),
              let expected = request.expectedRecordFingerprint,
              currentFingerprints[recordID] == expected else {
            selectedRecordID = nil
            focusedStatementID = nil
            presentError(
                "The Research Record changed or was deleted. Search results must be refreshed."
            )
            return
        }
        if let statementID = request.statementID,
           !record.statements.contains(where: { $0.id == statementID }) {
            selectedRecordID = nil
            focusedStatementID = nil
            presentError(
                "The matched Research Record statement is no longer available. Search results must be refreshed."
            )
            return
        }
        clearAllFilters()
        viewKind = .records
        selectedRecordID = recordID
        focusedStatementID = request.statementID
        refilterRecords()
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isRecordSearchError = false
        isShowingError = true
    }

    private func presentRecordSearchError(_ message: String) {
        errorMessage = message
        isComparisonError = false
        isRecordSearchError = true
        isShowingError = true
    }

    private func presentComparison(_ error: Error) {
        isRecordSearchError = false
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
        for entry in allEntries {
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
        methodOptions = Set(allEntries.compactMap(\.methodName)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        actionOptions = Set(allEntries.map(\.actionID)).sorted {
            $0.rawValue < $1.rawValue
        }
        let authorOptions = Set(allEntries.flatMap(\.authorParticipants)).sorted {
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
        recordSearchGeneration &+= 1
        let generation = recordSearchGeneration
        recordSearchTask?.cancel()
        guard let recordSearch, triptychID != nil else {
            visibleEntries = []
            selectedRecordID = nil
            return
        }
        let request = SearchRequest(
            query: recordSearchQuery,
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: SearchContract.maximumInterfaceResults
        )
        recordSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await recordSearch(request)
                try Task.checkCancellation()
                guard generation == recordSearchGeneration else { return }
                try acceptRecordSearchResponse(response)
            } catch is CancellationError {
                return
            } catch {
                guard generation == recordSearchGeneration else { return }
                visibleEntries = []
                selectedRecordID = nil
                presentRecordSearchError(
                    "Research Record Search failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func acceptRecordSearchResponse(_ response: SearchResponse) throws {
        guard response.contractVersion == SearchContract.currentVersion,
              response.provider == .record,
              response.hasConsistentProviderIdentity,
              response.diagnostics.isEmpty,
              case .record(.current) = response.availability else {
            throw ResearchRecordBrowserSearchError.invalidResponse(
                response.diagnostics.first?.message
                    ?? "The Record provider did not return a current result."
            )
        }
        let results = response.results.compactMap { result -> RecordSearchResult? in
            guard case .record(let record) = result else { return nil }
            return record
        }
        guard results.count == response.results.count else {
            throw ResearchRecordBrowserSearchError.invalidResponse(
                "The Record provider returned a Note result."
            )
        }
        var entries: [ResearchRecordIndexEntry] = []
        for result in results {
            guard let entry = allEntries.first(where: { $0.id == result.recordID }),
                  currentFingerprints[result.recordID] == result.fingerprint else {
                throw ResearchRecordBrowserSearchError.invalidResponse(
                    "A Research Record changed while its results were being displayed."
                )
            }
            entries.append(entry)
        }
        if isRecordSearchError { dismissError() }
        let selectedID = selectedRecordID
        visibleEntries = entries
        if let selectedID, entries.contains(where: { $0.id == selectedID }) {
            selectedRecordID = selectedID
        } else {
            selectedRecordID = entries.first?.id
        }
    }

    private var recordSearchQuery: String {
        var clauses = ["kind:record"]
        clauses.append(contentsOf: searchText.split(whereSeparator: \.isWhitespace).map {
            Self.quotedSearchValue(String($0))
        })
        var noteIDs: [UUID] = []
        if let scopedNoteID { noteIDs.append(scopedNoteID) }
        if case .note(let noteID) = participantFilter { noteIDs.append(noteID) }
        for noteID in Set(noteIDs).sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            clauses.append("note:\(Self.quotedSearchValue(noteID.uuidString.lowercased()))")
        }
        if let methodFilterName {
            clauses.append("skill:\(Self.quotedSearchValue(methodFilterName))")
        }
        if let actionFilterID {
            clauses.append("action:\(Self.quotedSearchValue(actionFilterID.rawValue))")
        }
        if case .author(let author) = participantFilter {
            clauses.append("participant:\(author.rawValue)")
        }
        switch dateFilter {
        case .any:
            break
        case .today:
            clauses.append("date:today")
        case .pastSevenDays:
            clauses.append("date:7d")
        case .pastThirtyDays:
            clauses.append("date:30d")
        }
        return clauses.joined(separator: " ")
    }

    private static func quotedSearchValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func makeEntry(
        _ record: PortableResearchRecord
    ) -> ResearchRecordIndexEntry {
        let actionID = record.kind == .discussion
            ? ResearchActionID.discuss
            : record.action?.actionID ?? .discuss
        return ResearchRecordIndexEntry(
            record: record,
            contextTitle: record.researchRecordContextTitle ?? actionID.rawValue,
            actionID: actionID,
            methodName: record.method?.displayName,
            noteParticipants: record.participatingNotes,
            authorParticipants: Set(record.statements.map(\.author)).sorted {
                $0.rawValue < $1.rawValue
            }
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
