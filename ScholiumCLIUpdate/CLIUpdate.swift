import CryptoKit
import Darwin
import Foundation
import ScholiumContracts

public struct CLIReleaseIdentity: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let marketingVersion: String
    public let releaseLabel: String
    public let buildNumber: String
    public let packageMode: String?
    public let gitExactTag: String?

    public init(
        marketingVersion: String,
        releaseLabel: String,
        buildNumber: String,
        packageMode: String? = nil,
        gitExactTag: String? = nil
    ) {
        self.schemaVersion = 1
        self.marketingVersion = marketingVersion
        self.releaseLabel = releaseLabel
        self.buildNumber = buildNumber
        self.packageMode = packageMode
        self.gitExactTag = gitExactTag
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case marketingVersion = "marketing_version"
        case releaseLabel = "release_label"
        case buildNumber = "build_number"
        case packageMode = "package_mode"
        case gitExactTag = "git_exact_tag"
    }
}

public enum CLIUpdateMode: Sendable {
    case check
    case apply
}

public enum CLIUpdateState: String, Codable, Sendable {
    case upToDate = "up_to_date"
    case updateAvailable = "update_available"
    case updated
}

public struct CLIUpdateReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: CLIUpdateState
    public let current: CLIReleaseIdentity
    public let available: CLIReleaseIdentity
    public let executable: String
    public let message: String

    public init(
        state: CLIUpdateState,
        current: CLIReleaseIdentity,
        available: CLIReleaseIdentity,
        executable: String,
        message: String
    ) {
        self.schemaVersion = 1
        self.state = state
        self.current = current
        self.available = available
        self.executable = executable
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state, current, available, executable, message
    }
}

public enum CLIUpdateError: LocalizedError, Equatable, Sendable {
    case invalidInstallation(String)
    case invalidDownloadURL(String)
    case network(String)
    case invalidChecksum(String)
    case invalidArchive(String)
    case invalidProvenance(String)
    case incompatibleArchitecture(current: [String], available: [String])
    case unsupportedReleaseLabel(String)
    case concurrentUpdate
    case recoveryConflict(String)
    case replacement(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInstallation(let message):
            return "The installed Scholium CLI is not in a supported user-local layout: \(message)"
        case .invalidDownloadURL(let message):
            return "The official Scholium CLI update URL is invalid: \(message)"
        case .network(let message):
            return "The Scholium CLI update download failed: \(message)"
        case .invalidChecksum(let message):
            return "The downloaded Scholium CLI failed checksum verification: \(message)"
        case .invalidArchive(let message):
            return "The downloaded Scholium CLI archive is invalid: \(message)"
        case .invalidProvenance(let message):
            return "The downloaded Scholium CLI has invalid release provenance: \(message)"
        case .incompatibleArchitecture(let current, let available):
            return "The downloaded Scholium CLI architecture does not match the installed CLI (installed: \(current.joined(separator: ", ")); available: \(available.joined(separator: ", ")))."
        case .unsupportedReleaseLabel(let label):
            return "The Scholium CLI release label cannot be compared safely: \(label)"
        case .concurrentUpdate:
            return "Another Scholium CLI update is already running."
        case .recoveryConflict(let message):
            return "An interrupted Scholium CLI update needs recovery: \(message)"
        case .replacement(let message):
            return "The Scholium CLI could not be replaced safely: \(message)"
        }
    }

    public var code: String {
        switch self {
        case .invalidInstallation: return "invalid_installation"
        case .invalidDownloadURL: return "invalid_update_url"
        case .network: return "update_download_failed"
        case .invalidChecksum: return "invalid_update_checksum"
        case .invalidArchive: return "invalid_update_archive"
        case .invalidProvenance: return "invalid_update_provenance"
        case .incompatibleArchitecture: return "incompatible_update_architecture"
        case .unsupportedReleaseLabel: return "unsupported_release_label"
        case .concurrentUpdate: return "concurrent_update"
        case .recoveryConflict: return "update_recovery_conflict"
        case .replacement: return "update_replacement_failed"
        }
    }
}

public struct CLIUpdateFetchedResource: Sendable {
    public let data: Data
    public let finalURL: URL

    public init(data: Data, finalURL: URL) {
        self.data = data
        self.finalURL = finalURL
    }
}

