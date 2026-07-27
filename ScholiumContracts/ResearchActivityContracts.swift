import Foundation

/// The only durable, researcher-meaningful milestones shown in Research
/// Activity. These are records of completed work, never a predicted workflow.
public enum PendingResearchStateKind: String, Codable, CaseIterable, Hashable, Sendable {
    case responseReady = "response_ready"
    case awaitingFidelity = "awaiting_fidelity"
    case changedSinceSettled = "changed_since_settled"
}

/// Identifies the researcher-facing route behind a transient response. A
/// Comment exchange and a whole-note Discuss run share the quiet
/// `responseReady` presentation but never share completion semantics.
public enum PendingResearchRoute: String, Codable, Hashable, Sendable {
    case comment
    case discuss
}

public struct ResearchActivityNoteReference: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchFunctionTargetRole
    /// Snapshot only. Titles remain researcher-authored document metadata;
    /// this preserves the source activity can name after a later rename.
    public let title: String

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One projected node for one note. Multi-note work shares an `activityID`,
/// source, target summary, and Research Record route across its nodes.
public struct PendingResearchState: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let kind: PendingResearchStateKind
    public let createdAt: Date
    public let activityID: UUID?
    /// Exact revision to which the transient state belongs when the state is
    /// revision-bound. Response-ready states do not need a fingerprint.
    public let fingerprint: DocumentFingerprint?
    public let route: PendingResearchRoute?

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        kind: PendingResearchStateKind,
        createdAt: Date = Date(),
        activityID: UUID? = nil,
        fingerprint: DocumentFingerprint? = nil,
        route: PendingResearchRoute? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.kind = kind
        self.createdAt = createdAt
        self.activityID = activityID
        self.fingerprint = fingerprint
        self.route = route
    }
}

/// A researcher-owned judgment that one exact saved revision is sufficiently
/// stable for current work. It is neither a truth claim nor qualification.
public struct SettlementRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let fingerprint: DocumentFingerprint
    public let settledAt: Date
    public let researcher: String
    public let rationale: String?

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        settledAt: Date = Date(),
        researcher: String = "Researcher",
        rationale: String? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.fingerprint = fingerprint
        self.settledAt = settledAt
        self.researcher = researcher.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = normalized?.isEmpty == false ? normalized : nil
    }
}

public enum ResearchWriteScope: String, Codable, CaseIterable, Hashable, Sendable {
    case currentNote = "current_note"
    case selectedNotes = "selected_notes"
    case analysesAndTopics = "analyses_and_topics"
    case entireTriptych = "entire_triptych"
}

public enum ResearchActivityGrantState: String, Codable, Hashable, Sendable {
    case active
    case completed
    case cancelled
    case revoked
    case expired
}

/// Durable internal authorization evidence for one multi-target write. The
/// plaintext activity key is deliberately excluded; only its digest persists.
public struct ResearchActivityGrant: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let activityID: UUID
    public let keyDigest: String
    public let origin: ResearchActivityNoteReference
    public let writeScope: ResearchWriteScope
    public let allowedTargets: [ResearchActivityNoteReference]
    /// Application-owned concurrency evidence, deliberately excluded from the
    /// prompt. Keys are stable note identities, not paths.
    public let startingFingerprints: [UUID: DocumentFingerprint]
    public let issuedAt: Date
    public let expiresAt: Date
    public var state: ResearchActivityGrantState
    /// Makes a keyed completion retry idempotent while rejecting a different
    /// payload after completion. The raw key is never persisted.
    public var completionPayloadDigest: String?
    public var completionReport: MultiTargetCompletionReport?

    public init(
        id: UUID = UUID(),
        activityID: UUID,
        keyDigest: String,
        origin: ResearchActivityNoteReference,
        writeScope: ResearchWriteScope,
        allowedTargets: [ResearchActivityNoteReference],
        startingFingerprints: [UUID: DocumentFingerprint],
        issuedAt: Date = Date(),
        expiresAt: Date,
        state: ResearchActivityGrantState = .active,
        completionPayloadDigest: String? = nil,
        completionReport: MultiTargetCompletionReport? = nil
    ) {
        self.id = id
        self.activityID = activityID
        self.keyDigest = keyDigest
        self.origin = origin
        self.writeScope = writeScope
        self.allowedTargets = allowedTargets.sorted {
            if $0.note.vaultID != $1.note.vaultID {
                return $0.note.vaultID.uuidString < $1.note.vaultID.uuidString
            }
            return $0.note.relativePath < $1.note.relativePath
        }
        self.startingFingerprints = startingFingerprints
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.state = state
        self.completionPayloadDigest = completionPayloadDigest
        self.completionReport = completionReport
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityID, keyDigest, origin, writeScope, allowedTargets
        case startingFingerprints, issuedAt, expiresAt, state
        case completionPayloadDigest, completionReport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            activityID: try container.decode(UUID.self, forKey: .activityID),
            keyDigest: try container.decode(String.self, forKey: .keyDigest),
            origin: try container.decode(ResearchActivityNoteReference.self, forKey: .origin),
            writeScope: try container.decode(ResearchWriteScope.self, forKey: .writeScope),
            allowedTargets: try container.decode(
                [ResearchActivityNoteReference].self,
                forKey: .allowedTargets
            ),
            startingFingerprints: try container.decodeIfPresent(
                [UUID: DocumentFingerprint].self,
                forKey: .startingFingerprints
            ) ?? [:],
            issuedAt: try container.decode(Date.self, forKey: .issuedAt),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt),
            state: try container.decode(ResearchActivityGrantState.self, forKey: .state),
            completionPayloadDigest: try container.decodeIfPresent(
                String.self,
                forKey: .completionPayloadDigest
            ),
            completionReport: try container.decodeIfPresent(
                MultiTargetCompletionReport.self,
                forKey: .completionReport
            )
        )
    }
}

