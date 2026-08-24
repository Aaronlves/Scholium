import Foundation
import CryptoKit
import Darwin
@testable import ScholiumCLIUpdate
import ScholiumContracts
import Testing

@Suite("Scholium CLI update")
struct CLIUpdateTests {
    @Test("A newer verified release replaces the executable and resource bundle")
    func appliesVerifiedRelease() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }

        let available = releaseIdentity(label: "v0.1.0-beta.10")
        let archive = Data("verified-archive".utf8)
        let engine = makeEngine(
            archive: archive,
            available: available
        )

        let report = try await engine.run(
            currentExecutable: fixture.executable,
            currentIdentity: fixture.identity,
            mode: .apply
        )

        #expect(report.state == .updated)
        #expect(report.current.releaseLabel == "v0.1.0-beta.1")
        #expect(report.available.releaseLabel == "v0.1.0-beta.10")
        #expect(try Data(contentsOf: fixture.executable) == Data("new-cli".utf8))
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.10")
        #expect(try transactionDirectories(in: fixture.root).isEmpty)
    }

    @Test("Check mode reports an update without changing the installed CLI")
    func checkDoesNotWrite() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }

        let oldExecutable = try Data(contentsOf: fixture.executable)
        let oldBundleLabel = try readReleaseLabel(from: fixture.bundle)
        let available = releaseIdentity(label: "v0.1.0-beta.2")
        let engine = makeEngine(
            archive: Data("check-archive".utf8),
            available: available
        )

        let report = try await engine.run(
            currentExecutable: fixture.executable,
            currentIdentity: fixture.identity,
            mode: .check
        )

        #expect(report.state == .updateAvailable)
        #expect(try Data(contentsOf: fixture.executable) == oldExecutable)
        #expect(try readReleaseLabel(from: fixture.bundle) == oldBundleLabel)
    }

    @Test("A checksum failure leaves the installed CLI unchanged")
    func checksumFailurePreservesInstallation() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }

        let oldExecutable = try Data(contentsOf: fixture.executable)
        let archive = Data("tampered-archive".utf8)
        let engine = makeEngine(
            archive: archive,
            available: releaseIdentity(label: "v0.1.0-beta.2"),
            checksumOverride: String(repeating: "0", count: 64)
        )

        do {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .apply
            )
            Issue.record("A checksum failure unexpectedly succeeded.")
        } catch let error as CLIUpdateError {
            guard case .invalidChecksum = error else {
                Issue.record("Unexpected update error: \(error.localizedDescription)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.executable) == oldExecutable)
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
    }

    @Test("Invalid release provenance leaves the installed CLI unchanged")
    func provenanceFailurePreservesInstallation() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }

        let oldExecutable = try Data(contentsOf: fixture.executable)
        let archive = Data("provenance-archive".utf8)
        let invalidIdentity = CLIReleaseIdentity(
            marketingVersion: "0.1.0",
            releaseLabel: "v0.1.0-beta.2",
            buildNumber: "1",
            packageMode: "development",
            gitExactTag: "v0.1.0-beta.2"
        )
        let engine = makeEngine(archive: archive, available: invalidIdentity)

        do {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .apply
            )
            Issue.record("Invalid release provenance unexpectedly succeeded.")
        } catch let error as CLIUpdateError {
            guard case .invalidProvenance = error else {
                Issue.record("Unexpected update error: \(error.localizedDescription)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.executable) == oldExecutable)
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
    }

    @Test("An incompatible architecture is rejected before replacement")
    func architectureMismatchPreservesInstallation() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }

        let oldExecutable = try Data(contentsOf: fixture.executable)
        let archive = Data("architecture-archive".utf8)
        let engine = makeEngine(
            archive: archive,
            available: releaseIdentity(label: "v0.1.0-beta.2"),
            candidateArchitectures: ["x86_64"]
        )

        do {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .apply
            )
            Issue.record("An incompatible architecture unexpectedly succeeded.")
        } catch let error as CLIUpdateError {
            guard case .incompatibleArchitecture = error else {
                Issue.record("Unexpected update error: \(error.localizedDescription)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.executable) == oldExecutable)
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
    }

    @Test("Recovery discards unpromoted staging without touching the installation")
    func unpromotedStagingIsNonAuthorizing() throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }
        let originalExecutable = try Data(contentsOf: fixture.executable)
        let staging = fixture.root.appendingPathComponent(
            ".scholium-cli-update-staging-fixture",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("incoming", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("incomplete".utf8).write(
            to: staging.appendingPathComponent("incoming/scholium")
        )

        try CLIUpdateEngine.recoverInterruptedInstallation(at: fixture.root)

        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(try Data(contentsOf: fixture.executable) == originalExecutable)
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
    }

    @Test("A promoted prepared transaction restores an interrupted pair replacement")
    func promotedTransactionRestoresPartialReplacement() throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }
        let transaction = fixture.root.appendingPathComponent(
            ".scholium-cli-update-transaction-fixture",
            isDirectory: true
        )
        let backup = transaction.appendingPathComponent("backup", isDirectory: true)
        let incoming = transaction.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture.executable,
            to: backup.appendingPathComponent("scholium")
        )
        try FileManager.default.copyItem(
            at: fixture.bundle,
            to: backup.appendingPathComponent(
                "Scholium_ScholiumCore.bundle",
                isDirectory: true
            )
        )
        let incomingExecutable = incoming.appendingPathComponent("scholium")
        try Data("new-cli".utf8).write(to: incomingExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: incomingExecutable.path
        )
        let incomingBundle = incoming.appendingPathComponent(
            "Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        try writeBundle(
            at: incomingBundle,
            identity: releaseIdentity(label: "v0.1.0-beta.2")
        )
        try writeTransactionManifest(
            at: transaction,
            oldExecutableFingerprint: try CLIUpdateEngine.fileFingerprint(
                fixture.executable
            ),
            oldBundleFingerprint: try CLIUpdateEngine.directoryFingerprint(
                fixture.bundle
            ),
            newExecutableFingerprint: try CLIUpdateEngine.fileFingerprint(
                incomingExecutable
            ),
            newBundleFingerprint: try CLIUpdateEngine.directoryFingerprint(
                incomingBundle
            )
        )

        try FileManager.default.removeItem(at: fixture.executable)
        try FileManager.default.copyItem(at: incomingExecutable, to: fixture.executable)

        try CLIUpdateEngine.recoverInterruptedInstallation(at: fixture.root)

        #expect(try Data(contentsOf: fixture.executable) == Data("old-cli".utf8))
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
        #expect(!FileManager.default.fileExists(atPath: transaction.path))
    }

    @Test("The package installer owns first install only and resumes exact partial state")
    func installerIsFirstInstallOnly() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }

        let first = try fixture.run(prefix: fixture.root.appendingPathComponent("clean"))
        #expect(first.status == 0)
        let installedExecutable = fixture.root.appendingPathComponent("clean/bin/scholium")
        let installedBundle = fixture.root.appendingPathComponent(
            "clean/bin/Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        let installedExecutableData = try Data(contentsOf: installedExecutable)
        let installedResourceData = try Data(
            contentsOf: installedBundle.appendingPathComponent("payload")
        )

        let repeated = try fixture.run(prefix: fixture.root.appendingPathComponent("clean"))
        #expect(repeated.status != 0)
        #expect(repeated.stderr.contains("scholium update"))
        #expect(try Data(contentsOf: installedExecutable) == installedExecutableData)
        #expect(
            try Data(contentsOf: installedBundle.appendingPathComponent("payload"))
                == installedResourceData
        )

        let bundlePartial = fixture.root.appendingPathComponent("bundle-partial/bin")
        try FileManager.default.createDirectory(at: bundlePartial, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture.sourceBundle,
            to: bundlePartial.appendingPathComponent(
                "Scholium_ScholiumCore.bundle",
                isDirectory: true
            )
        )
        #expect(try fixture.run(prefix: fixture.root.appendingPathComponent("bundle-partial")).status == 0)
        #expect(FileManager.default.isExecutableFile(
            atPath: bundlePartial.appendingPathComponent("scholium").path
        ))

        let executablePartial = fixture.root.appendingPathComponent("executable-partial/bin")
        try FileManager.default.createDirectory(at: executablePartial, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture.sourceExecutable,
            to: executablePartial.appendingPathComponent("scholium")
        )
        #expect(try fixture.run(prefix: fixture.root.appendingPathComponent("executable-partial")).status == 0)
        #expect(FileManager.default.fileExists(
            atPath: executablePartial.appendingPathComponent(
                "Scholium_ScholiumCore.bundle"
            ).path
        ))

        let conflict = fixture.root.appendingPathComponent("conflict/bin")
        try FileManager.default.createDirectory(at: conflict, withIntermediateDirectories: true)
        let conflictBundle = conflict.appendingPathComponent(
            "Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: conflictBundle, withIntermediateDirectories: true)
        try Data("different".utf8).write(to: conflictBundle.appendingPathComponent("payload"))
        let conflictResult = try fixture.run(prefix: fixture.root.appendingPathComponent("conflict"))
        #expect(conflictResult.status != 0)
        #expect(!FileManager.default.fileExists(
            atPath: conflict.appendingPathComponent("scholium").path
        ))
        #expect(try Data(contentsOf: conflictBundle.appendingPathComponent("payload"))
            == Data("different".utf8))
    }

    @Test(
        "Every pre-commit installation interruption restores the original pair",
        arguments: [
            CLIUpdateEngine.InstallationStage.stagedContentSynchronized,
            .transactionPromoted,
            .executableReplaced,
            .bundleReplaced,
            .installedContentSynchronized,
        ]
    )
    func preCommitInterruptionRestoresOriginalPair(
        stage: CLIUpdateEngine.InstallationStage
    ) async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }
        let engine = makeEngine(
            archive: Data("interrupted-archive".utf8),
            available: releaseIdentity(label: "v0.1.0-beta.2"),
            installationFault: { observed in
                if observed == stage { throw InjectedInstallationFailure() }
            }
        )

        await #expect(throws: CLIUpdateError.self) {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .apply
            )
        }
        #expect(try Data(contentsOf: fixture.executable) == Data("old-cli".utf8))
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.1")
        #expect(try transactionDirectories(in: fixture.root).isEmpty)
    }

    @Test("A committed-manifest interruption converges to the verified new pair")
    func committedInterruptionConvergesToNewPair() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }
        let engine = makeEngine(
            archive: Data("committed-interruption".utf8),
            available: releaseIdentity(label: "v0.1.0-beta.2"),
            installationFault: { stage in
                if stage == .committedManifestWritten {
                    throw InjectedInstallationFailure()
                }
            }
        )

        await #expect(throws: CLIUpdateError.self) {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .apply
            )
        }
        #expect(!(try transactionDirectories(in: fixture.root)).isEmpty)

        try CLIUpdateEngine.recoverInterruptedInstallation(at: fixture.root)

        #expect(try Data(contentsOf: fixture.executable) == Data("new-cli".utf8))
        #expect(try readReleaseLabel(from: fixture.bundle) == "v0.1.0-beta.2")
        #expect(try transactionDirectories(in: fixture.root).isEmpty)
    }

    @Test("Concurrent package installers cannot publish a mixed-version pair")
    func concurrentInstallersPublishOneCoherentPair() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let secondPackage = fixture.root.appendingPathComponent(
            "package-two",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: fixture.packageRoot, to: secondPackage)
        let secondExecutable = secondPackage.appendingPathComponent("scholium")
        var secondExecutableData = try Data(contentsOf: secondExecutable)
        secondExecutableData.append(Data("\n# second package\n".utf8))
        try secondExecutableData.write(to: secondExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: secondExecutable.path
        )
        let secondResource = Data("second-resource".utf8)
        try secondResource.write(
            to: secondPackage.appendingPathComponent(
                "Scholium_ScholiumCore.bundle/payload"
            )
        )
        let prefix = fixture.root.appendingPathComponent("concurrent")

        let first = try fixture.launch(installer: fixture.installer, prefix: prefix)
        let second = try fixture.launch(
            installer: secondPackage.appendingPathComponent("install-scholium-cli.sh"),
            prefix: prefix
        )
        let firstResult = first.finish()
        let secondResult = second.finish()

        let installedExecutable = try Data(
            contentsOf: prefix.appendingPathComponent("bin/scholium")
        )
        let installedResource = try Data(
            contentsOf: prefix.appendingPathComponent(
                "bin/Scholium_ScholiumCore.bundle/payload"
            )
        )
        let firstExecutable = try Data(contentsOf: fixture.sourceExecutable)
        let firstResource = try Data(
            contentsOf: fixture.sourceBundle.appendingPathComponent("payload")
        )
        #expect(
            (installedExecutable == firstExecutable
                && installedResource == firstResource)
                || (installedExecutable == secondExecutableData
                    && installedResource == secondResource)
        )
        #expect(firstResult.status != 0 || secondResult.status != 0)
    }

    @Test("The updater refuses the shared installer lock")
    func updaterRefusesSharedInstallerLock() async throws {
        let fixture = try UpdateFixture(
            identity: releaseIdentity(label: "v0.1.0-beta.1"),
            executableContents: Data("old-cli".utf8)
        )
        defer { fixture.remove() }
        let lock = fixture.root.appendingPathComponent(
            ".scholium-cli-install.lock"
        )
        let descriptor = Darwin.open(
            lock.path,
            O_RDWR | O_CREAT | O_NOFOLLOW,
            0o600
        )
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        let engine = makeEngine(
            archive: Data("locked-archive".utf8),
            available: releaseIdentity(label: "v0.1.0-beta.2")
        )

        await #expect(throws: CLIUpdateError.concurrentUpdate) {
            _ = try await engine.run(
                currentExecutable: fixture.executable,
                currentIdentity: fixture.identity,
                mode: .check
            )
        }
    }

    @Test("The package installer refuses the shared updater lock")
    func installerRefusesSharedUpdaterLock() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let prefix = fixture.root.appendingPathComponent(
            "installer-locked",
            isDirectory: true
        )
        let destination = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let lock = destination.appendingPathComponent(
            ".scholium-cli-install.lock"
        )
        let descriptor = Darwin.open(
            lock.path,
            O_RDWR | O_CREAT | O_NOFOLLOW,
            0o600
        )
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)

        let result = try fixture.run(prefix: prefix)

        #expect(result.status == 75)
        #expect(result.stderr.contains("already running"))
        #expect(!FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("scholium").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(
                "Scholium_ScholiumCore.bundle",
                isDirectory: true
            ).path
        ))
    }

    private func makeEngine(
        archive: Data,
        available: CLIReleaseIdentity,
        checksumOverride: String? = nil,
        candidateArchitectures: Set<String> = ["arm64"],
        installationFault: (@Sendable (CLIUpdateEngine.InstallationStage) throws -> Void)? = nil
    ) -> CLIUpdateEngine {
        let checksum = checksumOverride ?? sha256Hex(archive)
        let fetchResource: CLIUpdateEngine.ResourceFetcher = { url in
            let data = url.pathExtension == "sha256"
                ? Data("\(checksum)  \(ScholiumCLIDistribution.archiveName)\n".utf8)
                : archive
            return CLIUpdateFetchedResource(data: data, finalURL: url)
        }
        let extractArchive: CLIUpdateEngine.ArchiveExtractor = { _, destination in
            try writePackage(
                at: destination,
                identity: available,
                executableContents: Data("new-cli".utf8)
            )
        }
        let inspectArchitectures: CLIUpdateEngine.ArchitectureInspector = { executable in
            executable.deletingLastPathComponent().lastPathComponent == "Scholium-CLI"
                ? candidateArchitectures
                : ["arm64"]
        }
        if let installationFault {
            return CLIUpdateEngine(
                fetchResource: fetchResource,
                extractArchive: extractArchive,
                inspectArchitectures: inspectArchitectures,
                verifySignature: { _ in },
                installationFault: installationFault
            )
        }
        return CLIUpdateEngine(
            fetchResource: fetchResource,
            extractArchive: extractArchive,
            inspectArchitectures: inspectArchitectures,
            verifySignature: { _ in }
        )
    }
}