public struct CLIUpdateEngine: Sendable {
    public typealias ResourceFetcher = @Sendable (URL) async throws -> CLIUpdateFetchedResource
    public typealias ArchiveExtractor = @Sendable (URL, URL) throws -> Void
    public typealias ArchitectureInspector = @Sendable (URL) throws -> Set<String>
    public typealias SignatureVerifier = @Sendable (URL) throws -> Void

    private let fetchResource: ResourceFetcher
    private let extractArchive: ArchiveExtractor
    private let inspectArchitectures: ArchitectureInspector
    private let verifySignature: SignatureVerifier

    public init() {
        self.fetchResource = Self.fetchOfficialResource
        self.extractArchive = Self.extractOfficialArchive
        self.inspectArchitectures = Self.detectArchitectures
        self.verifySignature = Self.verifyCodeSignature
    }

    public init(
        fetchResource: @escaping ResourceFetcher,
        extractArchive: @escaping ArchiveExtractor,
        inspectArchitectures: @escaping ArchitectureInspector,
        verifySignature: @escaping SignatureVerifier
    ) {
        self.fetchResource = fetchResource
        self.extractArchive = extractArchive
        self.inspectArchitectures = inspectArchitectures
        self.verifySignature = verifySignature
    }

    public func run(
        currentExecutable: URL,
        currentIdentity: CLIReleaseIdentity,
        mode: CLIUpdateMode
    ) async throws -> CLIUpdateReport {
        let executable = currentExecutable.standardizedFileURL
        let root = executable.deletingLastPathComponent()
        try Self.withInstallationLock(at: root) {
            try Self.recoverInterruptedInstallation(at: root)
        }
        let current = try validateCurrentInstallation(
            executable: executable,
            root: root
        )

        let archiveURL = try Self.officialArchiveURL()
        let checksumURL = try Self.officialChecksumURL(for: archiveURL)
        let archive = try await fetchAndValidate(
            archiveURL,
            maximumBytes: Self.maximumArchiveBytes
        )
        let checksum = try await fetchAndValidate(
            checksumURL,
            maximumBytes: Self.maximumChecksumBytes
        )
        let expectedDigest = try Self.parseChecksum(
            checksum.data,
            archiveName: ScholiumCLIDistribution.archiveName
        )
        let actualDigest = Self.sha256Hex(archive.data)
        guard actualDigest == expectedDigest else {
            throw CLIUpdateError.invalidChecksum(
                "expected \(expectedDigest), received \(actualDigest)"
            )
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "scholium-cli-update-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: scratch,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: scratch) }

            let archiveFile = scratch.appendingPathComponent(
                ScholiumCLIDistribution.archiveName
            )
            try archive.data.write(to: archiveFile, options: .atomic)
            let expanded = scratch.appendingPathComponent("expanded", isDirectory: true)
            try FileManager.default.createDirectory(
                at: expanded,
                withIntermediateDirectories: true
            )
            do {
                try extractArchive(archiveFile, expanded)
            } catch {
                throw CLIUpdateError.invalidArchive(error.localizedDescription)
            }

            let candidate = try inspectCandidate(
                expanded: expanded,
                currentArchitectures: current.architectures
            )
            let comparison = try Self.compare(
                current: currentIdentity,
                available: candidate.identity
            )
            guard comparison == .orderedDescending else {
                return CLIUpdateReport(
                    state: .upToDate,
                    current: currentIdentity,
                    available: candidate.identity,
                    executable: executable.path,
                    message: "No newer Scholium CLI release is available."
                )
            }
            if case .check = mode {
                return CLIUpdateReport(
                    state: .updateAvailable,
                    current: currentIdentity,
                    available: candidate.identity,
                    executable: executable.path,
                    message: "A newer Scholium CLI release is available."
                )
            }

            try Self.withInstallationLock(at: root) {
                try Self.recoverInterruptedInstallation(at: root)
                let latest = try validateCurrentInstallation(
                    executable: executable,
                    root: root
                )
                guard latest.executableFingerprint == current.executableFingerprint,
                      latest.bundleFingerprint == current.bundleFingerprint else {
                    throw CLIUpdateError.concurrentUpdate
                }
                try Self.install(
                    candidate: candidate,
                    current: latest,
                    root: root
                )
            }
            return CLIUpdateReport(
                state: .updated,
                current: currentIdentity,
                available: candidate.identity,
                executable: executable.path,
                message: "Scholium CLI was updated successfully."
            )
        } catch let error as CLIUpdateError {
            throw error
        } catch {
            throw CLIUpdateError.invalidArchive(error.localizedDescription)
        }
    }

