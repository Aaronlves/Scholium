import Foundation
import CryptoKit
import ScholiumCLIUpdate
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

    private func makeEngine(
        archive: Data,
        available: CLIReleaseIdentity,
        checksumOverride: String? = nil,
        candidateArchitectures: Set<String> = ["arm64"]
    ) -> CLIUpdateEngine {
        let checksum = checksumOverride ?? sha256Hex(archive)
        return CLIUpdateEngine(
            fetchResource: { url in
                let data = url.pathExtension == "sha256"
                    ? Data("\(checksum)  \(ScholiumCLIDistribution.archiveName)\n".utf8)
                    : archive
                return CLIUpdateFetchedResource(data: data, finalURL: url)
            },
            extractArchive: { _, destination in
                try writePackage(
                    at: destination,
                    identity: available,
                    executableContents: Data("new-cli".utf8)
                )
            },
            inspectArchitectures: { executable in
                executable.deletingLastPathComponent().lastPathComponent == "Scholium-CLI"
                    ? candidateArchitectures
                    : ["arm64"]
            },
            verifySignature: { _ in }
        )
    }
}

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
