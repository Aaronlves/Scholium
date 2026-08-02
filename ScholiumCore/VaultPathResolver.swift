import Foundation
import ScholiumContracts

/// Root-scoped path authority. Display spelling remains untouched; comparison
/// keys exist only for collision and lookup decisions on the root's volume.
struct VaultPathResolver: Sendable {
    let canonicalRoot: URL
    let caseSensitive: Bool
    let normalizationSensitive: Bool

    init(rootURL: URL) throws {
        canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try canonicalRoot.resourceValues(forKeys: [
            .isDirectoryKey,
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        guard values.isDirectory == true else {
            throw VaultRepositoryError.outsideVault(rootURL.path)
        }
        caseSensitive = values.volumeSupportsCaseSensitiveNames ?? true
        // Apple file systems compare canonically equivalent Unicode spellings.
        // Foundation exposes case behavior but no separate normalization key.
        normalizationSensitive = false
    }

    init(
        rootURL: URL,
        caseSensitive: Bool,
        normalizationSensitive: Bool
    ) {
        canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.caseSensitive = caseSensitive
        self.normalizationSensitive = normalizationSensitive
    }

    var comparisonPolicy: VaultPathComparisonPolicy {
        VaultPathComparisonPolicy(
            caseSensitive: caseSensitive,
            normalizationSensitive: normalizationSensitive
        )
    }

    func comparisonKey(for path: MarkdownRelativePath) -> VaultPathComparisonKey {
        comparisonPolicy.comparisonKey(for: path)
    }

    func comparisonKey(for path: VaultRelativeFolderPath) -> VaultPathComparisonKey {
        comparisonPolicy.comparisonKey(for: path)
    }

    func unresolvedURL(for path: MarkdownRelativePath) throws -> URL {
        let candidate = canonicalRoot
            .appendingPathComponent(path.rawValue, isDirectory: false)
            .standardizedFileURL
        guard contains(candidate) else {
            throw VaultRepositoryError.outsideVault(path.rawValue)
        }
        return candidate
    }

    func unresolvedURL(for path: VaultRelativeFolderPath) throws -> URL {
        let candidate = canonicalRoot
            .appendingPathComponent(path.rawValue, isDirectory: true)
            .standardizedFileURL
        guard contains(candidate) else {
            throw VaultRepositoryError.outsideVault(path.rawValue)
        }
        return candidate
    }

    func validateNoCollision(
        for requested: MarkdownRelativePath,
        fileManager: FileManager = .default
    ) throws {
        let requestedKey = comparisonKey(for: requested)
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  let relative = VaultPath.relativePath(for: url, in: canonicalRoot),
                  let existing = try? MarkdownRelativePath(relative),
                  comparisonKey(for: existing) == requestedKey else { continue }
            throw VaultRepositoryError.pathCollision(
                existing: existing.rawValue,
                requested: requested.rawValue
            )
        }
    }

    func validateNoCollision(
        for requested: VaultRelativeFolderPath,
        ignoring ignored: VaultRelativeFolderPath? = nil,
        fileManager: FileManager = .default
    ) throws {
        let requestedKey = comparisonKey(for: requested)
        let ignoredKey = ignored.map(comparisonKey(for:))
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory == true,
                  let relative = VaultPath.relativePath(for: url, in: canonicalRoot),
                  let existing = try? VaultRelativeFolderPath(relative) else { continue }
            let existingKey = comparisonKey(for: existing)
            guard existingKey == requestedKey, existingKey != ignoredKey else { continue }
            throw VaultRepositoryError.pathCollision(
                existing: existing.rawValue,
                requested: requested.rawValue
            )
        }
    }

    private func contains(_ candidate: URL) -> Bool {
        let rootPath = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }
}
