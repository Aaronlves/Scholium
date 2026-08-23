import Foundation
import ScholiumContracts

public enum AgentAnalysisCreationBindingState: String, Codable, Hashable, Sendable {
    /// The request is durable, but no Zotero binding mutation has begun.
    case reserved
    /// A binding mutation crossed its invocation boundary. Replay must inspect
    /// the authoritative binding and may never issue another write by inference.
    case writing
    /// The binding owner proved that the attempted mutation did not commit, so
    /// an exact retry may begin again after re-reading current authority.
    case retryable
    /// The requested binding was read back exactly.
    case committed
}

/// Machine-local idempotency evidence for the source-ahead portion of one
/// Agent-originated Analysis creation. It is not a Run, portable relationship,
/// write authority, or system-Trash participant; the portable binding and Note
/// remain independently authoritative.
public struct AgentAnalysisCreationReservation: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let triptychID: UUID
    public let runID: UUID
    public let requestFingerprint: DocumentFingerprint
    public let creationPayloadFingerprint: DocumentFingerprint
    public let startRequestFingerprint: DocumentFingerprint
    public let target: VaultQualifiedNoteID
    public let reservedIdentityID: UUID
    public let requestedBinding: AnalysisZoteroBinding?
    public let sourceRoute: ResearchAgentSourceRoute?
    public let initialMetadata: AnalysisCreationMetadata
    public let initialAuthoredYAML: AuthoredNoteYAML?
    public let academicPurpose: String?
    public var committedSourceFingerprint: DocumentFingerprint?
    public var bindingState: AgentAnalysisCreationBindingState?

    public var id: UUID { runID }

    public init(
        triptychID: UUID,
        runID: UUID,
        requestFingerprint: DocumentFingerprint,
        creationPayloadFingerprint: DocumentFingerprint,
        startRequestFingerprint: DocumentFingerprint,
        target: VaultQualifiedNoteID,
        reservedIdentityID: UUID,
        requestedBinding: AnalysisZoteroBinding?,
        sourceRoute: ResearchAgentSourceRoute?,
        initialMetadata: AnalysisCreationMetadata,
        initialAuthoredYAML: AuthoredNoteYAML?,
        academicPurpose: String?,
        committedSourceFingerprint: DocumentFingerprint? = nil,
        bindingState: AgentAnalysisCreationBindingState? = nil
    ) throws {
        guard (requestedBinding == nil) != (sourceRoute == nil),
              requestedBinding?.noteID == reservedIdentityID || requestedBinding == nil,
              requestedBinding != nil
                ? sourceRoute == nil
                : (sourceRoute == .researcherProvided && bindingState == nil) else {
            throw AgentAnalysisCreationReservationStoreError.reservationMismatch(runID)
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.runID = runID
        self.requestFingerprint = requestFingerprint
        self.creationPayloadFingerprint = creationPayloadFingerprint
        self.startRequestFingerprint = startRequestFingerprint
        self.target = target
        self.reservedIdentityID = reservedIdentityID
        self.requestedBinding = requestedBinding
        self.sourceRoute = sourceRoute
        self.initialMetadata = initialMetadata
        self.initialAuthoredYAML = initialAuthoredYAML
        self.academicPurpose = academicPurpose
        self.committedSourceFingerprint = committedSourceFingerprint
        self.bindingState = requestedBinding == nil ? nil : (bindingState ?? .reserved)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case runID = "run_id"
        case requestFingerprint = "request_fingerprint"
        case creationPayloadFingerprint = "creation_payload_fingerprint"
        case startRequestFingerprint = "start_request_fingerprint"
        case target
        case reservedIdentityID = "reserved_identity_id"
        case requestedBinding = "requested_binding"
        case sourceRoute = "source_route"
        case initialMetadata = "initial_metadata"
        case initialAuthoredYAML = "initial_authored_yaml"
        case academicPurpose = "academic_purpose"
        case committedSourceFingerprint = "committed_source_fingerprint"
        case bindingState = "binding_state"
    }

    public init(from decoder: Decoder) throws {
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: AgentAnalysisCreationReservationStoreError.unsupportedField
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AgentAnalysisCreationReservationStoreError
                .unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            runID: container.decode(UUID.self, forKey: .runID),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            creationPayloadFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .creationPayloadFingerprint
            ),
            startRequestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .startRequestFingerprint
            ),
            target: container.decode(VaultQualifiedNoteID.self, forKey: .target),
            reservedIdentityID: container.decode(UUID.self, forKey: .reservedIdentityID),
            requestedBinding: container.decodeIfPresent(
                AnalysisZoteroBinding.self,
                forKey: .requestedBinding
            ),
            sourceRoute: container.decodeIfPresent(
                ResearchAgentSourceRoute.self,
                forKey: .sourceRoute
            ),
            initialMetadata: container.decode(
                AnalysisCreationMetadata.self,
                forKey: .initialMetadata
            ),
            initialAuthoredYAML: container.decodeIfPresent(
                AuthoredNoteYAML.self,
                forKey: .initialAuthoredYAML
            ),
            academicPurpose: container.decodeIfPresent(
                String.self,
                forKey: .academicPurpose
            ),
            committedSourceFingerprint: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .committedSourceFingerprint
            ),
            bindingState: container.decodeIfPresent(
                AgentAnalysisCreationBindingState.self,
                forKey: .bindingState
            )
        )
    }
}