private struct InjectedInstallationFailure: Error {}

private struct UpdateFixture {
    let root: URL
    let executable: URL
    let bundle: URL
    let identity: CLIReleaseIdentity

    init(identity: CLIReleaseIdentity, executableContents: Data) throws {
        self.identity = identity
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-update-test-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        executable = root.appendingPathComponent("scholium")
        bundle = root.appendingPathComponent(
            "Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try executableContents.write(to: executable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        try writeBundle(at: bundle, identity: identity)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct InstallerFixture {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    struct Running {
        let process: Process
        let output: Pipe
        let errors: Pipe

        func finish() -> Result {
            process.waitUntilExit()
            return Result(
                status: process.terminationStatus,
                stdout: String(
                    decoding: output.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ),
                stderr: String(
                    decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )
            )
        }
    }

    let root: URL
    let packageRoot: URL
    let installer: URL
    let sourceExecutable: URL
    let sourceBundle: URL

    init() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = repositoryRoot
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
                "scholium-cli-installer-test-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        packageRoot = root.appendingPathComponent("package", isDirectory: true)
        installer = packageRoot.appendingPathComponent("install-scholium-cli.sh")
        sourceExecutable = packageRoot.appendingPathComponent("scholium")
        sourceBundle = packageRoot.appendingPathComponent(
            "Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent(
                "Tools/Packaging/install-scholium-cli.sh"
            ),
            to: installer
        )
        let executableSource = """
        #!/bin/zsh
        if [[ "${1:-}" == "version" || "${1:-}" == "doctor" ]]; then
          print '{"schema_version":1,"ok":true}'
          exit 0
        fi
        exit 64
        """
        try Data(executableSource.utf8).write(to: sourceExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceExecutable.path
        )
        try FileManager.default.createDirectory(
            at: sourceBundle,
            withIntermediateDirectories: true
        )
        try Data("resource".utf8).write(
            to: sourceBundle.appendingPathComponent("payload")
        )
    }

    func run(prefix: URL) throws -> Result {
        try launch(installer: installer, prefix: prefix).finish()
    }

    func launch(installer: URL, prefix: URL) throws -> Running {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [installer.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "SCHOLIUM_CLI_PREFIX": prefix.path,
        ]) { _, explicit in explicit }
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        return Running(process: process, output: output, errors: errors)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func releaseIdentity(label: String) -> CLIReleaseIdentity {
    CLIReleaseIdentity(
        marketingVersion: "0.1.0",
        releaseLabel: label,
        buildNumber: "1",
        packageMode: "release",
        gitExactTag: label
    )
}