    public static func recoverInterruptedInstallation(at root: URL) throws {
        try validateDirectory(root)
        let fileManager = FileManager.default
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        var seen: Set<String> = []
        for transaction in children where transaction.lastPathComponent.hasPrefix(transactionPrefix) {
            guard seen.insert(transaction.path).inserted else { continue }
            let values = try transaction.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CLIUpdateError.recoveryConflict(
                    "transaction path is not a real directory: \(transaction.path)"
                )
            }
            try recover(transaction: transaction, root: root)
        }
    }

    private struct InstallationSnapshot: Sendable {
        let executable: URL
        let bundle: URL
        let executableFingerprint: String
        let bundleFingerprint: String
        let architectures: Set<String>
    }

    private struct Candidate: Sendable {
        let executable: URL
        let bundle: URL
        let identity: CLIReleaseIdentity
        let executableFingerprint: String
        let bundleFingerprint: String
    }

    private struct InstallationManifest: Codable {
        enum State: String, Codable {
            case prepared
            case committed
        }

        let schemaVersion: Int
        var state: State
        let executableName: String
        let bundleName: String
        let oldExecutableFingerprint: String
        let oldBundleFingerprint: String
        let newExecutableFingerprint: String
        let newBundleFingerprint: String

        init(
            state: State,
            oldExecutableFingerprint: String,
            oldBundleFingerprint: String,
            newExecutableFingerprint: String,
            newBundleFingerprint: String
        ) {
            self.schemaVersion = 1
            self.state = state
            self.executableName = CLIUpdateEngine.executableName
            self.bundleName = CLIUpdateEngine.bundleName
            self.oldExecutableFingerprint = oldExecutableFingerprint
            self.oldBundleFingerprint = oldBundleFingerprint
            self.newExecutableFingerprint = newExecutableFingerprint
            self.newBundleFingerprint = newBundleFingerprint
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case state
            case executableName = "executable_name"
            case bundleName = "bundle_name"
            case oldExecutableFingerprint = "old_executable_fingerprint"
            case oldBundleFingerprint = "old_bundle_fingerprint"
            case newExecutableFingerprint = "new_executable_fingerprint"
            case newBundleFingerprint = "new_bundle_fingerprint"
        }
    }

    private static let executableName = "scholium"
    private static let bundleName = "Scholium_ScholiumCore.bundle"
    private static let transactionPrefix = ".scholium-cli-update-"
    private static let maximumArchiveBytes = 256 * 1024 * 1024
    private static let maximumChecksumBytes = 64 * 1024

    private func fetchAndValidate(
        _ url: URL,
        maximumBytes: Int
    ) async throws -> CLIUpdateFetchedResource {
        let result: CLIUpdateFetchedResource
        do {
            result = try await fetchResource(url)
        } catch {
            throw CLIUpdateError.network(error.localizedDescription)
        }
        guard result.data.count <= maximumBytes else {
            throw CLIUpdateError.invalidArchive(
                "download exceeds the \(maximumBytes)-byte limit"
            )
        }
        guard Self.isAllowedDownloadURL(result.finalURL) else {
            throw CLIUpdateError.network(
                "redirected to an unapproved host: \(result.finalURL.host ?? "unknown")"
            )
        }
        return result
    }

    private func inspectCandidate(
        expanded: URL,
        currentArchitectures: Set<String>
    ) throws -> Candidate {
        let packageRoot = expanded.appendingPathComponent("Scholium-CLI", isDirectory: true)
        try Self.validateDirectory(packageRoot)
        let executable = packageRoot.appendingPathComponent(Self.executableName)
        let bundle = packageRoot.appendingPathComponent(Self.bundleName, isDirectory: true)
        try Self.validateRegularExecutable(executable)
        try Self.validateDirectory(bundle)
        try Self.validateTree(bundle)
        let identity = try Self.readReleaseIdentity(from: bundle)
        let availableArchitectures: Set<String>
        do {
            availableArchitectures = try inspectArchitectures(executable)
        } catch {
            throw CLIUpdateError.invalidArchive(
                "could not inspect the candidate executable architecture: \(error.localizedDescription)"
            )
        }
        guard availableArchitectures == currentArchitectures else {
            throw CLIUpdateError.incompatibleArchitecture(
                current: currentArchitectures.sorted(),
                available: availableArchitectures.sorted()
            )
        }
        do {
            try verifySignature(executable)
        } catch {
            throw CLIUpdateError.invalidArchive(
                "candidate code signature verification failed: \(error.localizedDescription)"
            )
        }
        return Candidate(
            executable: executable,
            bundle: bundle,
            identity: identity,
            executableFingerprint: try Self.fileFingerprint(executable),
            bundleFingerprint: try Self.directoryFingerprint(bundle)
        )
    }

    private static func install(
        candidate: Candidate,
        current: InstallationSnapshot,
        root: URL
    ) throws {
        let fileManager = FileManager.default
        let transaction = root.appendingPathComponent(
            transactionPrefix + UUID().uuidString.lowercased(),
            isDirectory: true
        )
        let backup = transaction.appendingPathComponent("backup", isDirectory: true)
        let incoming = transaction.appendingPathComponent("incoming", isDirectory: true)
        var preparedManifestWritten = false
        var committedManifestWritten = false
        do {
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: incoming, withIntermediateDirectories: true)
            try fileManager.copyItem(
                at: current.executable,
                to: backup.appendingPathComponent(executableName)
            )
            try fileManager.copyItem(
                at: current.bundle,
                to: backup.appendingPathComponent(bundleName, isDirectory: true)
            )
            try fileManager.copyItem(
                at: candidate.executable,
                to: incoming.appendingPathComponent(executableName)
            )
            try fileManager.copyItem(
                at: candidate.bundle,
                to: incoming.appendingPathComponent(bundleName, isDirectory: true)
            )

            var manifest = InstallationManifest(
                state: .prepared,
                oldExecutableFingerprint: current.executableFingerprint,
                oldBundleFingerprint: current.bundleFingerprint,
                newExecutableFingerprint: candidate.executableFingerprint,
                newBundleFingerprint: candidate.bundleFingerprint
            )
            try writeManifest(manifest, transaction: transaction)
            preparedManifestWritten = true

            try replace(
                at: root.appendingPathComponent(executableName),
                with: incoming.appendingPathComponent(executableName)
            )
            try replace(
                at: root.appendingPathComponent(bundleName, isDirectory: true),
                with: incoming.appendingPathComponent(bundleName, isDirectory: true)
            )

            let installed = try InstallationSnapshot(
                executable: root.appendingPathComponent(executableName),
                bundle: root.appendingPathComponent(bundleName, isDirectory: true),
                executableFingerprint: fileFingerprint(
                    root.appendingPathComponent(executableName)
                ),
                bundleFingerprint: directoryFingerprint(
                    root.appendingPathComponent(bundleName, isDirectory: true)
                ),
                architectures: current.architectures
            )
            guard installed.executableFingerprint == candidate.executableFingerprint,
                  installed.bundleFingerprint == candidate.bundleFingerprint else {
                throw CLIUpdateError.replacement(
                    "the installed executable or resource bundle did not match the verified candidate"
                )
            }
            manifest.state = .committed
            try writeManifest(manifest, transaction: transaction)
            committedManifestWritten = true
            try fileManager.removeItem(at: transaction)
        } catch let error as CLIUpdateError {
            if committedManifestWritten {
                throw CLIUpdateError.replacement(
                    "the update committed, but its recovery transaction could not be removed at (transaction.path): (error.localizedDescription)"
                )
            }
            if !preparedManifestWritten {
                try? fileManager.removeItem(at: transaction)
                throw error
            }
            do {
                try restore(transaction: transaction, root: root)
            } catch {
                throw CLIUpdateError.replacement(
                    "\(error.localizedDescription); recovery transaction retained at \(transaction.path)"
                )
            }
            throw error
        } catch {
            if committedManifestWritten {
                throw CLIUpdateError.replacement(
                    "the update committed, but its recovery transaction could not be removed at (transaction.path): (error.localizedDescription)"
                )
            }
            if !preparedManifestWritten {
                try? fileManager.removeItem(at: transaction)
                throw CLIUpdateError.replacement(error.localizedDescription)
            }
            do {
                try restore(transaction: transaction, root: root)
            } catch {
                throw CLIUpdateError.replacement(
                    "\(error.localizedDescription); recovery transaction retained at \(transaction.path)"
                )
            }
            throw CLIUpdateError.replacement(error.localizedDescription)
        }
    }

    private static func recover(transaction: URL, root: URL) throws {
        let manifest = try readManifest(transaction: transaction)
        let executable = root.appendingPathComponent(executableName)
        let bundle = root.appendingPathComponent(bundleName, isDirectory: true)
        let current = try currentFingerprints(executable: executable, bundle: bundle)
        let isOld = current.executable == manifest.oldExecutableFingerprint
            && current.bundle == manifest.oldBundleFingerprint
        let isNew = current.executable == manifest.newExecutableFingerprint
            && current.bundle == manifest.newBundleFingerprint

        switch (manifest.state, isOld, isNew) {
        case (.committed, _, true):
            try FileManager.default.removeItem(at: transaction)
        case (.prepared, _, true):
            var committed = manifest
            committed.state = .committed
            try writeManifest(committed, transaction: transaction)
            try FileManager.default.removeItem(at: transaction)
        case (_, true, _):
            try FileManager.default.removeItem(at: transaction)
        default:
            try restore(transaction: transaction, root: root)
        }
    }

    private static func restore(transaction: URL, root: URL) throws {
        let manifest = try readManifest(transaction: transaction)
        let backup = transaction.appendingPathComponent("backup", isDirectory: true)
        try validateDirectory(backup)
        try restoreItem(
            from: backup.appendingPathComponent(executableName),
            to: root.appendingPathComponent(executableName),
            transaction: transaction
        )
        try restoreItem(
            from: backup.appendingPathComponent(bundleName, isDirectory: true),
            to: root.appendingPathComponent(bundleName, isDirectory: true),
            transaction: transaction
        )
        let current = try currentFingerprints(
            executable: root.appendingPathComponent(executableName),
            bundle: root.appendingPathComponent(bundleName, isDirectory: true)
        )
        guard current.executable == manifest.oldExecutableFingerprint,
              current.bundle == manifest.oldBundleFingerprint else {
            throw CLIUpdateError.recoveryConflict(
                "the original CLI files could not be verified after recovery"
            )
        }
        try FileManager.default.removeItem(at: transaction)
    }

    private static func restoreItem(
        from source: URL,
        to destination: URL,
        transaction: URL
    ) throws {
        let temporary = transaction.appendingPathComponent(
            "restore-\(UUID().uuidString.lowercased())",
            isDirectory: source.hasDirectoryPath
        )
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temporary,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func replace(at destination: URL, with source: URL) throws {
        guard FileManager.default.fileExists(atPath: destination.path) else {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }
        _ = try FileManager.default.replaceItemAt(
            destination,
            withItemAt: source,
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )
    }

    private static func writeManifest(
        _ manifest: InstallationManifest,
        transaction: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(
            to: transaction.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private static func readManifest(
        transaction: URL
    ) throws -> InstallationManifest {
        let manifestURL = transaction.appendingPathComponent("manifest.json")
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(InstallationManifest.self, from: data)
            guard manifest.schemaVersion == 1,
                  manifest.executableName == executableName,
                  manifest.bundleName == bundleName else {
                throw CLIUpdateError.recoveryConflict(
                    "transaction manifest is not for the Scholium CLI layout"
                )
            }
            return manifest
        } catch let error as CLIUpdateError {
            throw error
        } catch {
            throw CLIUpdateError.recoveryConflict(
                "could not read transaction manifest at \(manifestURL.path): \(error.localizedDescription)"
            )
        }
    }

    private static func currentFingerprints(
        executable: URL,
        bundle: URL
    ) throws -> (executable: String, bundle: String) {
        let executableFingerprint = try fileFingerprintIfPresent(executable)
        let bundleFingerprint = try directoryFingerprintIfPresent(bundle)
        return (executableFingerprint ?? "missing", bundleFingerprint ?? "missing")
    }

    private func validateCurrentInstallation(
        executable: URL,
        root: URL
    ) throws -> InstallationSnapshot {
        try Self.validateDirectory(root)
        guard executable.lastPathComponent == Self.executableName else {
            throw CLIUpdateError.invalidInstallation(
                "the executable must be named \(Self.executableName)"
            )
        }
        try Self.validateRegularExecutable(executable)
        let bundle = root.appendingPathComponent(Self.bundleName, isDirectory: true)
        try Self.validateDirectory(bundle)
        try Self.validateTree(bundle)
        return InstallationSnapshot(
            executable: executable,
            bundle: bundle,
            executableFingerprint: try Self.fileFingerprint(executable),
            bundleFingerprint: try Self.directoryFingerprint(bundle),
            architectures: try inspectArchitectures(executable)
        )
    }

    private static func readReleaseIdentity(from bundle: URL) throws -> CLIReleaseIdentity {
        let provenance = bundle
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("ScholiumBuildProvenance.plist")
        let values: [String: Any]
        do {
            values = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: provenance),
                options: [],
                format: nil
            ) as? [String: Any] ?? [:]
        } catch {
            throw CLIUpdateError.invalidProvenance(
                "could not read \(provenance.path): \(error.localizedDescription)"
            )
        }
        guard values["schema"] as? String == "scholium-build-provenance-v1",
              let marketingVersion = values["marketing_version"] as? String,
              !marketingVersion.isEmpty,
              let releaseLabel = values["release_label"] as? String,
              !releaseLabel.isEmpty,
              let buildNumber = values["build_number"] as? String,
              !buildNumber.isEmpty,
              values["package_mode"] as? String == "release",
              values["source_clean"] as? Bool == true,
              let gitExactTag = values["git_exact_tag"] as? String,
              !gitExactTag.isEmpty,
              gitExactTag == releaseLabel else {
            throw CLIUpdateError.invalidProvenance(
                "the archive is not a clean, exactly tagged release"
            )
        }
        let identity = CLIReleaseIdentity(
            marketingVersion: marketingVersion,
            releaseLabel: releaseLabel,
            buildNumber: buildNumber,
            packageMode: "release",
            gitExactTag: gitExactTag
        )
        do {
            let release = try ParsedRelease(label: releaseLabel)
            let marketing = try ParsedRelease(label: marketingVersion)
            guard release.core == marketing.core else {
                throw CLIUpdateError.invalidProvenance(
                    "release label and marketing version identify different versions"
                )
            }
        } catch let error as CLIUpdateError {
            throw error
        } catch {
            throw CLIUpdateError.invalidProvenance(
                "release label is not a supported version: \(releaseLabel)"
            )
        }
        return identity
    }

    private static func compare(
        current: CLIReleaseIdentity,
        available: CLIReleaseIdentity
    ) throws -> ComparisonResult {
        guard available.packageMode == "release" else {
            throw CLIUpdateError.invalidProvenance(
                "the available archive is not a release package"
            )
        }
        if current.packageMode != "release" || current.releaseLabel == "development" {
            _ = try ParsedRelease(label: available.releaseLabel)
            return .orderedDescending
        }
        do {
            let installed = try ParsedRelease(label: current.releaseLabel)
            let candidate = try ParsedRelease(label: available.releaseLabel)
            return candidate.compare(to: installed)
        } catch {
            throw CLIUpdateError.unsupportedReleaseLabel(current.releaseLabel)
        }
    }

    private static func parseChecksum(
        _ data: Data,
        archiveName: String
    ) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIUpdateError.invalidChecksum("checksum file is not UTF-8")
        }
        let lines = text.split(whereSeparator: \.isNewline)
        let matching = lines.filter { $0.contains(archiveName) }
        let line: Substring?
        if matching.count == 1 {
            line = matching[0]
        } else if matching.isEmpty, lines.count == 1 {
            line = lines[0]
        } else {
            line = nil
        }
        guard let line,
              let token = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
              token.count == 64,
              token.allSatisfy({ $0.isHexDigit }) else {
            throw CLIUpdateError.invalidChecksum(
                "checksum file does not contain one SHA-256 for \(archiveName)"
            )
        }
        return token.lowercased()
    }

    private static func officialArchiveURL() throws -> URL {
        guard let url = URL(string: ScholiumCLIDistribution.downloadURL),
              isAllowedDownloadURL(url) else {
            throw CLIUpdateError.invalidDownloadURL(ScholiumCLIDistribution.downloadURL)
        }
        return url
    }

    private static func officialChecksumURL(for archiveURL: URL) throws -> URL {
        guard let url = URL(string: archiveURL.absoluteString + ".sha256"),
              isAllowedDownloadURL(url) else {
            throw CLIUpdateError.invalidDownloadURL(archiveURL.absoluteString + ".sha256")
        }
        return url
    }

    private static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return [
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com",
            "github-releases.githubusercontent.com",
        ].contains(host)
    }

    private static func fetchOfficialResource(
        _ url: URL
    ) async throws -> CLIUpdateFetchedResource {
        guard isAllowedDownloadURL(url) else {
            throw CLIUpdateError.invalidDownloadURL(url.absoluteString)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              let finalURL = response.url,
              isAllowedDownloadURL(finalURL) else {
            throw CLIUpdateError.network(
                "the official release endpoint returned an unexpected response"
            )
        }
        return CLIUpdateFetchedResource(data: data, finalURL: finalURL)
    }

    private static func extractOfficialArchive(
        _ archive: URL,
        _ destination: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIUpdateError.invalidArchive(
                error.isEmpty ? "ditto failed with status \(process.terminationStatus)" : error
            )
        }
    }

    private static func detectArchitectures(_ executable: URL) throws -> Set<String> {
        let data = try Data(contentsOf: executable)
        guard data.count >= 8 else {
            throw CLIUpdateError.invalidArchive("executable is too small to be Mach-O")
        }
        let bytes = [UInt8](data.prefix(4))
        switch bytes {
        case [0xcf, 0xfa, 0xed, 0xfe]:
            return try thinArchitectures(data, endian: .little, is64Bit: true)
        case [0xfe, 0xed, 0xfa, 0xcf]:
            return try thinArchitectures(data, endian: .big, is64Bit: true)
        case [0xce, 0xfa, 0xed, 0xfe]:
            return try thinArchitectures(data, endian: .little, is64Bit: false)
        case [0xfe, 0xed, 0xfa, 0xce]:
            return try thinArchitectures(data, endian: .big, is64Bit: false)
        case [0xca, 0xfe, 0xba, 0xbe]:
            return try fatArchitectures(data, endian: .big, is64Bit: false)
        case [0xbe, 0xba, 0xfe, 0xca]:
            return try fatArchitectures(data, endian: .little, is64Bit: false)
        case [0xca, 0xfe, 0xba, 0xbf]:
            return try fatArchitectures(data, endian: .big, is64Bit: true)
        case [0xbf, 0xba, 0xfe, 0xca]:
            return try fatArchitectures(data, endian: .little, is64Bit: true)
        default:
            throw CLIUpdateError.invalidArchive("executable is not a supported Mach-O file")
        }
    }

    private enum Endian {
        case little
        case big
    }

    private static func thinArchitectures(
        _ data: Data,
        endian: Endian,
        is64Bit: Bool
    ) throws -> Set<String> {
        guard let cpu = readUInt32(data, offset: 4, endian: endian) else {
            throw CLIUpdateError.invalidArchive("Mach-O header is truncated")
        }
        _ = is64Bit
        return [architectureName(cpuType: cpu)]
    }

    private static func fatArchitectures(
        _ data: Data,
        endian: Endian,
        is64Bit: Bool
    ) throws -> Set<String> {
        guard let count = readUInt32(data, offset: 4, endian: endian), count > 0, count <= 64 else {
            throw CLIUpdateError.invalidArchive("fat Mach-O header has an invalid architecture count")
        }
        let entrySize = is64Bit ? 32 : 20
        var result: Set<String> = []
        for index in 0 ..< Int(count) {
            let offset = 8 + index * entrySize
            guard let cpu = readUInt32(data, offset: offset, endian: endian) else {
                throw CLIUpdateError.invalidArchive("fat Mach-O header is truncated")
            }
            result.insert(architectureName(cpuType: cpu))
        }
        return result
    }

    private static func readUInt32(
        _ data: Data,
        offset: Int,
        endian: Endian
    ) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bytes = [UInt8](data[offset ..< offset + 4])
        switch endian {
        case .little:
            return UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
        case .big:
            return UInt32(bytes[3])
                | UInt32(bytes[2]) << 8
                | UInt32(bytes[1]) << 16
                | UInt32(bytes[0]) << 24
        }
    }

    private static func architectureName(cpuType: UInt32) -> String {
        switch cpuType {
        case 0x0100000c: return "arm64"
        case 0x01000007: return "x86_64"
        case 0x0000000c: return "arm"
        case 0x00000007: return "i386"
        default: return String(format: "cpu-%08x", cpuType)
        }
    }

    private static func verifyCodeSignature(_ executable: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", "--verbose=0", executable.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIUpdateError.invalidArchive(
                error.isEmpty ? "codesign failed with status \(process.terminationStatus)" : error
            )
        }
    }

    private static func validateRegularExecutable(_ url: URL) throws {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CLIUpdateError.invalidInstallation(
                "expected a regular executable at \(url.path)"
            )
        }
    }

    private static func validateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CLIUpdateError.invalidInstallation(
                "expected a real directory at \(url.path)"
            )
        }
    }

    private static func validateTree(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CLIUpdateError.invalidArchive("could not enumerate \(root.path)")
        }
        for case let item as URL in enumerator {
            let values = try item.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else {
                throw CLIUpdateError.invalidArchive(
                    "resource bundle contains an unsupported entry: \(item.path)"
                )
            }
        }
    }

    private static func fileFingerprintIfPresent(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try fileFingerprint(url)
    }

    private static func directoryFingerprintIfPresent(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try directoryFingerprint(url)
    }

    private static func fileFingerprint(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CLIUpdateError.invalidInstallation("not a regular file: \(url.path)")
        }
        return sha256Hex(try Data(contentsOf: url))
    }

    private static func directoryFingerprint(_ root: URL) throws -> String {
        try validateDirectory(root)
        try validateTree(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CLIUpdateError.invalidInstallation("could not enumerate \(root.path)")
        }
        var entries: [(relative: String, material: Data)] = []
        for case let item as URL in enumerator {
            let values = try item.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            let relative = item.path.hasPrefix(root.path + "/")
                ? String(item.path.dropFirst(root.path.count + 1))
                : item.lastPathComponent
            if values.isDirectory == true {
                entries.append((relative, Data("D\0\(relative)\n".utf8)))
            } else if values.isRegularFile == true {
                var material = Data("F\0\(relative)\0".utf8)
                material.append(contentsOf: try Data(contentsOf: item))
                material.append(0)
                entries.append((relative, material))
            }
        }
        let records = entries
            .sorted { $0.relative < $1.relative }
            .reduce(into: Data()) { result, entry in
                result.append(entry.material)
            }
        return sha256Hex(records)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func withInstallationLock<T>(
        at root: URL,
        _ body: () throws -> T
    ) throws -> T {
        try validateDirectory(root)
        let descriptor = root.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else {
            throw CLIUpdateError.invalidInstallation(
                "could not open the installation directory for locking"
            )
        }
        defer { _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw CLIUpdateError.concurrentUpdate
        }
        return try body()
    }
}

