import Darwin
import Foundation
import ScholiumApplication
import Testing

@Suite("Scholium delivery paths")
struct ScholiumPathsTests {
    @Test("Scholium creates isolated app state without importing another product")
    func isolatedApplicationState() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let otherProduct = base.appendingPathComponent("OtherProduct", isDirectory: true)
        try FileManager.default.createDirectory(at: otherProduct, withIntermediateDirectories: true)
        try Data("unrelated".utf8).write(to: otherProduct.appendingPathComponent("marker.txt"))

        let current = try ScholiumPaths.applicationSupportURL(baseURL: base)

        #expect(current.lastPathComponent == "State-v1")
        #expect(current.deletingLastPathComponent().lastPathComponent == "Scholium")
        let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(FileManager.default.fileExists(atPath: otherProduct.appendingPathComponent("marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: current.appendingPathComponent("marker.txt").path))
    }

    @Test("Unsupported pre-release Scholium state remains nonauthorizing")
    func preReleaseStateIsNotImported() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacyRoot = base.appendingPathComponent("Scholium", isDirectory: true)
        let legacyRegistry = legacyRoot
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("workspace-registry-v2.json")
        try FileManager.default.createDirectory(
            at: legacyRegistry.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyBytes = Data("pre-release registry".utf8)
        try legacyBytes.write(to: legacyRegistry)

        let current = try ScholiumPaths.applicationSupportURL(baseURL: base)

        #expect(current.path == legacyRoot.appendingPathComponent("State-v1").path)
        #expect(try Data(contentsOf: legacyRegistry) == legacyBytes)
        #expect(!FileManager.default.fileExists(atPath: current
            .appendingPathComponent("Workspace/workspace-registration-v3.json").path))
    }

    @Test("The CLI ignores retired container state and uses ordinary Application Support")
    func ordinaryApplicationSupportDiscovery() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        let container = home.appendingPathComponent(
            "Library/Containers/com.scholium.app/Data/Library/Application Support/Scholium",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let discovered = try ScholiumPaths.sharedApplicationSupportURL(
            baseURL: base.appendingPathComponent("fallback", isDirectory: true)
        )

        #expect(discovered.standardizedFileURL == base
            .appendingPathComponent("fallback/Scholium/State-v1", isDirectory: true)
            .standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: container.path))
    }

    @Test("An isolated CLI home also isolates workspace registry state")
    func isolatedCLIWorkspaceState() throws {
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let state = try ScholiumPaths.workspaceRegistryURL(
            homeURL: isolatedHome,
            environment: ["SCHOLIUM_HOME": "/a/different/process/value"]
        )

        #expect(state.standardizedFileURL == isolatedHome
            .appendingPathComponent("registry", isDirectory: true)
            .standardizedFileURL)
    }

    @Test("The production Agent bridge namespace selects one loopback port")
    func productionAgentBridgeRoot() throws {
        let home = URL(fileURLWithPath: "/Users/researcher", isDirectory: true)
        let root = try ScholiumPaths.agentBridgeContainerURL(
            environment: [:],
            homeURL: home
        )
        let port = LocalAgentBridgeLocation.port(
            applicationSupportURL: root
        )

        #expect(root.path == "/Users/researcher/Library/Application Support/Scholium/State-v1/AgentBridge")
        #expect(LocalAgentBridgeLocation.host == "127.0.0.1")
        #expect(port == LocalAgentBridgeLocation.port(applicationSupportURL: root))
        #expect(port >= 49_152)
    }

    @Test("Production Agent credentials use the machine-state root")
    func productionAgentSessionDirectory() throws {
        let home = URL(fileURLWithPath: "/Users/researcher", isDirectory: true)
        let root = try ScholiumPaths.agentSessionCredentialDirectoryURL(
            environment: [:],
            homeURL: home
        )

        #expect(root.path == "/Users/researcher/Library/Application Support/Scholium/State-v1/Agent Sessions")
    }

    @Test("An explicit isolated home never falls through to the production bridge")
    func isolatedAgentBridgeRoot() throws {
        let root = try ScholiumPaths.agentBridgeContainerURL(
            environment: ["SCHOLIUM_HOME": "/fixture/home"]
        )

        #expect(root.path == "/fixture/home/ApplicationSupport/AgentBridge")
    }

    @Test("An explicit isolated home keeps Agent credentials inside its test state")
    func isolatedAgentSessionDirectory() throws {
        let root = try ScholiumPaths.agentSessionCredentialDirectoryURL(
            environment: ["SCHOLIUM_HOME": "/fixture/home"]
        )

        #expect(root.path == "/fixture/home/ApplicationSupport/Agent Sessions")
    }

    @Test("A Debug App keeps its bridge inside the supplied isolated app state")
    func debugAgentBridgeFallback() throws {
        let root = try ScholiumPaths.agentBridgeContainerURL(
            environment: [:],
            debugFallbackURL: URL(fileURLWithPath: "/fixture/app-support")
        )

        #expect(root.path == "/fixture/app-support/AgentBridge")
    }
}
