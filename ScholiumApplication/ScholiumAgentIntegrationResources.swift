import Foundation
import ScholiumCore
import Security

/// Public application-layer access to the release-bundled Core Protocol.
/// Delivery surfaces may reveal this ordinary Skill folder, but never edit or
/// install an external Agent host's configuration.
public enum ScholiumAgentIntegrationResources {
    public static func executableURL(at path: String) -> URL? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Finds a Codex CLI bundled in a Launch Services-registered application.
    public static func codexRuntimeURL(registeredApplicationBundles: [URL]) -> URL? {
        codexRuntimeURL(
            registeredApplicationBundles: registeredApplicationBundles,
            trustedApplication: isTrustedCodexApplication,
            trustedNestedRuntime: isTrustedCodexCLI)
    }

    /// Recheck a discovered path immediately before an automatic process launch.
    public static func verifiedCodexRuntimeURL(at executable: URL) -> URL? {
        let components = executable.standardizedFileURL.pathComponents
        guard components.count > 7,
            Array(components.suffix(7))[0...2] == ["Contents", "Resources", "codex-cli"],
            Array(components.suffix(7))[3].hasSuffix(".app"),
            Array(components.suffix(7))[4...6] == ["Contents", "MacOS", "codex"]
        else { return nil }
        let application = URL(
            fileURLWithPath: NSString.path(withComponents: Array(components.dropLast(7))),
            isDirectory: true)
        guard isTrustedCodexApplication(application) else { return nil }
        return verifiedRuntime(executable, in: application, trustedNestedRuntime: isTrustedCodexCLI)
    }

    // Kept injectable so path rejection can be tested without manufacturing an
    // OpenAI signing identity in a disposable fixture.
    static func codexRuntimeURL(
        registeredApplicationBundles: [URL], trustedApplication: (URL) -> Bool,
        trustedNestedRuntime: (URL) -> Bool
    ) -> URL? {
        for application in registeredApplicationBundles where trustedApplication(application) {
            for candidate in codexRuntimeCandidates(in: application) {
                if let runtime = verifiedRuntime(
                    candidate, in: application,
                    trustedNestedRuntime: trustedNestedRuntime)
                {
                    return runtime
                }
            }
        }
        return nil
    }

    private static func verifiedRuntime(
        _ candidate: URL, in application: URL, trustedNestedRuntime: (URL) -> Bool
    ) -> URL? {
        guard let base = canonicalFileURL(application), let runtime = canonicalFileURL(candidate)
        else { return nil }
        guard application.pathExtension == "app",
            candidate.deletingLastPathComponent().lastPathComponent == "MacOS",
            candidate.lastPathComponent == "codex",
            candidate.pathComponents.contains("codex-cli")
        else { return nil }
        // Build the expected location below the canonical app root. Any symlink
        // in the nested app or executable that redirects it changes this path.
        let relative = candidate.pathComponents.suffix(7)
        guard relative.count == 7,
            relative.first == "Contents",
            Array(relative)[1] == "Resources",
            Array(relative)[2] == "codex-cli",
            Array(relative)[3].hasSuffix(".app"),
            Array(relative)[4...6] == ["Contents", "MacOS", "codex"]
        else { return nil }
        let expected = base.appendingPathComponent(relative.joined(separator: "/"))
        guard runtime.path == expected.path, FileManager.default.isExecutableFile(atPath: runtime.path) else { return nil }
        let nestedApplication = expected.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard trustedNestedRuntime(nestedApplication) else { return nil }
        return runtime
    }

    private static func canonicalFileURL(_ url: URL) -> URL? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    private static func isTrustedCodexApplication(_ application: URL) -> Bool {
        guard Bundle(url: application)?.bundleIdentifier == "com.openai.codex" else { return false }
        return isTrustedCode(
            application,
            requirement: "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"")
    }

    private static func isTrustedCodexCLI(_ application: URL) -> Bool {
        isTrustedCode(
            application,
            requirement: "anchor apple generic and identifier \"codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"")
    }

    private static func isTrustedCode(_ url: URL, requirement source: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
            let code
        else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(source as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess
    }

    private static func codexRuntimeCandidates(in applicationBundle: URL) -> [URL] {
        let cliApplicationsDirectory =
            applicationBundle
            .appendingPathComponent("Contents/Resources/codex-cli", isDirectory: true)
        let bundledRuntimes =
            (try? FileManager.default.contentsOfDirectory(
                at: cliApplicationsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.appendingPathComponent("Contents/MacOS/codex") } ?? []

        return bundledRuntimes
    }

    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        try BundledResearchSkillResources.coreProtocolSkillDirectoryURL()
    }

    public static func chatHelperURL(bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        executableURL(at: bundleURL.appendingPathComponent("Contents/Helpers/ScholiumAgentHelper").path)
    }

}