private struct ParsedRelease: Comparable, Sendable {
    struct Core: Comparable, Sendable, Equatable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: Core, rhs: Core) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    enum Identifier: Comparable, Sendable {
        case numeric(Int)
        case text(String)

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(left), .numeric(right)):
                return left < right
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case let (.text(left), .text(right)):
                return left < right
            }
        }
    }

    let core: Core
    let prerelease: [Identifier]

    init(label: String) throws {
        var value = label
        if value.hasPrefix("v") { value.removeFirst() }
        let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let coreText = pieces.first else {
            throw CLIUpdateError.unsupportedReleaseLabel(label)
        }
        let numbers = coreText.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Int(numbers[0]),
              let minor = Int(numbers[1]),
              let patch = Int(numbers[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            throw CLIUpdateError.unsupportedReleaseLabel(label)
        }
        self.core = Core(major: major, minor: minor, patch: patch)
        if pieces.count == 1 {
            self.prerelease = []
        } else {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else {
                throw CLIUpdateError.unsupportedReleaseLabel(label)
            }
            self.prerelease = try identifiers.map { identifier in
                guard !identifier.isEmpty else {
                    throw CLIUpdateError.unsupportedReleaseLabel(label)
                }
                if let numeric = Int(identifier), !identifier.hasPrefix("0") || identifier == "0" {
                    return .numeric(numeric)
                }
                guard identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                    throw CLIUpdateError.unsupportedReleaseLabel(label)
                }
                return .text(String(identifier))
            }
        }
    }

    func compare(to other: Self) -> ComparisonResult {
        if core < other.core { return .orderedAscending }
        if other.core < core { return .orderedDescending }
        if prerelease.isEmpty && other.prerelease.isEmpty { return .orderedSame }
        if prerelease.isEmpty { return .orderedDescending }
        if other.prerelease.isEmpty { return .orderedAscending }
        for (left, right) in zip(prerelease, other.prerelease) {
            if left < right { return .orderedAscending }
            if right < left { return .orderedDescending }
        }
        if prerelease.count < other.prerelease.count { return .orderedAscending }
        if other.prerelease.count < prerelease.count { return .orderedDescending }
        return .orderedSame
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.compare(to: rhs) == .orderedAscending
    }
}
