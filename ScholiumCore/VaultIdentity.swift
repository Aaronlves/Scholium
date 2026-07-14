import Foundation

public struct VaultIdentity: Codable, Hashable, Sendable {
    public let id: UUID
    public let canonicalPath: String
    public let bookmarkData: Data?

    public init(id: UUID, canonicalPath: String, bookmarkData: Data?) {
        self.id = id
        self.canonicalPath = canonicalPath
        self.bookmarkData = bookmarkData
    }
}

public enum VaultIdentityRegistryError: LocalizedError, Sendable {
    case corruptRegistry(String)

    public var errorDescription: String? {
        switch self {
        case .corruptRegistry(let reason):
            "Scholium could not safely load the vault-access registry. The existing file was left unchanged. \(reason)"
        }
    }
}

public actor VaultIdentityRegistry {
    private struct Registry: Codable {
        var vaults: [String: VaultIdentity]
    }

    private let registryURL: URL

    public init(applicationSupportURL: URL) {
        self.registryURL = applicationSupportURL.appendingPathComponent("vault-registry.json")
    }

    public func identity(for vaultURL: URL) throws -> VaultIdentity {
        let bookmark = try? vaultURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return try identity(for: vaultURL, bookmarkData: bookmark)
    }

    /// Records a newly granted bookmark while preserving the stable vault ID.
    /// This also repairs an earlier registration whose bookmark became stale
    /// or was created by a differently sandboxed development build.
    func identity(for vaultURL: URL, bookmarkData: Data?) throws -> VaultIdentity {
        let canonical = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        var (registry, loadFailure) = load()
        if let loadFailure {
            throw VaultIdentityRegistryError.corruptRegistry(loadFailure)
        }
        if let existing = registry.vaults[canonical] {
            guard let bookmarkData, bookmarkData != existing.bookmarkData else { return existing }
            let refreshed = VaultIdentity(
                id: existing.id,
                canonicalPath: canonical,
                bookmarkData: bookmarkData
            )
            registry.vaults[canonical] = refreshed
            try save(registry)
            return refreshed
        }

        let identity = VaultIdentity(id: UUID(), canonicalPath: canonical, bookmarkData: bookmarkData)
        registry.vaults[canonical] = identity
        try save(registry)
        return identity
    }

    public func identity(id: UUID) -> VaultIdentity? {
        load().registry.vaults.values.first(where: { $0.id == id })
    }

    public func identity(forCanonicalPath path: String) -> VaultIdentity? {
        let canonical = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        return load().registry.vaults[canonical]
    }

    public func healthError() -> String? {
        load().failure.map {
            VaultIdentityRegistryError.corruptRegistry($0).localizedDescription
        }
    }

    private func load() -> (registry: Registry, failure: String?) {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return (Registry(vaults: [:]), nil)
        }
        do {
            let data = try Data(contentsOf: registryURL, options: [.mappedIfSafe])
            return (try JSONDecoder().decode(Registry.self, from: data), nil)
        } catch {
            return (Registry(vaults: [:]), error.localizedDescription)
        }
    }

    private func save(_ registry: Registry) throws {
        try FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }
}

/// Machine-local authorization for the folder containing Works and the
/// portable `.scholium` directory beside it. This is deliberately separate
/// from `VaultIdentityRegistry`: the container is an access boundary, not a
/// fourth research vault.
public struct PortableControlAccess: Codable, Hashable, Sendable {
    public let canonicalContainerPath: String
    public let bookmarkData: Data

    public init(canonicalContainerPath: String, bookmarkData: Data) {
        self.canonicalContainerPath = canonicalContainerPath
        self.bookmarkData = bookmarkData
    }
}

public enum PortableControlAccessRegistryError: LocalizedError, Sendable {
    case corruptRegistry(String)
    case invalidContainer(expected: String, selected: String)

    public var errorDescription: String? {
        switch self {
        case .corruptRegistry(let reason):
            "Scholium could not safely load the portable-folder access registry. The existing file was left unchanged. \(reason)"
        case .invalidContainer(let expected, let selected):
            "Choose the folder containing Works. Expected '\(expected)', but received '\(selected)'."
        }
    }
}

public actor PortableControlAccessRegistry {
    private struct Registry: Codable {
        var containers: [String: PortableControlAccess]
    }

    private let registryURL: URL

    public init(applicationSupportURL: URL) {
        registryURL = applicationSupportURL.appendingPathComponent("portable-control-access.json")
    }

    public func register(containerURL: URL, forWorksURL worksURL: URL) throws -> PortableControlAccess {
        let container = canonicalDirectory(containerURL)
        let expected = canonicalDirectory(worksURL.deletingLastPathComponent())
        guard container.path == expected.path else {
            throw PortableControlAccessRegistryError.invalidContainer(
                expected: expected.path,
                selected: container.path
            )
        }
        let bookmark = try container.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return try register(containerURL: container, bookmarkData: bookmark)
    }

    public func access(forWorksURL worksURL: URL) -> PortableControlAccess? {
        let path = canonicalDirectory(worksURL.deletingLastPathComponent()).path
        return load().registry.containers[path]
    }

    public func healthError() -> String? {
        load().failure.map {
            PortableControlAccessRegistryError.corruptRegistry($0).localizedDescription
        }
    }

    /// Test seam and migration helper that records an already-created
    /// security-scoped bookmark without changing the canonical access key.
    func register(containerURL: URL, bookmarkData: Data) throws -> PortableControlAccess {
        let canonical = canonicalDirectory(containerURL)
        var (registry, loadFailure) = load()
        if let loadFailure {
            throw PortableControlAccessRegistryError.corruptRegistry(loadFailure)
        }
        let access = PortableControlAccess(
            canonicalContainerPath: canonical.path,
            bookmarkData: bookmarkData
        )
        registry.containers[canonical.path] = access
        try save(registry)
        return access
    }

    private func canonicalDirectory(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func load() -> (registry: Registry, failure: String?) {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return (Registry(containers: [:]), nil)
        }
        do {
            let data = try Data(contentsOf: registryURL, options: [.mappedIfSafe])
            return (try JSONDecoder().decode(Registry.self, from: data), nil)
        } catch {
            return (Registry(containers: [:]), error.localizedDescription)
        }
    }

    private func save(_ registry: Registry) throws {
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }
}
