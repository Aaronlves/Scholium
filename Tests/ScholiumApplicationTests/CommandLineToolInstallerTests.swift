import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Command-line tool installation")
struct CommandLineToolInstallerTests {
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
        await #expect(throws: CommandLineToolInstallationError.destinationIsSymbolicLink) {
            try await installer.installCommandLineTool()
        }
        #expect(try Data(contentsOf: redirected) == Data("do not replace".utf8))
    }

    private func writeCurrentResourceSentinels(in bundle: URL) throws {
        let skills = bundle.appendingPathComponent(
            "Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills",
            isDirectory: true
        )
        for path in [
            "README.md",
            "Scholium System Skills/scholium-core-protocol/SKILL.md",
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
