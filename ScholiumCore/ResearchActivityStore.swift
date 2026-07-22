import Foundation
import ScholiumContracts

/// App-owned activity, settlement, and communication records.
/// The store is intentionally independent of legacy Human Review persistence:
/// it never reuses qualification or Review state as Settlement. Private page
/// Annotations belong to `PageAnnotationStore` and cannot enter this timeline.
public actor ResearchActivityStore {
    private static let currentSchemaVersion = 2

    private struct Payload: Codable {
        var schemaVersion: Int
        var events: [ResearchActivityEvent]
        var settlements: [SettlementRecord]
        var exchanges: [CommentExchange]
        var pendingStates: [PendingResearchState]
        var grants: [ResearchActivityGrant]
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var payload: Payload
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileURL = storageURL.appendingPathComponent("research-activity.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                var decoded = try decoder.decode(Payload.self, from: data)
                switch decoded.schemaVersion {
                case Self.currentSchemaVersion:
                    payload = decoded
                    loadFailure = nil
                case 1:
                    let backupURL = storageURL.appendingPathComponent(
                        "research-activity.v1.backup.json",
                        isDirectory: false
                    )
                    if !fileManager.fileExists(atPath: backupURL.path) {
                        // The source file remains intact until the migrated
                        // payload has been validated. Use an exclusive write
                        // for the immutable backup; Foundation does not allow
                        // `.atomic` and `.withoutOverwriting` together.
                        try data.write(to: backupURL, options: .withoutOverwriting)
                    }
                    decoded.schemaVersion = Self.currentSchemaVersion
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let migratedData = try encoder.encode(decoded)
                    _ = try decoder.decode(Payload.self, from: migratedData)
                    try migratedData.write(to: fileURL, options: .atomic)
                    payload = decoded
                    loadFailure = nil
                default:
                    payload = Self.emptyPayload
                    loadFailure = "Unsupported Research Activity schema version \(decoded.schemaVersion)."
                }
            } catch {
                payload = Self.emptyPayload
                loadFailure = error.localizedDescription
            }
        } else {
            payload = Self.emptyPayload
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Research Activity", reason: $0)
                .localizedDescription
        }
    }

    public func allEvents() -> [ResearchActivityEvent] {
        payload.events.sorted(by: Self.eventOrder)
    }

    public func events(for noteID: UUID) -> [ResearchActivityEvent] {
        payload.events.filter { $0.note.noteID == noteID }.sorted(by: Self.eventOrder)
    }

    public func pendingStates(for noteID: UUID) -> [PendingResearchState] {
        payload.pendingStates
            .filter { $0.noteID == noteID }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func allSettlements() -> [SettlementRecord] {
        payload.settlements.sorted { lhs, rhs in
            if lhs.settledAt != rhs.settledAt { return lhs.settledAt > rhs.settledAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func latestSettlement(for noteID: UUID) -> SettlementRecord? {
        payload.settlements
            .filter { $0.noteID == noteID }
            .max { lhs, rhs in
                if lhs.settledAt != rhs.settledAt { return lhs.settledAt < rhs.settledAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func exchanges(for noteID: UUID) -> [CommentExchange] {
        payload.exchanges
            .filter { $0.note.noteID == noteID }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func allExchanges() -> [CommentExchange] {
        payload.exchanges.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func exchange(id: UUID) -> CommentExchange? {
        payload.exchanges.first { $0.id == id }
    }

    public func allPendingStates() -> [PendingResearchState] {
        payload.pendingStates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func grants() -> [ResearchActivityGrant] {
        payload.grants.sorted { lhs, rhs in
            if lhs.issuedAt != rhs.issuedAt { return lhs.issuedAt > rhs.issuedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func grant(activityID: UUID) -> ResearchActivityGrant? {
        payload.grants.first { $0.activityID == activityID }
    }

    /// Creates one short-lived authorization and returns the only copy of its
    /// plaintext key. The key is high-entropy and the persisted digest is used
    /// only to authenticate a completion report, never as filesystem access.
    public func issueGrant(
        activityID: UUID = UUID(),
        origin: ResearchActivityNoteReference,
        writeScope: ResearchWriteScope,
        allowedTargets: [ResearchActivityNoteReference],
        startingFingerprints: [UUID: DocumentFingerprint],
        issuedAt: Date = Date(),
        validFor requestedDuration: TimeInterval = 60 * 60
    ) throws -> ResearchActivityGrantAuthorization {
        try requireHealthyStore()
        guard payload.grants.allSatisfy({ $0.activityID != activityID }) else {
            throw ResearchActivityGrantError.duplicateActivity(activityID)
        }
        let distinctTargets = Dictionary(
            allowedTargets.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !distinctTargets.isEmpty else {
            throw ResearchActivityGrantError.emptyWriteSet
        }
        guard Set(distinctTargets.keys) == Set(startingFingerprints.keys) else {
            throw ResearchActivityGrantError.incompleteStartingFingerprints
        }
        let maximumDuration: TimeInterval = 24 * 60 * 60
        let duration = min(max(1, requestedDuration), maximumDuration)
        let rawKey = [UUID().uuidString, UUID().uuidString]
            .joined(separator: "-")
            .lowercased()
        let grant = ResearchActivityGrant(
            activityID: activityID,
            keyDigest: Self.digest(rawKey),
            origin: origin,
            writeScope: writeScope,
            allowedTargets: Array(distinctTargets.values),
            startingFingerprints: startingFingerprints,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(duration)
        )
        var proposed = payload
        proposed.grants.append(grant)
        try commit(proposed)
        return ResearchActivityGrantAuthorization(grant: grant, activityKey: rawKey)
    }

    /// Validates key state without exposing the persisted digest. Expiry is
    /// committed before returning so a crashed completion cannot revive it.
    public func authorizeCompletion(
        activityID: UUID,
        activityKey: String,
        at date: Date = Date()
    ) throws -> ResearchActivityGrant {
        try requireHealthyStore()
        guard let index = payload.grants.firstIndex(where: {
            $0.activityID == activityID
        }) else {
            throw ResearchActivityGrantError.notFound(activityID)
        }
        var grant = payload.grants[index]
        if grant.state == .active, date > grant.expiresAt {
            grant.state = .expired
            var proposed = payload
            proposed.grants[index] = grant
            try commit(proposed)
        }
        guard grant.keyDigest == Self.digest(activityKey) else {
            throw ResearchActivityGrantError.keyMismatch
        }
        switch grant.state {
        case .active, .completed:
            return grant
        case .cancelled, .revoked, .expired:
            throw ResearchActivityGrantError.inactive(grant.state)
        }
    }

    /// Commits the Application-confirmed report. An exact keyed retry returns
    /// its existing report; any different payload after completion is rejected.
    @discardableResult
    public func completeGrant(
        activityID: UUID,
        activityKey: String,
        completionPayloadDigest: String,
        report: MultiTargetCompletionReport,
        projectedEvents: [ResearchActivityEvent]
    ) throws -> MultiTargetCompletionReport {
        try requireHealthyStore()
        guard report.activityID == activityID,
              projectedEvents.allSatisfy({ $0.activityID == activityID }) else {
            throw ResearchActivityGrantError.activityMismatch
        }
        let grant = try authorizeCompletion(
            activityID: activityID,
            activityKey: activityKey,
            at: report.completedAt
        )
        guard let index = payload.grants.firstIndex(where: {
            $0.activityID == activityID
        }) else {
            throw ResearchActivityGrantError.notFound(activityID)
        }
        if grant.state == .completed {
            guard grant.completionPayloadDigest == completionPayloadDigest,
                  let existingReport = grant.completionReport else {
                throw ResearchActivityGrantError.completionAlreadyRecorded(activityID)
            }
            return existingReport
        }

        let allowedIDs = Set(grant.allowedTargets.map(\.noteID))
        let confirmedIDs = Set(report.confirmedModifiedNotes.map(\.noteID))
        let unmodifiedIDs = Set(report.unmodifiedNotes.map(\.noteID))
        let unreportedIDs = Set(report.unreportedChangedNotes.map(\.noteID))
        guard confirmedIDs.isDisjoint(with: unmodifiedIDs),
              confirmedIDs.isDisjoint(with: unreportedIDs),
              unmodifiedIDs.isDisjoint(with: unreportedIDs),
              confirmedIDs.union(unmodifiedIDs).union(unreportedIDs)
                .isSubset(of: allowedIDs),
              Set(report.observedFingerprints.keys).isSubset(of: allowedIDs),
              confirmedIDs.isSubset(of: Set(report.observedFingerprints.keys)) else {
            throw ResearchActivityGrantError.invalidConfirmedSets
        }
        guard Set(projectedEvents.map { $0.note.noteID }) == confirmedIDs else {
            throw ResearchActivityGrantError.invalidProjection
        }

        var proposed = payload
        proposed.grants[index].state = .completed
        proposed.grants[index].completionPayloadDigest = completionPayloadDigest
        proposed.grants[index].completionReport = report
        for event in projectedEvents where !proposed.events.contains(where: { $0.id == event.id }) {
            proposed.events.append(event)
        }
        for note in report.confirmedModifiedNotes {
            proposed.pendingStates.removeAll {
                $0.noteID == note.noteID && $0.kind == .awaitingFidelity
            }
            proposed.pendingStates.append(PendingResearchState(
                id: Self.stablePendingID(activityID: activityID, noteID: note.noteID),
                noteID: note.noteID,
                kind: .awaitingFidelity,
                createdAt: report.completedAt,
                activityID: activityID,
                fingerprint: report.observedFingerprints[note.noteID]
            ))
        }
        try commit(proposed)
        return payload.grants[index].completionReport ?? report
    }

    public func cancelGrant(activityID: UUID) throws {
        try transitionGrant(activityID: activityID, to: .cancelled)
    }

    public func revokeGrant(activityID: UUID) throws {
        try transitionGrant(activityID: activityID, to: .revoked)
    }

    @discardableResult
    public func appendEvent(_ event: ResearchActivityEvent) throws -> ResearchActivityEvent {
        try requireHealthyStore()
        if let existing = payload.events.first(where: { $0.id == event.id }) {
            return existing
        }
        var proposed = payload
        proposed.events.append(event)
        try commit(proposed)
        return event
    }

    /// Creation is the only event that may be inferred from Scholium's own
    /// identity assignment. Existing notes are never backfilled without that
    /// reliable creation evidence.
    @discardableResult
    public func recordCreated(
        note: ResearchActivityNoteReference,
        occurredAt: Date = Date()
    ) throws -> ResearchActivityEvent {
        try requireHealthyStore()
        if let existing = payload.events.first(where: {
            $0.note.noteID == note.noteID && $0.kind == .created
        }) {
            return existing
        }
        let activityID = UUID()
        let event = ResearchActivityEvent(
            activityID: activityID,
            note: note,
            kind: .created,
            occurredAt: occurredAt,
            origin: note,
            researchRecordID: activityID
        )
        var proposed = payload
        proposed.events.append(event)
        try commit(proposed)
        return event
    }

    /// Records an authoritative state without accidentally treating it as a
    /// workflow stage. Revision-bound states supersede their prior value;
    /// independent response-ready activities remain independently actionable.
    @discardableResult
    public func setPendingState(_ state: PendingResearchState) throws -> PendingResearchState {
        try requireHealthyStore()
        var proposed = payload
        proposed.pendingStates.removeAll { existing in
            guard existing.noteID == state.noteID,
                  existing.kind == state.kind else { return false }
            if state.kind == .responseReady {
                return existing.activityID == state.activityID
            }
            return true
        }
        proposed.pendingStates.append(state)
        try commit(proposed)
        return state
    }

    public func clearPendingState(
        noteID: UUID,
        kind: PendingResearchStateKind
    ) throws {
        try requireHealthyStore()
        guard payload.pendingStates.contains(where: {
            $0.noteID == noteID && $0.kind == kind
        }) else { return }
        var proposed = payload
        proposed.pendingStates.removeAll { $0.noteID == noteID && $0.kind == kind }
        try commit(proposed)
    }

    /// Keeps Changed since settled derived from the current source revision
    /// while preserving its first observed time. It creates no history node.
    public func synchronizeSettlementCurrency(
        noteID: UUID,
        currentFingerprint: DocumentFingerprint,
        activityID: UUID? = nil
    ) throws {
        try requireHealthyStore()
        guard let settlement = latestSettlement(for: noteID) else {
            try clearPendingState(noteID: noteID, kind: .changedSinceSettled)
            return
        }
        if settlement.fingerprint == currentFingerprint {
            try clearPendingState(noteID: noteID, kind: .changedSinceSettled)
            return
        }
        guard !payload.pendingStates.contains(where: {
            $0.noteID == noteID && $0.kind == .changedSinceSettled
        }) else { return }
        var proposed = payload
        proposed.pendingStates.append(PendingResearchState(
            noteID: noteID,
            kind: .changedSinceSettled,
            activityID: activityID
        ))
        try commit(proposed)
    }

    /// Repeating Settle on the same exact revision returns its existing record
    /// and does not append a duplicate Settled node.
    @discardableResult
    public func settle(
        note: ResearchActivityNoteReference,
        fingerprint: DocumentFingerprint,
        researcher: String = "Researcher",
        rationale: String? = nil,
        settledAt: Date = Date()
    ) throws -> SettlementRecord {
        try requireHealthyStore()
        if let existing = payload.settlements.first(where: {
            $0.noteID == note.noteID && $0.fingerprint == fingerprint
        }) {
            return existing
        }

        let settlement = SettlementRecord(
            noteID: note.noteID,
            fingerprint: fingerprint,
            settledAt: settledAt,
            researcher: researcher,
            rationale: rationale
        )
        let activityID = settlement.id
        let event = ResearchActivityEvent(
            activityID: activityID,
            note: note,
            kind: .settled,
            occurredAt: settledAt,
            origin: note,
            researchRecordID: activityID
        )
        var proposed = payload
        proposed.settlements.append(settlement)
        proposed.events.append(event)
        proposed.pendingStates.removeAll {
            $0.noteID == note.noteID && $0.kind == .changedSinceSettled
        }
        try commit(proposed)
        return payload.settlements.first(where: { $0.id == settlement.id }) ?? settlement
    }

    @discardableResult
    public func createExchange(_ exchange: CommentExchange) throws -> CommentExchange {
        try requireHealthyStore()
        guard exchange.anchor.state == .attached else {
            throw CommentExchangeError.selectionUnavailable
        }
        guard exchange.status == .awaitingReply,
              exchange.turns.count == 1,
              exchange.turns.first?.author == .researcher,
              exchange.turns.first?.text.isEmpty == false else {
            throw CommentExchangeError.initialResearcherMessageRequired
        }
        guard !payload.exchanges.contains(where: { $0.id == exchange.id }) else {
            throw CommentExchangeError.duplicateExchange(exchange.id)
        }
        var proposed = payload
        proposed.exchanges.append(exchange)
        proposed.pendingStates.removeAll {
            $0.noteID == exchange.note.noteID
                && $0.kind == .responseReady
                && $0.activityID == exchange.id
        }
        try commit(proposed)
        return exchange
    }

    @discardableResult
    public func appendExchangeTurn(
        exchangeID: UUID,
        turn: CommentExchangeTurn
    ) throws -> CommentExchange {
        try requireHealthyStore()
        guard let index = payload.exchanges.firstIndex(where: { $0.id == exchangeID }) else {
            throw CommentExchangeError.exchangeNotFound(exchangeID)
        }
        guard payload.exchanges[index].status != .finished else {
            throw CommentExchangeError.exchangeAlreadyFinished(exchangeID)
        }
        guard !turn.text.isEmpty else {
            throw CommentExchangeError.emptyTurn
        }
        let expectedAuthor: CommentExchangeTurnAuthor = switch payload.exchanges[index].status {
        case .awaitingReply: .agent
        case .responseReady: .researcher
        case .finished: .researcher
        }
        guard turn.author == expectedAuthor else {
            throw CommentExchangeError.unexpectedTurn(expected: expectedAuthor)
        }
        var proposed = payload
        proposed.exchanges[index].turns.append(turn)
        proposed.exchanges[index].updatedAt = turn.createdAt
        proposed.exchanges[index].status = turn.author == .agent ? .responseReady : .awaitingReply
        let exchange = proposed.exchanges[index]
        proposed.pendingStates.removeAll {
            $0.noteID == exchange.note.noteID
                && $0.kind == .responseReady
                && $0.activityID == exchange.id
        }
        if exchange.status == .responseReady {
            proposed.pendingStates.append(PendingResearchState(
                noteID: exchange.note.noteID,
                kind: .responseReady,
                createdAt: turn.createdAt,
                activityID: exchange.id,
                route: .comment
            ))
        }
        try commit(proposed)
        return exchange
    }

    /// Finishing is researcher-only and idempotently creates one Commented
    /// event after at least one agent reply has been reviewed.
    @discardableResult
    public func finishExchange(
        exchangeID: UUID,
        finishedAt: Date = Date()
    ) throws -> CommentExchange {
        try requireHealthyStore()
        guard let index = payload.exchanges.firstIndex(where: { $0.id == exchangeID }) else {
            throw CommentExchangeError.exchangeNotFound(exchangeID)
        }
        if payload.exchanges[index].status == .finished {
            return payload.exchanges[index]
        }
        let exchange = payload.exchanges[index]
        guard exchange.status == .responseReady,
              exchange.turns.last?.author == .agent else {
            throw CommentExchangeError.agentReplyRequired
        }
        var proposed = payload
        proposed.exchanges[index].status = .finished
        proposed.exchanges[index].finishedAt = finishedAt
        proposed.exchanges[index].updatedAt = finishedAt
        proposed.pendingStates.removeAll {
            $0.noteID == exchange.note.noteID
                && $0.kind == .responseReady
                && $0.activityID == exchange.id
        }
        proposed.events.append(ResearchActivityEvent(
            activityID: exchange.id,
            note: exchange.note,
            kind: .commented,
            occurredAt: finishedAt,
            origin: exchange.note,
            researchRecordID: exchange.id
        ))
        let completed = proposed.exchanges[index]
        try commit(proposed)
        return completed
    }

    /// A completed read-only Discuss run becomes durable research activity
    /// only after the researcher has reviewed its response and explicitly
    /// finishes it. Retrying Finish is idempotent.
    @discardableResult
    public func finishDiscussion(
        note: ResearchActivityNoteReference,
        runID: UUID,
        finishedAt: Date = Date()
    ) throws -> ResearchActivityEvent {
        try requireHealthyStore()
        if let existing = payload.events.first(where: {
            $0.activityID == runID && $0.kind == .discussed
        }) {
            return existing
        }
        guard payload.pendingStates.contains(where: {
            $0.noteID == note.noteID
                && $0.kind == .responseReady
                && $0.activityID == runID
                && $0.route == .discuss
        }) else {
            throw DiscussionCompletionError.responseNotReady(runID)
        }
        let event = ResearchActivityEvent(
            id: runID,
            activityID: runID,
            note: note,
            kind: .discussed,
            occurredAt: finishedAt,
            origin: note,
            researchRecordID: runID
        )
        var proposed = payload
        proposed.pendingStates.removeAll {
            $0.noteID == note.noteID
                && $0.kind == .responseReady
                && $0.activityID == runID
                && $0.route == .discuss
        }
        proposed.events.append(event)
        try commit(proposed)
        return event
    }

    private static var emptyPayload: Payload {
        Payload(
            schemaVersion: currentSchemaVersion,
            events: [],
            settlements: [],
            exchanges: [],
            pendingStates: [],
            grants: []
        )
    }

    private func requireHealthyStore() throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Research Activity",
                reason: loadFailure
            )
        }
    }

    private func commit(_ proposed: Payload) throws {
        try requireHealthyStore()
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(proposed)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonical = try decoder.decode(Payload.self, from: data)
        try data.write(to: fileURL, options: .atomic)
        payload = canonical
    }

    private func transitionGrant(
        activityID: UUID,
        to state: ResearchActivityGrantState
    ) throws {
        try requireHealthyStore()
        guard let index = payload.grants.firstIndex(where: {
            $0.activityID == activityID
        }) else {
            throw ResearchActivityGrantError.notFound(activityID)
        }
        if payload.grants[index].state == state { return }
        guard payload.grants[index].state == .active else {
            throw ResearchActivityGrantError.inactive(payload.grants[index].state)
        }
        var proposed = payload
        proposed.grants[index].state = state
        try commit(proposed)
    }

    private static func digest(_ value: String) -> String {
        DocumentFingerprint(content: value).sha256
    }

    private static func stablePendingID(activityID: UUID, noteID: UUID) -> UUID {
        let digest = DocumentFingerprint(
            content: "awaiting-fidelity:\(activityID.uuidString):\(noteID.uuidString)"
        ).sha256
        let compact = String(digest.prefix(32))
        let uuid = [
            compact.prefix(8),
            compact.dropFirst(8).prefix(4),
            compact.dropFirst(12).prefix(4),
            compact.dropFirst(16).prefix(4),
            compact.dropFirst(20).prefix(12),
        ].map(String.init).joined(separator: "-")
        return UUID(uuidString: uuid) ?? UUID()
    }

    private static func eventOrder(
        _ lhs: ResearchActivityEvent,
        _ rhs: ResearchActivityEvent
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum ResearchActivityGrantError: LocalizedError, Sendable {
    case duplicateActivity(UUID)
    case emptyWriteSet
    case incompleteStartingFingerprints
    case notFound(UUID)
    case keyMismatch
    case inactive(ResearchActivityGrantState)
    case activityMismatch
    case completionAlreadyRecorded(UUID)
    case invalidConfirmedSets
    case invalidProjection

    public var errorDescription: String? {
        switch self {
        case .duplicateActivity(let id):
            "Research Activity already exists: \(id.uuidString)"
        case .emptyWriteSet:
            "A Write activity requires at least one explicitly authorized note."
        case .incompleteStartingFingerprints:
            "Every authorized note requires one frozen starting fingerprint."
        case .notFound(let id):
            "Research Activity grant was not found: \(id.uuidString)"
        case .keyMismatch:
            "The activity key does not match this Research Activity."
        case .inactive(let state):
            "The Research Activity grant is no longer active: \(state.rawValue)"
        case .activityMismatch:
            "The completion report does not belong to this Research Activity."
        case .completionAlreadyRecorded(let id):
            "A different completion is already recorded for Research Activity \(id.uuidString)."
        case .invalidConfirmedSets:
            "The confirmed, unmodified, and unreported sets must be disjoint and remain inside the frozen authorization."
        case .invalidProjection:
            "HUD events must match the Application-confirmed modified set exactly."
        }
    }
}

public enum CommentExchangeError: LocalizedError, Sendable {
    case selectionUnavailable
    case initialResearcherMessageRequired
    case duplicateExchange(UUID)
    case exchangeNotFound(UUID)
    case exchangeAlreadyFinished(UUID)
    case emptyTurn
    case unexpectedTurn(expected: CommentExchangeTurnAuthor)
    case agentReplyRequired

    public var errorDescription: String? {
        switch self {
        case .selectionUnavailable:
            "Comment requires an attached source selection."
        case .initialResearcherMessageRequired:
            "Comment requires an initial researcher message."
        case .duplicateExchange(let id):
            "Comment exchange is already recorded: \(id.uuidString)"
        case .exchangeNotFound(let id):
            "Comment exchange was not found: \(id.uuidString)"
        case .exchangeAlreadyFinished(let id):
            "Comment exchange is already finished: \(id.uuidString)"
        case .emptyTurn:
            "A Comment turn cannot be empty."
        case .unexpectedTurn(let expected):
            expected == .agent
                ? "The Comment is waiting for an agent reply."
                : "Review the agent reply, then Follow Up or Finish."
        case .agentReplyRequired:
            "Finish requires an agent reply that the researcher can review."
        }
    }
}

public enum DiscussionCompletionError: LocalizedError, Sendable {
    case responseNotReady(UUID)

    public var errorDescription: String? {
        switch self {
        case .responseNotReady(let id):
            "The Discuss response is not ready for researcher completion: \(id.uuidString)"
        }
    }
}
