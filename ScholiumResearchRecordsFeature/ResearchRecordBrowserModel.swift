import Foundation
import Observation
import ScholiumContracts

package enum ResearchRecordDateFilter: String, CaseIterable, Equatable, Sendable {
    case any
    case today
    case pastSevenDays
    case pastThirtyDays
}

package enum ResearchRecordParticipantFilter: Hashable, Sendable {
    case author(PortableResearchStatementAuthor)
    case note(UUID)
}

package enum ResearchLiteratureRecommendationFilter: String, CaseIterable, Hashable, Sendable {
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

package struct ResearchRecordNoteOption: Identifiable, Equatable, Sendable {
    package let id: UUID
    package let title: String
    package let role: ResearchActionTargetRole
}

package struct ResearchRecordParticipantOption: Identifiable, Equatable, Sendable {
    package let filter: ResearchRecordParticipantFilter
    package let title: String

    package var id: ResearchRecordParticipantFilter { filter }
}

package struct ResearchRecordIndexEntry: Identifiable, Equatable, Sendable {
    package let id: UUID
    package let finishedAt: Date
    package let title: String
    package let noteTitle: String
    package let actionID: ResearchActionID
    package let methodName: String?
    package let sourceName: String?
    package let reliability: ResearchRecordLedgerFieldState
    package let coverage: ResearchRecordLedgerFieldState
    package let noteParticipants: [PortableResearchNoteRevision]
    package let authorParticipants: [PortableResearchStatementAuthor]
    package let resultDisposition: ResearchAgentResultDisposition
    package let statementCount: Int
    package let isTopLevel: Bool

    package init(
        id: UUID,
        finishedAt: Date,
        title: String,
        noteTitle: String,
        actionID: ResearchActionID,
        methodName: String?,
        sourceName: String?,
        reliability: ResearchRecordLedgerFieldState,
        coverage: ResearchRecordLedgerFieldState,
        noteParticipants: [PortableResearchNoteRevision],
        authorParticipants: [PortableResearchStatementAuthor],
        resultDisposition: ResearchAgentResultDisposition,
        statementCount: Int,
        isTopLevel: Bool
    ) {
        self.id = id
        self.finishedAt = finishedAt
        self.title = title
        self.noteTitle = noteTitle
        self.actionID = actionID
        self.methodName = methodName
        self.sourceName = sourceName
        self.reliability = reliability
        self.coverage = coverage
        self.noteParticipants = noteParticipants
        self.authorParticipants = authorParticipants
        self.resultDisposition = resultDisposition
        self.statementCount = statementCount
        self.isTopLevel = isTopLevel
    }

}

package enum ResearchRecordLedgerFieldState: Equatable, Sendable {
    case value(String)
    case notSupplied
    case unavailable
    case notApplicable
}

package struct ResearchLiteratureRecommendationOccurrenceID: Hashable, Sendable {
    package let recordID: UUID
    package let recommendationID: UUID

    package init(recordID: UUID, recommendationID: UUID) {
        self.recordID = recordID
        self.recommendationID = recommendationID
    }
}

package struct ResearchLiteratureRecommendationOccurrence: Identifiable, Equatable, Sendable {
    package let parentRecord: PortableResearchRecord
    package let recommendation: ResearchLiteratureRecommendation
    package let contextTitle: String
    fileprivate let normalizedDOI: String?
    fileprivate let normalizedZoteroItemKey: String?
    fileprivate let normalizedSearchCorpus: String

    package var id: ResearchLiteratureRecommendationOccurrenceID {
        ResearchLiteratureRecommendationOccurrenceID(
            recordID: parentRecord.id,
            recommendationID: recommendation.id
        )
    }

    package var displayTitle: String {
        recommendation.title ?? recommendation.rawCitation
    }
}

package struct ResearchLiteratureRecommendationGroup: Identifiable, Equatable, Sendable {
    package let id: String
    package let title: String
    package let occurrences: [ResearchLiteratureRecommendationOccurrence]

    package var displaysSharedIdentityHeader: Bool { occurrences.count > 1 }
}

extension PortableResearchRecord {
    package var researchRecordContextParticipant: PortableResearchNoteRevision? {
        if let primaryNoteID,
            let primary = participatingNotes.first(where: {
                $0.noteID == primaryNoteID
            })
        {
            return primary
        }
        return participatingNotes.count == 1 ? participatingNotes.first : nil
    }

    package var researchRecordFocalNoteTitle: String? {
        if let primary = researchRecordContextParticipant {
            return primary.title
        }
        let liveTitles =
            participatingNotes
            .map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return liveTitles.isEmpty ? nil : liveTitles.joined(separator: ", ")
    }
}

/// A reconstructable occurrence index over the recommendation arrays owned by
/// Analyze Research Records. Grouping is deliberately conservative: only an
/// exact normalized DOI or Zotero item key can join occurrences, and an
/// ambiguous bridge never combines conflicting identifiers.
package struct ResearchLiteratureRecommendationDerivedIndex: Equatable, Sendable {
    private let occurrences: [ResearchLiteratureRecommendationOccurrence]
    private let occurrencesByID:
        [ResearchLiteratureRecommendationOccurrenceID:
            ResearchLiteratureRecommendationOccurrence]

    package init(records: [PortableResearchRecord]) {
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

    package func occurrence(
        id: ResearchLiteratureRecommendationOccurrenceID
    ) -> ResearchLiteratureRecommendationOccurrence? {
        occurrencesByID[id]
    }

    package func query(
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
                let hasStatus =
                    switch status {
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

    package func groupingCompatibilityCheckCount(noteID: UUID?) -> Int {
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
            recommendation.publication,
            recommendation.doi,
            recommendation.zoteroItemKey,
            recommendation.sourceLocators.joined(separator: " "),
            recommendation.reason,
            recommendation.uncertainty,
            recommendation.disposition.researcherNote,
            record.researchRecordFocalNoteTitle,
            record.sourceReference?.displayName,
            record.method?.displayName,
        ].compactMap { $0 }.joined(separator: "\n")
        return ResearchLiteratureRecommendationOccurrence(
            parentRecord: record,
            recommendation: recommendation,
            contextTitle: record.researchRecordFocalNoteTitle ?? "Analyze",
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
                valuesDoNotConflict(year, other.year)
            else {
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
                    let signature = clusters[id]?.signature
                else {
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
            let title =
                occurrences.lazy.compactMap(\.recommendation.title).first
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
            !value.isEmpty
        else { return nil }
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
        guard
            var value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(), !value.isEmpty
        else { return nil }
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
            !value.isEmpty
        else { return nil }
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
package final class ResearchRecordBrowserModel {
    package private(set) var route: ResearchRecordsRoute = .collection
    package private(set) var visibleEntries: [ResearchRecordIndexEntry] = []
    package private(set) var visibleRecommendationGroups: [ResearchLiteratureRecommendationGroup] =
        []
    package private(set) var visibleRecommendationOccurrences:
        [ResearchLiteratureRecommendationOccurrence] = []
    package private(set) var recordResultCount = 0
    package private(set) var recommendationResultCount = 0
    package private(set) var hasMoreRecords = false
    package private(set) var hasMoreRecommendations = false
    package private(set) var isLoadingRecords = false
    package private(set) var isLoadingMoreRecords = false
    package private(set) var recordLoadMoreErrorMessage: String?
    package private(set) var noteOptions: [ResearchRecordNoteOption] = []
    package private(set) var methodOptions: [String] = []
    package private(set) var actionOptions: [ResearchActionID] = []
    package private(set) var participantOptions: [ResearchRecordParticipantOption] = []
    package private(set) var rebuildingGeneration = 0
    package private(set) var mutatingRecordIDs: Set<UUID> = []
    package private(set) var deletingRecordIDs: Set<UUID> = []
    package private(set) var mutatingRecommendationIDs:
        Set<
            ResearchLiteratureRecommendationOccurrenceID
        > = []
    package private(set) var optimisticRecommendationStatuses:
        [
            ResearchLiteratureRecommendationOccurrenceID:
                ResearchLiteratureRecommendationDispositionStatus
        ] = [:]
    package private(set) var contextNoteID: UUID?
    package private(set) var focusedStatementID: UUID?
    package private(set) var pendingFollowUpRecordID: UUID?
    package private(set) var pendingFollowUpRequestGeneration: UInt64 = 0

    package var selectedRecord: PortableResearchRecord? {
        selectedRecordID.flatMap { recordsByID[$0] }
    }

    package var selectedRecommendationOccurrence: ResearchLiteratureRecommendationOccurrence? {
        selectedRecommendationID.flatMap(recommendationIndex.occurrence(id:))
    }

    package var selectedRecordID: UUID? {
        get { route.recordID }
        set {
            guard let newValue else {
                route = .collection
                return
            }
            route = .record(newValue)
        }
    }

    package var selectedRecommendationID: ResearchLiteratureRecommendationOccurrenceID? {
        get { route.recommendationID }
        set {
            guard let newValue else {
                route = .collection
                return
            }
            route = .recommendation(newValue)
        }
    }

    package var scope: ResearchRecordsScope = .triptych { didSet { refilter() } }
    package var viewKind: ResearchRecordsViewKind = .records
    package var recordSort: RecordSearchSortOrder = .finishedAtDescending {
        didSet { refilterRecords() }
    }
    package var searchText = "" { didSet { refilterRecords() } }
    package var recommendationSearchText = "" { didSet { refilterRecommendations() } }
    package var recommendationFilter: ResearchLiteratureRecommendationFilter = .unprocessed {
        didSet { refilterRecommendations() }
    }
    package var dateFilter: ResearchRecordDateFilter = .any { didSet { refilterRecords() } }
    package var methodFilterName: String? { didSet { refilterRecords() } }
    package var actionFilterID: ResearchActionID? { didSet { refilterRecords() } }
    package var participantFilter: ResearchRecordParticipantFilter? {
        didSet { refilterRecords() }
    }
    package private(set) var errorMessage = ""
    private var isRecordSearchError = false
    package var isShowingError = false

    package var canScopeToNote: Bool { contextNoteID != nil }
    package var totalRecordCount: Int { collectionEntries.count }

    private var allEntries: [ResearchRecordIndexEntry] = []
    private var recordsByID: [UUID: PortableResearchRecord] = [:]
    private var recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(records: [])
    private var filteredRecommendationOccurrences:
        [ResearchLiteratureRecommendationOccurrence] = []
    private var currentRecords: [PortableResearchRecord] = []
    private var currentFingerprints: [UUID: DocumentFingerprint] = [:]
    private var activeRecordLocator: ResearchRecordsWindowRequest?
    private var directUndoResultFingerprints: [UUID: DocumentFingerprint] = [:]
    @ObservationIgnored private var recordSearch:
        (
            @MainActor @Sendable (
                SearchRequest
            ) async throws -> SearchResponse
        )?
    @ObservationIgnored private var recordSearchTask: Task<Void, Never>?
    @ObservationIgnored private var recordSearchGeneration: UInt64 = 0
    @ObservationIgnored private var recommendationMutationTasks:
        [ResearchLiteratureRecommendationOccurrenceID: Task<Void, Never>] = [:]
    private var triptychID: UUID?

    package init() {}

    package func bindRecordSearch(
        _ search:
            @escaping @MainActor @Sendable (
                SearchRequest
            ) async throws -> SearchResponse
    ) {
        recordSearch = search
        refilterRecords()
    }

    #if DEBUG
        package func waitForRecordSearchForTesting() async {
            await recordSearchTask?.value
        }

        package func waitForRecommendationMutationForTesting(
            _ occurrenceID: ResearchLiteratureRecommendationOccurrenceID
        ) async {
            await recommendationMutationTasks[occurrenceID]?.value
        }
    #endif

    package func loadMoreRecordsIfNeeded(currentID: UUID) {
        guard currentID == visibleEntries.last?.id,
              hasMoreRecords,
              !isLoadingMoreRecords
        else { return }
        requestRecordPage(offset: visibleEntries.count, appending: true)
    }

    package func retryLoadingMoreRecords() {
        guard hasMoreRecords, !isLoadingMoreRecords else { return }
        requestRecordPage(offset: visibleEntries.count, appending: true)
    }

    package func loadMoreRecommendationsIfNeeded(
        currentID: ResearchLiteratureRecommendationOccurrenceID
    ) {
        guard currentID == visibleRecommendationOccurrences.last?.id,
              hasMoreRecommendations
        else { return }
        let upperBound = min(
            visibleRecommendationOccurrences.count + SearchContract.recordCollectionPageSize,
            filteredRecommendationOccurrences.count
        )
        visibleRecommendationOccurrences = Array(
            filteredRecommendationOccurrences.prefix(upperBound)
        )
        hasMoreRecommendations = upperBound < recommendationResultCount
    }

    package func prepareForOpen(
        triptychID: UUID,
        records: [PortableResearchRecord],
        fingerprints: [UUID: DocumentFingerprint] = [:],
        request: ResearchRecordsWindowRequest
    ) {
        self.triptychID = triptychID
        route = request.recordID.map(ResearchRecordsRoute.record) ?? .collection
        searchText = ""
        recommendationSearchText = ""
        recommendationFilter = .unprocessed
        recordSort = .finishedAtDescending
        dateFilter = .any
        methodFilterName = nil
        actionFilterID = nil
        participantFilter = nil
        currentFingerprints = fingerprints
        rebuild(records: records)
        apply(request)
    }

    package func receive(
        triptychID: UUID,
        records: [PortableResearchRecord],
        fingerprints: [UUID: DocumentFingerprint] = [:]
    ) {
        guard self.triptychID == triptychID else { return }
        currentFingerprints = fingerprints
        rebuild(records: records)
        if let activeRecordLocator {
            applyRecordLocator(activeRecordLocator, presentsFollowUp: false)
        }
    }

    package func apply(_ request: ResearchRecordsWindowRequest) {
        guard triptychID == nil || request.triptychID == triptychID else { return }
        activeRecordLocator = request.recordID == nil ? nil : request
        if request.recordID == nil {
            focusedStatementID = nil
            route = .collection
        }
        contextNoteID = request.noteID
        scope = request.noteID == nil ? .triptych : .thisNote
        viewKind = request.initialView
        refilter()
        applyRecordLocator(request, presentsFollowUp: true)
    }

    package func select(_ id: UUID?) {
        activeRecordLocator = nil
        focusedStatementID = nil
        pendingFollowUpRecordID = nil
        selectedRecordID = id
        if id == nil { refilterRecords() }
    }

    package func consumeFollowUpRequest(recordID: UUID) -> Bool {
        guard pendingFollowUpRecordID == recordID else { return false }
        pendingFollowUpRecordID = nil
        return true
    }

    package func selectRecommendation(_ id: ResearchLiteratureRecommendationOccurrenceID?) {
        selectedRecommendationID = id
    }

    package func backToCollection() {
        activeRecordLocator = nil
        focusedStatementID = nil
        route = .collection
        refilterRecords()
    }

    package func openParentRecord(_ id: UUID) {
        activeRecordLocator = nil
        viewKind = .records
        clearAllFilters()
        selectedRecordID = id
        refilterRecords()
    }

    package func openRecord(id: UUID, statementID: UUID? = nil) {
        guard recordsByID[id] != nil else { return }
        activeRecordLocator = nil
        viewKind = .records
        focusedStatementID = statementID
        route = .record(id)
    }

    package func openRecommendation(recordID: UUID, recommendationID: UUID) {
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

    package func clearAllFilters() {
        searchText = ""
        dateFilter = .any
        methodFilterName = nil
        actionFilterID = nil
        participantFilter = nil
    }

    package func clearRecommendationFilters() {
        recommendationSearchText = ""
        recommendationFilter = .unprocessed
    }

    package func dismissError() {
        isShowingError = false
        errorMessage = ""
        isRecordSearchError = false
    }

    package func presentError(_ message: String) {
        errorMessage = message
        isRecordSearchError = false
        isShowingError = true
    }

    package func deletePermanently(
        recordID: UUID,
        update: @MainActor (UUID) async throws -> Void
    ) async {
        guard !mutatingRecordIDs.contains(recordID),
            let current = recordsByID[recordID]
        else { return }
        let priorFingerprint = currentFingerprints[recordID]
        let wasVisible = visibleEntries.contains { $0.id == recordID }
        mutatingRecordIDs.insert(recordID)
        deletingRecordIDs.insert(recordID)
        dismissError()
        removeRecordProjection(recordID)
        defer {
            deletingRecordIDs.remove(recordID)
            mutatingRecordIDs.remove(recordID)
        }
        do {
            try await update(recordID)
        } catch ScholiumApplicationError.operationCommittedButRefreshFailed {
            presentError(
                "The Research Record was deleted, but the workspace refresh failed. Scholium removed the committed Record from this window."
            )
        } catch {
            deletingRecordIDs.remove(recordID)
            restoreRecordProjection(
                current,
                fingerprint: priorFingerprint,
                wasVisible: wasVisible
            )
            present(error)
        }
    }

    package func recommendationDispositionStatus(
        for occurrenceID: ResearchLiteratureRecommendationOccurrenceID
    ) -> ResearchLiteratureRecommendationDispositionStatus {
        optimisticRecommendationStatuses[occurrenceID]
            ?? recommendationIndex.occurrence(id: occurrenceID)?
                .recommendation.disposition.status
            ?? .unprocessed
    }

    package func setRecommendationDisposition(
        occurrenceID: ResearchLiteratureRecommendationOccurrenceID,
        status: ResearchLiteratureRecommendationDispositionStatus,
        update:
            @escaping @MainActor (
                UUID,
                UUID,
                ResearchLiteratureRecommendationDispositionStatus
            ) async throws -> PortableResearchRecord
    ) {
        guard recommendationIndex.occurrence(id: occurrenceID) != nil,
              recommendationDispositionStatus(for: occurrenceID) != status,
              mutatingRecommendationIDs.insert(occurrenceID).inserted
        else { return }
        dismissError()
        optimisticRecommendationStatuses[occurrenceID] = status
        recommendationMutationTasks[occurrenceID] = Task { @MainActor in
            await commitRecommendationDisposition(
                occurrenceID: occurrenceID,
                status: status,
                update: update
            )
        }
    }

    private func commitRecommendationDisposition(
        occurrenceID: ResearchLiteratureRecommendationOccurrenceID,
        status: ResearchLiteratureRecommendationDispositionStatus,
        update:
            @MainActor (
                UUID,
                UUID,
                ResearchLiteratureRecommendationDispositionStatus
            ) async throws -> PortableResearchRecord
    ) async {
        defer {
            recommendationMutationTasks[occurrenceID] = nil
            optimisticRecommendationStatuses[occurrenceID] = nil
            mutatingRecommendationIDs.remove(occurrenceID)
        }
        do {
            replaceRecord(
                try await update(
                    occurrenceID.recordID,
                    occurrenceID.recommendationID,
                    status
                ))
        } catch {
            present(error)
        }
    }

    package func setRecommendationNote(
        occurrenceID: ResearchLiteratureRecommendationOccurrenceID,
        note: String?,
        update:
            @MainActor (
                UUID,
                UUID,
                String?
            ) async throws -> PortableResearchRecord
    ) async throws {
        guard mutatingRecommendationIDs.insert(occurrenceID).inserted else { return }
        dismissError()
        defer { mutatingRecommendationIDs.remove(occurrenceID) }
        replaceRecord(
            try await update(
                occurrenceID.recordID,
                occurrenceID.recommendationID,
                note
            ))
    }

    package func acceptUpdatedRecord(_ record: PortableResearchRecord) {
        replaceRecord(record)
    }

    package func record(id: UUID) -> PortableResearchRecord? {
        recordsByID[id]
    }

    /// Direct undo is a transient presentation grant owned by this window
    /// model. It survives navigation and researcher-owned Record mutations,
    /// but not a changed finalized result or the window's destruction.
    package func hasDirectUndoEligibility(
        for record: PortableResearchRecord
    ) -> Bool {
        guard let directUndoResultFingerprint = directUndoResultFingerprints[record.id],
              (try? record.finalizedResultFingerprint())
                == directUndoResultFingerprint else {
            return false
        }
        return true
    }

    package func continuationParent(
        for record: PortableResearchRecord
    ) -> PortableResearchRecord? {
        guard let kind = record.continuationLineage?.kind,
            kind == .continueResearch || kind == .followUp,
            let parentID = record.continuationLineage?.parentRunID
        else {
            return nil
        }
        return recordsByID[parentID]
    }

    package func continuationChildren(
        for recordID: UUID
    ) -> [PortableResearchRecord] {
        currentRecords.filter {
            guard let lineage = $0.continuationLineage else { return false }
            return (lineage.kind == .continueResearch || lineage.kind == .followUp)
                && lineage.parentRunID == recordID
        }.sorted {
            if $0.finishedAt != $1.finishedAt { return $0.finishedAt < $1.finishedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func replaceRecord(_ updated: PortableResearchRecord) {
        guard
            let currentIndex = currentRecords.firstIndex(where: {
                $0.id == updated.id
            })
        else { return }
        currentRecords[currentIndex] = updated
        rebuild(records: currentRecords)
    }

    private func removeRecordProjection(_ recordID: UUID) {
        let wasVisible = visibleEntries.contains { $0.id == recordID }
        currentRecords.removeAll { $0.id == recordID }
        recordsByID[recordID] = nil
        currentFingerprints[recordID] = nil
        allEntries.removeAll { $0.id == recordID }
        visibleEntries.removeAll { $0.id == recordID }
        if wasVisible { recordResultCount = max(0, recordResultCount - 1) }
        recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(
            records: currentRecords
        )
        reconcileRouteWithCurrentRecords()
        rebuildOptions()
        refilterRecommendations()
        rebuildingGeneration &+= 1
    }

    private func restoreRecordProjection(
        _ record: PortableResearchRecord,
        fingerprint: DocumentFingerprint?,
        wasVisible: Bool
    ) {
        guard recordsByID[record.id] == nil else { return }
        currentRecords.append(record)
        recordsByID[record.id] = record
        if let fingerprint { currentFingerprints[record.id] = fingerprint }
        let entry = Self.makeEntry(record)
        allEntries.append(entry)
        allEntries.sort(by: Self.ordersEntries)
        if wasVisible {
            visibleEntries.append(entry)
            visibleEntries.sort { Self.ordersEntries($0, $1, by: recordSort) }
            recordResultCount += 1
        }
        recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(
            records: currentRecords
        )
        rebuildOptions()
        refilterRecommendations()
        rebuildingGeneration &+= 1
    }

    private func rebuild(records: [PortableResearchRecord]) {
        let projectedRecords = records.filter { !deletingRecordIDs.contains($0.id) }
        let unique = Dictionary(
            projectedRecords.map { ($0.id, $0) },
            uniquingKeysWith: {
                first,
                second in
                if first.finishedAt != second.finishedAt {
                    return first.finishedAt > second.finishedAt ? first : second
                }
                return first.id.uuidString < second.id.uuidString ? first : second
            })
        recordsByID = unique
        currentRecords = Array(unique.values)
        reconcileDirectUndoEligibility()
        allEntries = currentRecords.map(Self.makeEntry).sorted(by: Self.ordersEntries)
        recommendationIndex = ResearchLiteratureRecommendationDerivedIndex(
            records: currentRecords
        )
        reconcileRouteWithCurrentRecords()
        rebuildingGeneration &+= 1
        rebuildOptions()
        refilter()
    }

    private func applyRecordLocator(
        _ request: ResearchRecordsWindowRequest,
        presentsFollowUp: Bool
    ) {
        guard let recordID = request.recordID else { return }
        guard let record = currentRecords.first(where: { $0.id == recordID }) else {
            pendingFollowUpRecordID = nil
            route = .collection
            focusedStatementID = nil
            presentError(
                "The Research Record changed or was deleted. Search results must be refreshed."
            )
            return
        }
        if presentsFollowUp {
            pendingFollowUpRecordID = nil
        }
        if let statementID = request.statementID,
            !record.statements.contains(where: { $0.id == statementID })
        {
            pendingFollowUpRecordID = nil
            route = .collection
            focusedStatementID = nil
            presentError(
                "The matched Research Record statement is no longer available. Search results must be refreshed."
            )
            return
        }
        switch request.purpose {
        case .browse:
            guard let expected = request.expectedRecordFingerprint,
                  currentFingerprints[recordID] == expected else {
                route = .collection
                focusedStatementID = nil
                presentError(
                    "The Research Record changed or was deleted. Search results must be refreshed."
                )
                return
            }
        case .reviewResult:
            guard record.kind == .action,
                  let expected = request.expectedFinalizedResultFingerprint,
                  (try? record.finalizedResultFingerprint()) == expected else {
                route = .collection
                focusedStatementID = nil
                presentError(
                    "The Agent result changed or is no longer available. Refresh the Action status before reviewing it."
                )
                return
            }
            directUndoResultFingerprints[recordID] = expected
        case .followUp:
            guard record.kind == .action,
                  let expected = request.expectedFinalizedResultFingerprint,
                  (try? record.finalizedResultFingerprint()) == expected else {
                pendingFollowUpRecordID = nil
                route = .collection
                focusedStatementID = nil
                presentError(
                    "The Agent result changed or is no longer available. Refresh the Action before following up."
                )
                return
            }
            if presentsFollowUp {
                pendingFollowUpRecordID = recordID
                pendingFollowUpRequestGeneration &+= 1
            }
        }
        viewKind = .records
        selectedRecordID = recordID
        clearAllFilters()
        focusedStatementID = request.statementID
        refilterRecords()
    }

    private func reconcileDirectUndoEligibility() {
        directUndoResultFingerprints = directUndoResultFingerprints.filter {
            recordID, fingerprint in
            guard let record = recordsByID[recordID] else { return false }
            return (try? record.finalizedResultFingerprint()) == fingerprint
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isRecordSearchError = false
        isShowingError = true
    }

    private func presentRecordSearchError(_ message: String) {
        errorMessage = message
        isRecordSearchError = true
        isShowingError = true
    }

    private func rebuildOptions() {
        var notesByID: [UUID: ResearchRecordNoteOption] = [:]
        for entry in collectionEntries {
            for note in entry.noteParticipants {
                let candidate = ResearchRecordNoteOption(
                    id: note.noteID,
                    title: note.title,
                    role: note.role
                )
                guard let current = notesByID[note.noteID] else {
                    notesByID[note.noteID] = candidate
                    continue
                }
                if candidate.title.localizedStandardCompare(current.title)
                        == .orderedAscending
                {
                    notesByID[note.noteID] = candidate
                }
            }
        }
        noteOptions = notesByID.values.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        methodOptions = Set(collectionEntries.compactMap(\.methodName)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        actionOptions = Set(collectionEntries.map(\.actionID)).sorted {
            $0.rawValue < $1.rawValue
        }
        let authorOptions = Set(collectionEntries.flatMap(\.authorParticipants)).sorted {
            $0.rawValue < $1.rawValue
        }.map {
            ResearchRecordParticipantOption(
                filter: .author($0),
                title: $0.rawValue
            )
        }
        participantOptions =
            authorOptions
            + noteOptions.map {
                ResearchRecordParticipantOption(
                    filter: .note($0.id),
                    title: $0.title
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
        recordSearchTask?.cancel()
        recordSearchTask = nil
        guard route == .collection else {
            isLoadingRecords = false
            isLoadingMoreRecords = false
            recordLoadMoreErrorMessage = nil
            if isRecordSearchError { dismissError() }
            return
        }
        visibleEntries = []
        recordResultCount = 0
        hasMoreRecords = false
        isLoadingRecords = false
        isLoadingMoreRecords = false
        recordLoadMoreErrorMessage = nil
        guard recordSearch != nil, triptychID != nil else {
            return
        }
        guard hasRecordSearchCandidates else {
            if isRecordSearchError { dismissError() }
            return
        }
        requestRecordPage(offset: 0, appending: false)
    }

    private func requestRecordPage(
        offset: Int,
        appending: Bool
    ) {
        guard let recordSearch else { return }
        let generation = recordSearchGeneration
        if appending {
            isLoadingMoreRecords = true
            recordLoadMoreErrorMessage = nil
        } else {
            isLoadingRecords = true
        }
        let request = SearchRequest(
            query: recordSearchQuery,
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: SearchContract.recordCollectionPageSize,
            offset: offset,
            recordSort: recordSort
        )
        recordSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await recordSearch(request)
                try Task.checkCancellation()
                guard generation == recordSearchGeneration else { return }
                try acceptRecordSearchResponse(
                    response,
                    request: request,
                    appending: appending
                )
                isLoadingRecords = false
                isLoadingMoreRecords = false
                recordSearchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == recordSearchGeneration else { return }
                isLoadingRecords = false
                isLoadingMoreRecords = false
                recordSearchTask = nil
                if appending {
                    recordLoadMoreErrorMessage = error.localizedDescription
                } else {
                    visibleEntries = []
                    recordResultCount = 0
                    hasMoreRecords = false
                    presentRecordSearchError(
                        "Research Record Search failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func acceptRecordSearchResponse(
        _ response: SearchResponse,
        request: SearchRequest,
        appending: Bool
    ) throws {
        guard response.contractVersion == SearchContract.currentVersion,
            response.requestID == request.id,
            response.provider == .record,
            response.hasConsistentProviderIdentity,
            response.diagnostics.isEmpty,
            response.availability.recordAvailability?.presentsCurrentResults == true,
            let totalResultCount = response.totalResultCount
        else {
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
        let expectedHasMore = request.resultOffset + results.count < totalResultCount
        guard totalResultCount >= request.resultOffset + results.count,
              response.hasMore == expectedHasMore,
              (!appending || request.resultOffset == visibleEntries.count)
        else {
            throw ResearchRecordBrowserSearchError.invalidResponse(
                "The Record provider returned an inconsistent page boundary."
            )
        }
        var entries: [ResearchRecordIndexEntry] = []
        for result in results {
            guard let entry = allEntries.first(where: { $0.id == result.recordID }),
                currentFingerprints[result.recordID] == result.fingerprint
            else {
                throw ResearchRecordBrowserSearchError.invalidResponse(
                    "A Research Record changed while its results were being displayed."
                )
            }
            guard entry.isTopLevel else {
                throw ResearchRecordBrowserSearchError.invalidResponse(
                    "The Record provider returned a continuation as a collection row."
                )
            }
            entries.append(entry)
        }
        let existingIDs = Set(visibleEntries.map(\.id))
        guard !appending || entries.allSatisfy({ !existingIDs.contains($0.id) }) else {
            throw ResearchRecordBrowserSearchError.invalidResponse(
                "The Record provider returned a duplicate page."
            )
        }
        if isRecordSearchError { dismissError() }
        visibleEntries = appending ? visibleEntries + entries : entries
        recordResultCount = totalResultCount
        hasMoreRecords = response.hasMore
        recordLoadMoreErrorMessage = nil
    }

    private var recordSearchQuery: String {
        var clauses = ["kind:record"]
        clauses.append(
            contentsOf: searchText.split(whereSeparator: \.isWhitespace).map {
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

    /// Search remains the sole query owner. This check only recognizes an
    /// impossible empty corpus before asking it to resolve a Note clause that
    /// cannot occur in any currently published Record.
    private var hasRecordSearchCandidates: Bool {
        guard !currentRecords.isEmpty else { return false }
        guard let scopedNoteID else { return true }
        return currentRecords.contains { record in
            record.participatingNotes.contains { $0.noteID == scopedNoteID }
        }
    }

    private static func quotedSearchValue(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func makeEntry(_ record: PortableResearchRecord) -> ResearchRecordIndexEntry {
        let actionID =
            record.kind == .discussion
            ? ResearchActionID.discuss
            : record.action?.actionID ?? .discuss
        return ResearchRecordIndexEntry(
            id: record.id,
            finishedAt: record.finishedAt,
            title: record.title.value,
            noteTitle: record.researchRecordFocalNoteTitle ?? "Note unavailable",
            actionID: actionID,
            methodName: record.method?.displayName,
            sourceName: record.sourceReference?.displayName,
            reliability: ledgerFieldState(
                "reliability",
                actionID: actionID,
                record: record
            ),
            coverage: ledgerFieldState(
                "coverage",
                actionID: actionID,
                record: record
            ),
            noteParticipants: record.participatingNotes,
            authorParticipants: Set(record.statements.map(\.author)).sorted {
                $0.rawValue < $1.rawValue
            },
            resultDisposition: record.resultDisposition,
            statementCount: record.statements.count,
            isTopLevel: Self.isTopLevelCollectionRecord(record)
        )
    }

    private static func academicResultValue(
        _ result: PortableResearchAcademicFieldResult
    ) -> String? {
        guard let value = result.value else { return nil }
        return switch value {
        case .freeText(let text):
            text
        case .singleChoice(let choice):
            result.definition.choices.first { $0.value == choice }?.label ?? choice
        case .multipleChoice(let choices):
            choices.map { choice in
                result.definition.choices.first { $0.value == choice }?.label ?? choice
            }.joined(separator: ", ")
        }
    }

    private static func ledgerFieldState(
        _ fieldID: String,
        actionID: ResearchActionID,
        record: PortableResearchRecord
    ) -> ResearchRecordLedgerFieldState {
        guard actionID == .analyze else { return .notApplicable }
        guard
            let result = record.academicResults.first(where: {
                $0.definition.fieldID.rawValue == fieldID
            })
        else {
            return .unavailable
        }
        guard let value = academicResultValue(result),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .notSupplied
        }
        return .value(value)
    }

    private static func ordersEntries(
        _ lhs: ResearchRecordIndexEntry,
        _ rhs: ResearchRecordIndexEntry
    ) -> Bool {
        if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func ordersEntries(
        _ lhs: ResearchRecordIndexEntry,
        _ rhs: ResearchRecordIndexEntry,
        by sort: RecordSearchSortOrder
    ) -> Bool {
        switch sort {
        case .finishedAtDescending:
            return ordersEntries(lhs, rhs)
        case .finishedAtAscending:
            if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt < rhs.finishedAt }
        case .titleAscending, .titleDescending:
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            if comparison != .orderedSame {
                return sort == .titleAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
        case .actionAscending, .actionDescending:
            let comparison = lhs.actionID.rawValue.localizedStandardCompare(
                rhs.actionID.rawValue
            )
            if comparison != .orderedSame {
                return sort == .actionAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
        }
        if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func refilterRecommendations() {
        let noteID = scopedNoteID
        visibleRecommendationGroups = recommendationIndex.query(
            text: recommendationSearchText,
            noteID: noteID,
            status: recommendationFilter
        )
        filteredRecommendationOccurrences = visibleRecommendationGroups.flatMap(\.occurrences)
        recommendationResultCount = filteredRecommendationOccurrences.count
        let firstPageCount = min(
            SearchContract.recordCollectionPageSize,
            recommendationResultCount
        )
        visibleRecommendationOccurrences = Array(
            filteredRecommendationOccurrences.prefix(firstPageCount)
        )
        hasMoreRecommendations = firstPageCount < recommendationResultCount
    }

    private var collectionEntries: [ResearchRecordIndexEntry] {
        allEntries.filter(\.isTopLevel)
    }

    private static func isTopLevelCollectionRecord(
        _ record: PortableResearchRecord
    ) -> Bool {
        guard let kind = record.continuationLineage?.kind else { return true }
        return kind != .continueResearch && kind != .followUp
    }

    private func reconcileRouteWithCurrentRecords() {
        switch route {
        case .collection:
            return
        case .record(let id):
            guard recordsByID[id] == nil else { return }
        case .recommendation(let id):
            guard recommendationIndex.occurrence(id: id) == nil else { return }
        }
        activeRecordLocator = nil
        focusedStatementID = nil
        route = .collection
    }

    private var scopedNoteID: UUID? {
        scope == .thisNote ? contextNoteID : nil
    }
}
