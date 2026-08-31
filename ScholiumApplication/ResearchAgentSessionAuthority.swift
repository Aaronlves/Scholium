import CryptoKit
import Darwin
import Foundation
import ScholiumContracts
import Security

protocol ResearchSecureRandomSource: Sendable {
    func bytes(count: Int) throws -> Data
}

struct AppleResearchSecureRandomSource: ResearchSecureRandomSource {
    func bytes(count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw ResearchAgentSessionError.secureRandomUnavailable(status)
        }
        return Data(bytes)
    }
}

struct ResearchAuthenticatedRun: Hashable, Sendable {
    let runID: UUID
    let triptychID: UUID
    let locator: ResearchRunLocator
    let sessionID: UUID
    let canWrite: Bool
}

/// Internal, non-Codable one-operation transaction lease. It never crosses
/// the bridge or enters a prompt; the session owner consumes it exactly once
/// before the Application starts the bound file transaction.
struct ResearchMutationLease: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: UUID
    let secret: String
    let run: ResearchRunLocator
    let sessionID: UUID
    let activityLedgerRevision: DocumentFingerprint
    let target: ResearchWriteTargetHandle
    let expectedRevision: DocumentFingerprint?
    let operationID: UUID
    let expiresAt: Date

    var description: String { "<redacted mutation lease>" }
    var debugDescription: String { description }
}