private func writePackage(
    at expanded: URL,
    identity: CLIReleaseIdentity,
    executableContents: Data
) throws {
    let packageRoot = expanded.appendingPathComponent("Scholium-CLI", isDirectory: true)
    try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
    let executable = packageRoot.appendingPathComponent("scholium")
    try executableContents.write(to: executable, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    try writeBundle(
        at: packageRoot.appendingPathComponent(
            "Scholium_ScholiumCore.bundle",
            isDirectory: true
        ),
        identity: identity
    )
}

private func writeBundle(at bundle: URL, identity: CLIReleaseIdentity) throws {
    let resources = bundle
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let values: [String: Any] = [
        "schema": "scholium-build-provenance-v1",
        "git_exact_tag": identity.gitExactTag ?? identity.releaseLabel,
        "source_clean": true,
        "release_label": identity.releaseLabel,
        "marketing_version": identity.marketingVersion,
        "build_number": identity.buildNumber,
        "package_mode": identity.packageMode ?? "release",
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: values,
        format: .xml,
        options: 0
    )
    try data.write(
        to: resources.appendingPathComponent("ScholiumBuildProvenance.plist"),
        options: .atomic
    )
}

private func readReleaseLabel(from bundle: URL) throws -> String {
    let url = bundle
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("ScholiumBuildProvenance.plist")
    let values = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url),
        options: [],
        format: nil
    ) as? [String: Any]
    return try #require(values?["release_label"] as? String)
}

private func writeTransactionManifest(
    at transaction: URL,
    oldExecutableFingerprint: String,
    oldBundleFingerprint: String,
    newExecutableFingerprint: String,
    newBundleFingerprint: String
) throws {
    let manifest: [String: Any] = [
        "schema_version": 1,
        "state": "prepared",
        "executable_name": "scholium",
        "bundle_name": "Scholium_ScholiumCore.bundle",
        "old_executable_fingerprint": oldExecutableFingerprint,
        "old_bundle_fingerprint": oldBundleFingerprint,
        "new_executable_fingerprint": newExecutableFingerprint,
        "new_bundle_fingerprint": newBundleFingerprint,
    ]
    try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.sortedKeys]
    ).write(
        to: transaction.appendingPathComponent("manifest.json"),
        options: .atomic
    )
}

private func transactionDirectories(in root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).filter { $0.lastPathComponent.hasPrefix(".scholium-cli-update-") }
}

private func sha256Hex(_ data: Data) -> String {
    importCryptoSHA256(data)
}

private func importCryptoSHA256(_ data: Data) -> String {
    CryptoKit.SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
