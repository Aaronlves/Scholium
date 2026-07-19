import Foundation
import Testing
@testable import ScholiumApp

@Suite("QA runtime isolation")
struct ScholiumRuntimeIsolationTests {
    @Test("An explicit isolated home always wins")
    func explicitHomeWins() throws {
        let explicit = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let resolved = ScholiumRuntimeIsolation.homeURL(
            environment: ["SCHOLIUM_HOME": explicit.path],
            bundleIdentifier: "com.scholium.app",
            qaHomeURL: fallback
        )

        #expect(resolved == explicit.standardizedFileURL)
    }

    @Test("The QA bundle never falls back to production Application Support")
    func qaBundleUsesDedicatedHome() throws {
        let qaHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(ScholiumRuntimeIsolation.homeURL(
            environment: [:],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier,
            qaHomeURL: qaHome
        ) == qaHome.standardizedFileURL)
        #expect(ScholiumRuntimeIsolation.homeURL(
            environment: [:],
            bundleIdentifier: "com.scholium.app",
            qaHomeURL: qaHome
        ) == nil)
        #expect(
            ScholiumRuntimeIsolation.defaultQAHomeURL.standardizedFileURL.path
                == "/tmp/scholium-workbench-home"
        )
    }

    @Test("A fixture opens only when the test explicitly supplies its root")
    func fixtureRequiresExplicitEnvironment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(ScholiumRuntimeIsolation.fixtureRootURL(
            environment: [:]
        ) == nil)
        #expect(ScholiumRuntimeIsolation.fixtureRootURL(
            environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": root.path]
        ) == root.standardizedFileURL)
    }

    @Test("QA viewport control is independent from fixture configuration")
    func qaViewportIsIndependent() {
        let environment = ["SCHOLIUM_UI_TEST_WINDOW_WIDTH": "1180"]

        #expect(ScholiumRuntimeIsolation.windowWidth(
            environment: environment,
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == 1_180)
        #expect(ScholiumRuntimeIsolation.windowWidth(
            environment: environment,
            bundleIdentifier: "com.scholium.app"
        ) == nil)
        #expect(ScholiumRuntimeIsolation.windowWidth(
            environment: ["SCHOLIUM_UI_TEST_WINDOW_WIDTH": "invalid"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)
    }
}
