import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Command-line tool installation")
struct CommandLineToolInstallerTests {
    @Test("A sandbox-container copy is not reported as the user installation")
    func ignoresSandboxContainerHome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-sandbox-home-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Scholium.app", isDirectory: true)
        let source = bundle.appendingPathComponent("Contents/Helpers/scholium")
        let accountHome = root.appendingPathComponent("Users/researcher", isDirectory: true)
        let sandboxHome = accountHome.appendingPathComponent(
            "Library/Containers/com.scholium.app/Data",
            isDirectory: true
        )
        let containerDestination = sandboxHome.appendingPathComponent(
            ".local/bin/scholium",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeCurrentResourceSentinels(in: bundle)
        try Data("bundled executable".utf8).write(to: source)
        try FileManager.default.createDirectory(
            at: containerDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("bundled executable".utf8).write(to: containerDestination)
        let bundledResources = bundle.appendingPathComponent(
            "Contents/Resources/Scholium_ScholiumCore.bundle",
            isDirectory: true
        )
        try FileManager.default.copyItem(
            at: bundledResources,
            to: containerDestination.deletingLastPathComponent().appendingPathComponent(
                "Scholium_ScholiumCore.bundle",
                isDirectory: true
            )
        )

        let installationHome = CommandLineToolInstaller.installationHomeDirectory(
            accountHomePath: accountHome.path
        )
        let installer = CommandLineToolInstaller(
            environment: { [:] },
            homeDirectory: { installationHome },
            bundleURL: { bundle },
            version: "test"
        )

        let status = await installer.commandLineToolStatus()
        #expect(status.state == .notInstalled)
        #expect(status.installPath == accountHome.appendingPathComponent(
            ".local/bin/scholium"
        ).path)
        #expect(!status.installPath.contains("/Library/Containers/"))
    }

    @Test("An unresolved account home cannot fall back to the sandbox container")
    func unresolvedAccountHome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-unresolved-home-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Scholium.app", isDirectory: true)
        let source = bundle.appendingPathComponent("Contents/Helpers/scholium")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeCurrentResourceSentinels(in: bundle)
        try Data("bundled".utf8).write(to: source)
        let installer = CommandLineToolInstaller(
            environment: { [:] },
            homeDirectory: { nil },
            bundleURL: { bundle },
            version: "test"
        )

        let status = await installer.commandLineToolStatus()
        #expect(status.state == .invalidInstallation)
        #expect(status.repairMessage?.contains("login account's home folder") == true)
        await #expect(throws: CommandLineToolInstallationError.installationHomeUnavailable) {
            try await installer.installCommandLineTool()
        }
    }

    @Test("Installer atomically copies and verifies the bundled executable")
    func installAndUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-installer-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Scholium.app", isDirectory: true)
        let source = bundle.appendingPathComponent(
            "Contents/Helpers/scholium",
            isDirectory: false
        )
        let destination = root.appendingPathComponent("bin/scholium", isDirectory: false)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeCurrentResourceSentinels(in: bundle)
        try Data("first executable".utf8).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: source.path
        )
        let installer = CommandLineToolInstaller(
            environment: {
                [
                    "SCHOLIUM_CLI_INSTALL_PATH": destination.path,
                    "PATH": destination.deletingLastPathComponent().path,
                ]
            },
            homeDirectory: { root },
            bundleURL: { bundle },
            version: "test"
        )

        #expect(await installer.commandLineToolStatus().state == .notInstalled)
        let installed = try await installer.installCommandLineTool()
        #expect(installed.state == .installed)
        #expect(installed.isOnCurrentPATH)
        #expect(try Data(contentsOf: destination) == Data("first executable".utf8))

        try Data("second executable".utf8).write(to: source, options: .atomic)
        #expect(await installer.commandLineToolStatus().state == .updateAvailable)
        let updated = try await installer.installCommandLineTool()
        #expect(updated.state == .installed)
        #expect(try Data(contentsOf: destination) == Data("second executable".utf8))
    }

    @Test("Installer refuses a symbolic-link destination")
    func refusesSymbolicLinkDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-installer-link-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Scholium.app/Contents/Helpers/scholium")
        let destination = root.appendingPathComponent("bin/scholium")
        let redirected = root.appendingPathComponent("redirected")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeCurrentResourceSentinels(
            in: root.appendingPathComponent("Scholium.app", isDirectory: true)
        )
        try Data("bundled".utf8).write(to: source)
        try Data("do not replace".utf8).write(to: redirected)
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: redirected
        )
        let installer = CommandLineToolInstaller(
            environment: { ["SCHOLIUM_CLI_INSTALL_PATH": destination.path] },
            homeDirectory: { root },
            bundleURL: { root.appendingPathComponent("Scholium.app") },
            version: "test"
        )

        #expect(await installer.commandLineToolStatus().state == .invalidInstallation)
        await #expect(
            throws: CommandLineToolInstallationError.installationPathContainsSymbolicLink
        ) {
            try await installer.installCommandLineTool()
        }
        #expect(try Data(contentsOf: redirected) == Data("do not replace".utf8))
    }

    @Test("Installer refuses a symbolic link in the installation directory chain")
    func refusesSymbolicLinkParent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-installer-parent-link-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Scholium.app", isDirectory: true)
        let source = bundle.appendingPathComponent("Contents/Helpers/scholium")
        let redirected = root.appendingPathComponent("redirected", isDirectory: true)
        let local = root.appendingPathComponent("home/.local", isDirectory: true)
        let destination = local.appendingPathComponent("bin/scholium")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: local, withDestinationURL: redirected)
        try writeCurrentResourceSentinels(in: bundle)
        try Data("bundled".utf8).write(to: source)
        let installer = CommandLineToolInstaller(
            environment: { ["SCHOLIUM_CLI_INSTALL_PATH": destination.path] },
            homeDirectory: { root.appendingPathComponent("home") },
            bundleURL: { bundle },
            version: "test"
        )

        #expect(await installer.commandLineToolStatus().state == .invalidInstallation)
        await #expect(
            throws: CommandLineToolInstallationError.installationPathContainsSymbolicLink
        ) {
            try await installer.installCommandLineTool()
        }
        #expect(!FileManager.default.fileExists(
            atPath: redirected.appendingPathComponent("bin/scholium").path
        ))
    }

    @Test("Packaged sandbox grants only the user-local CLI installation root")
    func packagedSandboxEntitlement() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Tools/Packaging/Scholium.entitlements"
        ))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        let paths = try #require(
            plist[
                "com.apple.security.temporary-exception.files.home-relative-path.read-write"
            ] as? [String]
        )

        #expect(paths == ["/.local/"])
    }

    private func writeCurrentResourceSentinels(in bundle: URL) throws {
        let skills = bundle.appendingPathComponent(
            "Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills",
            isDirectory: true
        )
        for path in [
            "README.md",
            "Scholium System Skills/scholium-core-protocol/SKILL.md",
            "Scholium System Skills/scholium-core-protocol/references/runtime-protocol.md",
            "Scholium Method Skills/scholium-analyze/SKILL.md",
        ] {
            let target = skills.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("current research-method resource\n".utf8).write(to: target)
        }
    }
}