/// The only object containing the plaintext activity key. Delivery adapters
/// may hand it to the selected agent, but it is never Codable or persisted.
public struct ResearchActivityGrantAuthorization: Sendable {
    public let grant: ResearchActivityGrant
    public let activityKey: String

    public init(grant: ResearchActivityGrant, activityKey: String) {
        self.grant = grant
        self.activityKey = activityKey
    }
}

/// Agent-authored candidate report. It deliberately contains neither final
/// fingerprints nor any claim that Scholium attributed a filesystem change.
public struct ResearchActivityCompletionSubmission: Codable, Hashable, Sendable {
    public let activityID: UUID
    public let activityKey: String
    public let candidateModifiedNotes: [VaultQualifiedNoteID]
    public let summary: String
    public let submittedAt: Date

    public init(
        activityID: UUID,
        activityKey: String,
        candidateModifiedNotes: [VaultQualifiedNoteID],
        summary: String,
        submittedAt: Date = Date()
    ) {
        self.activityID = activityID
        self.activityKey = activityKey
        self.candidateModifiedNotes = Array(Set(candidateModifiedNotes)).sorted()
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.submittedAt = submittedAt
    }
}

/// Application-confirmed result after bounded fingerprint and containment
/// checks. This is the sole source for HUD projection and modified counts.
public struct MultiTargetCompletionReport: Codable, Hashable, Sendable {
    public let activityID: UUID
    public let candidateModifiedNotes: [VaultQualifiedNoteID]
    public let confirmedModifiedNotes: [ResearchActivityNoteReference]
    public let unmodifiedNotes: [ResearchActivityNoteReference]
    public let unreportedChangedNotes: [ResearchActivityNoteReference]
    /// Application-observed exact revisions at completion. Only stable note
    /// IDs are persisted as keys; the agent neither supplies nor validates
    /// these fingerprints.
    public let observedFingerprints: [UUID: DocumentFingerprint]
    public let summary: String
    public let completedAt: Date

    public init(
        activityID: UUID,
        candidateModifiedNotes: [VaultQualifiedNoteID],
        confirmedModifiedNotes: [ResearchActivityNoteReference] = [],
        unmodifiedNotes: [ResearchActivityNoteReference] = [],
        unreportedChangedNotes: [ResearchActivityNoteReference] = [],
        observedFingerprints: [UUID: DocumentFingerprint] = [:],
        summary: String,
        completedAt: Date = Date()
    ) {
        self.activityID = activityID
        self.candidateModifiedNotes = Array(Set(candidateModifiedNotes)).sorted()
        self.confirmedModifiedNotes = Self.orderedUnique(confirmedModifiedNotes)
        self.unmodifiedNotes = Self.orderedUnique(unmodifiedNotes)
        self.unreportedChangedNotes = Self.orderedUnique(unreportedChangedNotes)
        self.observedFingerprints = observedFingerprints
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case activityID, candidateModifiedNotes, confirmedModifiedNotes
        case unmodifiedNotes, unreportedChangedNotes, observedFingerprints
        case summary, completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            activityID: try container.decode(UUID.self, forKey: .activityID),
            candidateModifiedNotes: try container.decode(
                [VaultQualifiedNoteID].self,
                forKey: .candidateModifiedNotes
            ),
            confirmedModifiedNotes: try container.decodeIfPresent(
                [ResearchActivityNoteReference].self,
                forKey: .confirmedModifiedNotes
            ) ?? [],
            unmodifiedNotes: try container.decodeIfPresent(
                [ResearchActivityNoteReference].self,
                forKey: .unmodifiedNotes
            ) ?? [],
            unreportedChangedNotes: try container.decodeIfPresent(
                [ResearchActivityNoteReference].self,
                forKey: .unreportedChangedNotes
            ) ?? [],
            observedFingerprints: try container.decodeIfPresent(
                [UUID: DocumentFingerprint].self,
                forKey: .observedFingerprints
            ) ?? [:],
            summary: try container.decode(String.self, forKey: .summary),
            completedAt: try container.decode(Date.self, forKey: .completedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activityID, forKey: .activityID)
        try container.encode(candidateModifiedNotes, forKey: .candidateModifiedNotes)
        try container.encode(confirmedModifiedNotes, forKey: .confirmedModifiedNotes)
        try container.encode(unmodifiedNotes, forKey: .unmodifiedNotes)
        try container.encode(unreportedChangedNotes, forKey: .unreportedChangedNotes)
        if !observedFingerprints.isEmpty {
            try container.encode(observedFingerprints, forKey: .observedFingerprints)
        }
        try container.encode(summary, forKey: .summary)
        try container.encode(completedAt, forKey: .completedAt)
    }

    private static func orderedUnique(
        _ notes: [ResearchActivityNoteReference]
    ) -> [ResearchActivityNoteReference] {
        var seen: Set<UUID> = []
        return notes
            .filter { seen.insert($0.noteID).inserted }
            .sorted {
                if $0.note.vaultID != $1.note.vaultID {
                    return $0.note.vaultID.uuidString < $1.note.vaultID.uuidString
                }
                return $0.note.relativePath < $1.note.relativePath
            }
    }
}