public enum AgentAnalysisCreationReservationStoreError: LocalizedError, Sendable {
    case unsafeStore(String)
    case reservationAlreadyExists(UUID)
    case reservationNotFound(UUID)
    case reservationMismatch(UUID)
    case unsupportedField(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsafeStore(let reason):
            "The Agent Analysis creation-reservation store is unsafe or unavailable: \(reason)"
        case .reservationAlreadyExists(let id):
            "Agent Analysis creation reservation \(id.uuidString) already exists with different evidence."
        case .reservationNotFound(let id):
            "Agent Analysis creation reservation \(id.uuidString) was not found."
        case .reservationMismatch(let id):
            "Agent Analysis creation reservation \(id.uuidString) does not match its request-owned evidence."
        case .unsupportedField(let field):
            "The Agent Analysis creation reservation contains unsupported field \(field)."
        case .unsupportedSchemaVersion(let version):
            "The Agent Analysis creation-reservation schema version \(version) is unsupported."
        }
    }
}

/// Private per-request reservation storage. It is intentionally independent
/// from Action Run execution journals and never participates in their listing,
/// system-Trash authority, compaction, archival, or recovery scans.
public actor AgentAnalysisCreationReservationStore {
    private static let maximumStoredByteCount = 2 * 1024 * 1024
    private static let storageDirectoryName = "agent-analysis-creations-v1"
    private static let coordinationLockName = "agent-analysis-creations-v1.lock"

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                Self.storageDirectoryName,
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumStoredByteCount
        )
        try storage.ensureDirectories([])
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: Self.coordinationLockName
            )
        } catch {
            throw AgentAnalysisCreationReservationStoreError.unsafeStore(
                error.localizedDescription
            )
        }
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [nil])
        }
    }

    @discardableResult
    public func create(
        _ reservation: AgentAnalysisCreationReservation
    ) throws -> AgentAnalysisCreationReservation {
        guard reservation.triptychID == triptychID else {
            throw AgentAnalysisCreationReservationStoreError
                .reservationMismatch(reservation.id)
        }
        return try lock.withExclusiveLock {
            let (canonical, data) = try Self.canonicalized(reservation)
            do {
                let readback = try storage.createExclusive(
                    data,
                    directory: nil,
                    fileName: Self.fileName(reservation.id)
                )
                let stored = try Self.decode(
                    AgentAnalysisCreationReservation.self,
                    from: readback
                )
                guard stored == canonical else {
                    throw AgentAnalysisCreationReservationStoreError
                        .reservationMismatch(reservation.id)
                }
                return stored
            } catch let error as SecureRecordDirectoryError {
                if case .alreadyExists = error {
                    let existing = try read(id: reservation.id)
                    if existing == canonical { return existing }
                    throw AgentAnalysisCreationReservationStoreError
                        .reservationAlreadyExists(reservation.id)
                }
                throw AgentAnalysisCreationReservationStoreError.unsafeStore(
                    error.localizedDescription
                )
            }
        }
    }

    public func reservation(id: UUID) throws -> AgentAnalysisCreationReservation {
        try lock.withSharedLock { try read(id: id) }
    }

    public func reservationIfPresent(
        id: UUID
    ) throws -> AgentAnalysisCreationReservation? {
        try lock.withSharedLock {
            do { return try read(id: id) }
            catch AgentAnalysisCreationReservationStoreError.reservationNotFound {
                return nil
            }
        }
    }

    @discardableResult
    public func revisePrecommit(
        expected: AgentAnalysisCreationReservation,
        replacement: AgentAnalysisCreationReservation
    ) throws -> AgentAnalysisCreationReservation {
        guard expected.triptychID == triptychID,
              replacement.triptychID == triptychID,
              expected.runID == replacement.runID,
              expected.target == replacement.target,
              expected.reservedIdentityID == replacement.reservedIdentityID,
              expected.requestedBinding == replacement.requestedBinding,
              expected.sourceRoute == replacement.sourceRoute,
              expected.initialMetadata == replacement.initialMetadata,
              expected.academicPurpose == replacement.academicPurpose,
              expected.committedSourceFingerprint == nil,
              replacement.committedSourceFingerprint == nil,
              expected.bindingState == replacement.bindingState,
              expected.bindingState == nil || expected.bindingState == .reserved else {
            throw AgentAnalysisCreationReservationStoreError
                .reservationMismatch(expected.runID)
        }
        return try replace(expected: expected, replacement: replacement)
    }

    @discardableResult
    public func confirmSource(
        runID: UUID,
        fingerprint: DocumentFingerprint
    ) throws -> AgentAnalysisCreationReservation {
        try lock.withExclusiveLock {
            var reservation = try read(id: runID)
            if let committed = reservation.committedSourceFingerprint {
                guard committed == fingerprint else {
                    throw AgentAnalysisCreationReservationStoreError
                        .reservationMismatch(runID)
                }
                return reservation
            }
            reservation.committedSourceFingerprint = fingerprint
            return try writeReplacement(reservation)
        }
    }

    @discardableResult
    public func advanceBinding(
        runID: UUID,
        to state: AgentAnalysisCreationBindingState
    ) throws -> AgentAnalysisCreationReservation {
        try lock.withExclusiveLock {
            var reservation = try read(id: runID)
            guard reservation.requestedBinding != nil,
                  reservation.sourceRoute == nil,
                  reservation.committedSourceFingerprint != nil,
                  let currentState = reservation.bindingState else {
                throw AgentAnalysisCreationReservationStoreError
                    .reservationMismatch(runID)
            }
            let allowed = switch (currentState, state) {
            case (.reserved, .reserved), (.reserved, .writing),
                 (.writing, .writing), (.writing, .retryable),
                 (.writing, .committed),
                 (.retryable, .retryable), (.retryable, .writing),
                 (.committed, .committed):
                true
            default:
                false
            }
            guard allowed else {
                throw AgentAnalysisCreationReservationStoreError
                    .reservationMismatch(runID)
            }
            if currentState == state { return reservation }
            reservation.bindingState = state
            return try writeReplacement(reservation)
        }
    }

    private func replace(
        expected: AgentAnalysisCreationReservation,
        replacement: AgentAnalysisCreationReservation
    ) throws -> AgentAnalysisCreationReservation {
        try lock.withExclusiveLock {
            let current = try read(id: expected.runID)
            guard current == expected else {
                throw AgentAnalysisCreationReservationStoreError
                    .reservationMismatch(expected.runID)
            }
            return try writeReplacement(replacement)
        }
    }

    private func writeReplacement(
        _ reservation: AgentAnalysisCreationReservation
    ) throws -> AgentAnalysisCreationReservation {
        let (canonical, data) = try Self.canonicalized(reservation)
        let readback = try storage.replace(
            data,
            directory: nil,
            fileName: Self.fileName(reservation.runID)
        )
        let stored = try Self.decode(
            AgentAnalysisCreationReservation.self,
            from: readback
        )
        guard stored == canonical else {
            throw AgentAnalysisCreationReservationStoreError
                .reservationMismatch(reservation.runID)
        }
        return stored
    }

    private func read(id: UUID) throws -> AgentAnalysisCreationReservation {
        do {
            let data = try storage.read(directory: nil, fileName: Self.fileName(id))
            let reservation = try Self.decode(
                AgentAnalysisCreationReservation.self,
                from: data
            )
            guard reservation.id == id, reservation.triptychID == triptychID else {
                throw AgentAnalysisCreationReservationStoreError.reservationMismatch(id)
            }
            return reservation
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw AgentAnalysisCreationReservationStoreError.reservationNotFound(id)
            }
            throw AgentAnalysisCreationReservationStoreError.unsafeStore(
                error.localizedDescription
            )
        }
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    private static func canonicalized<T: Codable>(_ value: T) throws -> (T, Data) {
        let first = try makeEncoder().encode(value)
        let canonical = try makeDecoder().decode(T.self, from: first)
        return (canonical, try makeEncoder().encode(canonical))
    }
}