actor ResearchAgentSessionAuthority {
    private struct Pairing: Sendable {
        let runID: UUID
        let triptychID: UUID
        let locator: ResearchRunLocator
        let codeDigest: Data
        let canWrite: Bool
        let userID: uid_t
        let expiresAt: Date
        var attemptsRemaining: Int
    }

    private struct Session: Sendable {
        let id: UUID
        let secretDigest: Data
        let generationDigest: Data
        let userID: uid_t
        let expiresAt: Date
        var runLocators: Set<ResearchRunLocator>
    }

    private struct RunBinding: Sendable {
        let runID: UUID
        let triptychID: UUID
        let locator: ResearchRunLocator
        let canWrite: Bool
        /// Immediate Run whose authenticated authority attached this locator.
        /// Nil means the Run owns independent Session authority. Revocation
        /// walks these parent links so every derived descendant disappears
        /// when any ancestor is re-paired or revoked.
        let sessionParentRunID: UUID?
        var activeSessionID: UUID?
        var isFinalized: Bool
    }

    private struct StoredMutationLease: Sendable {
        let id: UUID
        let secretDigest: Data
        let run: ResearchRunLocator
        let sessionID: UUID
        let activityLedgerRevision: DocumentFingerprint
        let target: ResearchWriteTargetHandle
        let expectedRevision: DocumentFingerprint?
        let operationID: UUID
        let expiresAt: Date
    }

    private let random: any ResearchSecureRandomSource
    private let generationDigest: Data
    private var pairings: [ResearchRunLocator: Pairing] = [:]
    private var sessions: [UUID: Session] = [:]
    private var runs: [ResearchRunLocator: RunBinding] = [:]
    private var mutationLeases: [UUID: StoredMutationLease] = [:]

    init(random: any ResearchSecureRandomSource = AppleResearchSecureRandomSource()) throws {
        self.random = random
        generationDigest = Self.digest(try random.bytes(count: 32))
    }

    func issuePairing(
        runID: UUID,
        triptychID: UUID,
        canWrite: Bool,
        now: Date = Date(),
        validity: TimeInterval = 10 * 60,
        userID: uid_t = geteuid()
    ) throws -> ResearchAgentHandoff {
        let boundedValidity = min(max(validity, 30), 30 * 60)
        let locator = try uniqueLocator()
        let code = try pairingCode()
        let expiresAt = now.addingTimeInterval(boundedValidity)
        revokeAuthorizationLineage(rootRunID: runID)
        pairings = pairings.filter { $0.value.runID != runID }
        pairings[locator] = Pairing(
            runID: runID,
            triptychID: triptychID,
            locator: locator,
            codeDigest: Self.digest(Data(code.rawValue.utf8)),
            canWrite: canWrite,
            userID: userID,
            expiresAt: expiresAt,
            attemptsRemaining: 5
        )
        runs[locator] = RunBinding(
            runID: runID,
            triptychID: triptychID,
            locator: locator,
            canWrite: canWrite,
            sessionParentRunID: nil,
            activeSessionID: nil,
            isFinalized: false
        )
        return ResearchAgentHandoff(
            triptychID: triptychID,
            run: locator,
            pairingCode: code,
            expiresAt: expiresAt
        )
    }

    /// Issues a Session for a Run whose start was initiated through the
    /// authenticated local App process. This is deliberately separate from
    /// Pairing: a user-started Run does not require a GUI handoff code.
    func issueAgentSession(
        runID: UUID,
        triptychID: UUID,
        canWrite: Bool,
        now: Date = Date(),
        sessionValidity: TimeInterval = 8 * 60 * 60,
        userID: uid_t = geteuid()
    ) throws -> (run: ResearchRunLocator, credential: ResearchConnectionCredential) {
        let locator = try uniqueLocator()
        let secretData = try random.bytes(count: 32)
        let secret = Self.base64URL(secretData)
        let expiry = now.addingTimeInterval(
            min(max(sessionValidity, 60), 24 * 60 * 60)
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: secret,
            expiresAt: expiry
        )
        revokeAuthorizationLineage(rootRunID: runID)
        pairings = pairings.filter { $0.value.runID != runID }
        sessions[credential.sessionID] = Session(
            id: credential.sessionID,
            secretDigest: Self.digest(Data(secret.utf8)),
            generationDigest: generationDigest,
            userID: userID,
            expiresAt: expiry,
            runLocators: [locator]
        )
        runs[locator] = RunBinding(
            runID: runID,
            triptychID: triptychID,
            locator: locator,
            canWrite: canWrite,
            sessionParentRunID: nil,
            activeSessionID: credential.sessionID,
            isFinalized: false
        )
        return (locator, credential)
    }

    func exchange(
        run locator: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        now: Date = Date(),
        sessionValidity: TimeInterval = 8 * 60 * 60,
        userID: uid_t = geteuid()
    ) throws -> ResearchConnectionCredential {
        guard var pairing = pairings[locator] else {
            throw ResearchAgentSessionError.pairingRejected
        }
        guard pairing.expiresAt > now, pairing.attemptsRemaining > 0 else {
            pairings[locator] = nil
            throw ResearchAgentSessionError.pairingRejected
        }
        guard pairing.userID == userID else {
            throw ResearchAgentSessionError.pairingRejected
        }
        guard Self.constantTimeEqual(
            pairing.codeDigest,
            Self.digest(Data(pairingCode.rawValue.utf8))
        ) else {
            pairing.attemptsRemaining -= 1
            pairings[locator] = pairing.attemptsRemaining > 0 ? pairing : nil
            throw ResearchAgentSessionError.pairingRejected
        }

        let secretData = try random.bytes(count: 32)
        let secret = Self.base64URL(secretData)
        let expiry = now.addingTimeInterval(
            min(max(sessionValidity, 60), 24 * 60 * 60)
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: secret,
            expiresAt: expiry
        )
        var binding = try requiredRun(locator)
        if let previousID = binding.activeSessionID {
            remove(locator: locator, fromSession: previousID)
        }
        sessions[credential.sessionID] = Session(
            id: credential.sessionID,
            secretDigest: Self.digest(Data(secret.utf8)),
            generationDigest: generationDigest,
            userID: userID,
            expiresAt: expiry,
            runLocators: [locator]
        )
        binding.activeSessionID = credential.sessionID
        runs[locator] = binding
        pairings[locator] = nil
        return credential
    }

    func authenticate(
        _ credential: ResearchConnectionCredential,
        run locator: ResearchRunLocator,
        requiresWrite: Bool,
        allowFinalized: Bool = false,
        now: Date = Date(),
        userID: uid_t = geteuid()
    ) throws -> ResearchAuthenticatedRun {
        guard let binding = runs[locator],
              let session = sessions[credential.sessionID],
              session.userID == userID,
              session.expiresAt > now,
              credential.expiresAt == session.expiresAt,
              Self.constantTimeEqual(session.generationDigest, generationDigest),
              Self.constantTimeEqual(
                session.secretDigest,
                Self.digest(Data(credential.secret.utf8))
              ),
              session.runLocators.contains(locator),
              binding.activeSessionID == credential.sessionID,
              allowFinalized || !binding.isFinalized,
              !requiresWrite || binding.canWrite else {
            if sessions[credential.sessionID]?.expiresAt ?? .distantPast <= now {
                revokeSession(credential.sessionID)
            }
            throw ResearchAgentSessionError.sessionRejected
        }
        return ResearchAuthenticatedRun(
            runID: binding.runID,
            triptychID: binding.triptychID,
            locator: locator,
            sessionID: session.id,
            canWrite: binding.canWrite
        )
    }

    func attachRun(
        runID: UUID,
        triptychID: UUID,
        canWrite: Bool,
        to credential: ResearchConnectionCredential,
        sessionParentRunID: UUID? = nil,
        now: Date = Date(),
        userID: uid_t = geteuid()
    ) throws -> ResearchRunLocator {
        guard let session = sessions[credential.sessionID],
              session.userID == userID,
              session.expiresAt > now,
              credential.expiresAt == session.expiresAt,
              Self.constantTimeEqual(
                session.secretDigest,
                Self.digest(Data(credential.secret.utf8))
              ) else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let locator = try uniqueLocator()
        runs[locator] = RunBinding(
            runID: runID,
            triptychID: triptychID,
            locator: locator,
            canWrite: canWrite,
            sessionParentRunID: sessionParentRunID,
            activeSessionID: credential.sessionID,
            isFinalized: false
        )
        var updated = session
        updated.runLocators.insert(locator)
        sessions[credential.sessionID] = updated
        return locator
    }

    /// Atomically attaches one child only while the supplied parent locator
    /// remains an authenticated binding in the same Session. Ordinary derived
    /// work requires an unfinished parent; Continue Research explicitly allows
    /// its safely finalized parent while preserving the same revocation chain.
    func attachRun(
        runID: UUID,
        triptychID: UUID,
        canWrite: Bool,
        to credential: ResearchConnectionCredential,
        authorizedBy parent: ResearchRunLocator,
        allowFinalizedParent: Bool = false,
        now: Date = Date(),
        userID: uid_t = geteuid()
    ) throws -> ResearchRunLocator {
        let authenticatedParent = try authenticate(
            credential,
            run: parent,
            requiresWrite: false,
            allowFinalized: allowFinalizedParent,
            now: now,
            userID: userID
        )
        guard authenticatedParent.triptychID == triptychID,
              authenticatedParent.runID != runID else {
            throw ResearchAgentSessionError.sessionRejected
        }
        if let existing = sessions[credential.sessionID]?.runLocators
            .compactMap({ locator -> ResearchRunLocator? in
                guard let binding = runs[locator],
                      binding.runID == runID,
                      binding.triptychID == triptychID,
                      binding.sessionParentRunID == authenticatedParent.runID,
                      binding.activeSessionID == credential.sessionID,
                      !binding.isFinalized else {
                    return nil
                }
                return locator
            })
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first {
            return existing
        }
        return try attachRun(
            runID: runID,
            triptychID: triptychID,
            canWrite: canWrite,
            to: credential,
            sessionParentRunID: authenticatedParent.runID,
            now: now,
            userID: userID
        )
    }

    func attachedLocator(
        for runID: UUID,
        credential: ResearchConnectionCredential,
        now: Date = Date(),
        userID: uid_t = geteuid()
    ) throws -> ResearchRunLocator? {
        guard let session = sessions[credential.sessionID],
              session.userID == userID,
              session.expiresAt > now,
              credential.expiresAt == session.expiresAt,
              Self.constantTimeEqual(session.generationDigest, generationDigest),
              Self.constantTimeEqual(
                session.secretDigest,
                Self.digest(Data(credential.secret.utf8))
              ) else {
            throw ResearchAgentSessionError.sessionRejected
        }
        return session.runLocators.compactMap { locator in
            guard let binding = runs[locator],
                  binding.runID == runID,
                  binding.activeSessionID == credential.sessionID else {
                return nil
            }
            return locator
        }.sorted { $0.rawValue < $1.rawValue }.first
    }

    func issueMutationLease(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        activityLedgerRevision: DocumentFingerprint,
        target: ResearchWriteTargetHandle,
        expectedRevision: DocumentFingerprint?,
        operationID: UUID,
        now: Date = Date(),
        validity: TimeInterval = 60,
        userID: uid_t = geteuid()
    ) throws -> ResearchMutationLease {
        let authenticated = try authenticate(
            credential,
            run: run,
            requiresWrite: true,
            now: now,
            userID: userID
        )
        let secret = Self.base64URL(try random.bytes(count: 32))
        let lease = ResearchMutationLease(
            id: UUID(),
            secret: secret,
            run: run,
            sessionID: authenticated.sessionID,
            activityLedgerRevision: activityLedgerRevision,
            target: target,
            expectedRevision: expectedRevision,
            operationID: operationID,
            expiresAt: now.addingTimeInterval(min(max(validity, 5), 5 * 60))
        )
        mutationLeases[lease.id] = StoredMutationLease(
            id: lease.id,
            secretDigest: Self.digest(Data(secret.utf8)),
            run: run,
            sessionID: authenticated.sessionID,
            activityLedgerRevision: activityLedgerRevision,
            target: target,
            expectedRevision: expectedRevision,
            operationID: operationID,
            expiresAt: lease.expiresAt
        )
        return lease
    }

    func consumeMutationLease(
        _ lease: ResearchMutationLease,
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        activityLedgerRevision: DocumentFingerprint,
        target: ResearchWriteTargetHandle,
        expectedRevision: DocumentFingerprint?,
        operationID: UUID,
        now: Date = Date(),
        userID: uid_t = geteuid()
    ) throws {
        _ = try authenticate(
            credential,
            run: run,
            requiresWrite: true,
            now: now,
            userID: userID
        )
        guard let stored = mutationLeases.removeValue(forKey: lease.id),
              stored.expiresAt > now,
              lease.expiresAt == stored.expiresAt,
              lease.run == run,
              lease.sessionID == stored.sessionID,
              stored.run == run,
              stored.activityLedgerRevision == activityLedgerRevision,
              stored.target == target,
              stored.expectedRevision == expectedRevision,
              stored.operationID == operationID,
              lease.activityLedgerRevision == activityLedgerRevision,
              lease.target == target,
              lease.expectedRevision == expectedRevision,
              lease.operationID == operationID,
              Self.constantTimeEqual(
                  stored.secretDigest,
                  Self.digest(Data(lease.secret.utf8))
              ) else {
            throw ResearchAgentSessionError.sessionRejected
        }
    }

    func revokeRun(_ runID: UUID) {
        revokeAuthorizationLineage(rootRunID: runID)
    }

    private func revokeAuthorizationLineage(rootRunID: UUID) {
        var revokedRunIDs: Set<UUID> = [rootRunID]
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for binding in runs.values {
                guard let parentRunID = binding.sessionParentRunID,
                      revokedRunIDs.contains(parentRunID),
                      revokedRunIDs.insert(binding.runID).inserted else {
                    continue
                }
                addedDescendant = true
            }
        }
        let locators = runs.values.filter {
            revokedRunIDs.contains($0.runID)
        }.map(\.locator)
        for locator in locators {
            mutationLeases = mutationLeases.filter {
                $0.value.run != locator
            }
            if let sessionID = runs[locator]?.activeSessionID {
                remove(locator: locator, fromSession: sessionID)
            }
            runs[locator] = nil
            pairings[locator] = nil
        }
        pairings = pairings.filter { $0.value.runID != rootRunID }
    }

    /// Ends all capabilities for a completed Run while retaining only its
    /// short-lived Session binding for idempotent Result acknowledgement and
    /// an explicitly requested Continue Research handoff. Ordinary context
    /// and write authentication rejects finalized bindings.
    func finalizeRun(_ runID: UUID) {
        let locators = runs.values.filter { $0.runID == runID }.map(\.locator)
        for locator in locators {
            mutationLeases = mutationLeases.filter {
                $0.value.run != locator
            }
            pairings[locator] = nil
            guard var binding = runs[locator] else { continue }
            binding.isFinalized = true
            runs[locator] = binding
        }
    }

    func revokeSession(_ sessionID: UUID) {
        mutationLeases = mutationLeases.filter {
            $0.value.sessionID != sessionID
        }
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        for locator in session.runLocators where runs[locator]?.activeSessionID == sessionID {
            var binding = runs[locator]
            binding?.activeSessionID = nil
            runs[locator] = binding
        }
    }

    /// Authenticates the complete bearer value before revoking its exact
    /// Session. A delivery adapter must never be able to revoke by UUID alone.
    func revokeSession(
        authenticating credential: ResearchConnectionCredential,
        userID: uid_t = geteuid()
    ) throws {
        guard let session = sessions[credential.sessionID],
              session.userID == userID,
              credential.expiresAt == session.expiresAt,
              Self.constantTimeEqual(session.generationDigest, generationDigest),
              Self.constantTimeEqual(
                session.secretDigest,
                Self.digest(Data(credential.secret.utf8))
              ) else {
            throw ResearchAgentSessionError.sessionRejected
        }
        revokeSession(credential.sessionID)
    }

    private func remove(locator: ResearchRunLocator, fromSession sessionID: UUID) {
        guard var session = sessions[sessionID] else { return }
        session.runLocators.remove(locator)
        if session.runLocators.isEmpty {
            sessions[sessionID] = nil
        } else {
            sessions[sessionID] = session
        }
    }

    private func requiredRun(_ locator: ResearchRunLocator) throws -> RunBinding {
        guard let binding = runs[locator] else {
            throw ResearchAgentSessionError.pairingRejected
        }
        return binding
    }

    private func uniqueLocator() throws -> ResearchRunLocator {
        for _ in 0..<8 {
            let raw = Self.base64URL(try random.bytes(count: 18))
            if let locator = ResearchRunLocator(rawValue: raw), runs[locator] == nil {
                return locator
            }
        }
        throw ResearchAgentSessionError.secureRandomCollision
    }

    private func pairingCode() throws -> ResearchPairingCode {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        let bytes = try random.bytes(count: 24)
        let compact = bytes.map { String(alphabet[Int($0) % alphabet.count]) }.joined()
        guard let code = ResearchPairingCode(rawValue: compact) else {
            throw ResearchAgentSessionError.secureRandomCollision
        }
        return code
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum ResearchAgentSessionError: LocalizedError, Equatable, Sendable {
    case secureRandomUnavailable(OSStatus)
    case secureRandomCollision
    case pairingRejected
    case sessionRejected

    var errorDescription: String? {
        switch self {
        case .secureRandomUnavailable:
            "The cryptographic random source is unavailable; no credential was issued."
        case .secureRandomCollision:
            "Scholium could not issue a unique local credential."
        case .pairingRejected:
            "The pairing request was rejected."
        case .sessionRejected:
            "The Connection Session is invalid, expired, revoked, or outside this Run."
        }
    }
}
