import Darwin
import Foundation
import ScholiumContracts

struct AgentSessionCredentialStore {
    private struct StoredCredential: Codable {
        static let currentSchemaVersion = 2
        let schemaVersion: Int
        let run: ResearchRunLocator
        let sessionID: UUID
        let secret: String

        init(run: ResearchRunLocator, credential: ResearchConnectionCredential) {
            schemaVersion = Self.currentSchemaVersion
            self.run = run
            sessionID = credential.sessionID
            secret = credential.secret
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema_version"
            case run
            case sessionID = "session_id"
            case secret
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
        }

        func validatedCredential() throws -> ResearchConnectionCredential {
            do {
                return try ResearchConnectionCredential(
                    sessionID: sessionID,
                    secret: secret
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

    func save(
        _ credential: ResearchConnectionCredential,
        for run: ResearchRunLocator
    ) throws {
        try prepareDirectory()
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

    func load(for run: ResearchRunLocator) throws -> ResearchConnectionCredential {
        try prepareDirectory()
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
        if mkdir(directoryURL.path, 0o700) != 0, errno != EEXIST {
            throw AgentSessionCredentialStoreError.unsafeState
        }
        var info = stat()
        guard lstat(directoryURL.path, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_mode & 0o077) == 0 else {
            throw AgentSessionCredentialStoreError.unsafeState
        }
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

enum AgentSessionCredentialStoreError: LocalizedError {
    case unsafeState
    case missingOrUnsafe

    var errorDescription: String? {
        switch self {
        case .unsafeState:
            "The protected local Session store is unavailable or unsafe."
        case .missingOrUnsafe:
            "No valid local Connection Session exists for this Run; pair again."
        }
    }
}
