import Darwin
import Foundation
import ScholiumContracts

struct AgentSessionCredentialStore {
    private struct StoredCredential: Codable {
        static let currentSchemaVersion = 3
        let schemaVersion: Int
        let run: ResearchRunLocator
        let sessionID: UUID
        let secret: String
        let expiresAt: Date

        init(run: ResearchRunLocator, credential: ResearchConnectionCredential) {
            schemaVersion = Self.currentSchemaVersion
            self.run = run
            sessionID = credential.sessionID
            secret = credential.secret
            expiresAt = credential.expiresAt
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema_version"
            case run
            case sessionID = "session_id"
            case secret
            case expiresAt = "expires_at"
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyCodingKey.self)
            let allowed = Set(CodingKeys.allCases.map(\.stringValue))
            guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
                throw AgentSessionCredentialStoreError.missingOrUnsafe
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw AgentSessionCredentialStoreError.missingOrUnsafe
            }
            self.schemaVersion = schemaVersion
            run = try container.decode(ResearchRunLocator.self, forKey: .run)
            sessionID = try container.decode(UUID.self, forKey: .sessionID)
            secret = try container.decode(String.self, forKey: .secret)
            expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        }

        func validatedCredential() throws -> ResearchConnectionCredential {
            do {
                return try ResearchConnectionCredential(
                    sessionID: sessionID,
                    secret: secret,
                    expiresAt: expiresAt
                )
            } catch {
                throw AgentSessionCredentialStoreError.missingOrUnsafe
            }
        }
    }

    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Establishes the protected parent and Session directory before a remote
    /// operation can create or consume a bearer Session.
    func prepare(now: Date = Date()) throws {
        try prepareDirectory()
        try pruneExpiredCredentials(now: now)
    }

    func save(
        _ credential: ResearchConnectionCredential,
        for run: ResearchRunLocator,
        now: Date = Date()
    ) throws {
        try prepare(now: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(StoredCredential(
            run: run,
            credential: credential
        ))
        let destination = url(for: run)
        let temporary = directoryURL.appendingPathComponent(
            ".credential-\(UUID().uuidString.lowercased())",
            isDirectory: false
        )
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw AgentSessionCredentialStoreError.unsafeState }
        var descriptorIsOpen = true
        do {
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        buffer.count - offset
                    )
                    guard count > 0 else {
                        throw AgentSessionCredentialStoreError.unsafeState
                    }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else {
                throw AgentSessionCredentialStoreError.unsafeState
            }
            Darwin.close(descriptor)
            descriptorIsOpen = false
            if rename(temporary.path, destination.path) != 0 {
                throw AgentSessionCredentialStoreError.unsafeState
            }
        } catch {
            if descriptorIsOpen { Darwin.close(descriptor) }
            unlink(temporary.path)
            throw error
        }
    }

    func load(
        for run: ResearchRunLocator,
        now: Date = Date()
    ) throws -> ResearchConnectionCredential {
        try prepare(now: now)
        let fileURL = url(for: run)
        var info = stat()
        guard lstat(fileURL.path, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o177) == 0,
              info.st_size <= 4_096 else {
            throw AgentSessionCredentialStoreError.missingOrUnsafe
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let stored = try JSONDecoder().decode(StoredCredential.self, from: data)
        guard stored.schemaVersion == StoredCredential.currentSchemaVersion,
              stored.run == run else {
            throw AgentSessionCredentialStoreError.missingOrUnsafe
        }
        return try stored.validatedCredential()
    }

    func remove(for run: ResearchRunLocator) throws {
        try prepareDirectory()
        let fileURL = url(for: run)
        var info = stat()
        guard lstat(fileURL.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw AgentSessionCredentialStoreError.unsafeState
        }
        guard info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o177) == 0 else {
            throw AgentSessionCredentialStoreError.missingOrUnsafe
        }
        guard unlink(fileURL.path) == 0 else {
            throw AgentSessionCredentialStoreError.unsafeState
        }
    }

    private func prepareDirectory() throws {
        let parentURL = directoryURL.deletingLastPathComponent()
        // An explicit isolated Home is allowed to be fresh on first use. The
        // private root is the only additional ancestor the store owns; create
        // it before ApplicationSupport so every store-owned directory still
        // receives the same strict ownership and mode checks.
        let privateRootURL = parentURL.deletingLastPathComponent()
        var privateRootInfo = stat()
        if lstat(privateRootURL.path, &privateRootInfo) != 0 {
            guard errno == ENOENT else {
                throw AgentSessionCredentialStoreError.unsafeState
            }
            try ensureSecureDirectory(at: privateRootURL)
        }
        try ensureSecureDirectory(at: parentURL)
        try ensureSecureDirectory(at: directoryURL)
    }

    private func ensureSecureDirectory(at url: URL) throws {
        if mkdir(url.path, 0o700) != 0, errno != EEXIST {
            throw AgentSessionCredentialStoreError.unsafeState
        }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_mode & 0o077) == 0 else {
            throw AgentSessionCredentialStoreError.unsafeState
        }
    }

    /// Removes only a current-schema credential whose Run filename and
    /// Application-issued expiry are exact. Unknown, malformed, symlinked, or
    /// otherwise unsafe entries remain untouched and nonauthorizing.
    private func pruneExpiredCredentials(now: Date) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for entry in entries where entry.pathExtension == "json" {
            guard let stored = try? storedCredential(at: entry),
                  entry.lastPathComponent == stored.run.rawValue + ".json",
                  stored.expiresAt <= now else { continue }
            try remove(for: stored.run)
        }
    }

    private func storedCredential(at fileURL: URL) throws -> StoredCredential {
        var info = stat()
        guard lstat(fileURL.path, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o177) == 0,
              info.st_size <= 4_096 else {
            throw AgentSessionCredentialStoreError.missingOrUnsafe
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return try JSONDecoder().decode(StoredCredential.self, from: data)
    }

    private func url(for run: ResearchRunLocator) -> URL {
        directoryURL.appendingPathComponent(run.rawValue + ".json", isDirectory: false)
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

enum AgentSessionCredentialStoreError: LocalizedError,
    AgentCommandErrorCodeProviding
{
    case unsafeState
    case missingOrUnsafe

    var errorDescription: String? {
        switch self {
        case .unsafeState:
            "The protected local Session store is unavailable or unsafe."
        case .missingOrUnsafe:
            "No valid local Connection Session exists for this Run; copy a new handoff and pair the same Run."
        }
    }

    var agentCommandErrorCode: String {
        switch self {
        case .unsafeState: "session_store_unavailable"
        case .missingOrUnsafe: "session_expired"
        }
    }

    var agentCommandRecovery: AgentOperationRecovery? {
        switch self {
        case .unsafeState:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .stopAndReport
            )
        case .missingOrUnsafe:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .copyNewHandoffAndPairSameRun
            )
        }
    }
}
