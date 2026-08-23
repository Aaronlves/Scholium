import Foundation
import Testing
@testable import ScholiumApp

@Suite("QA runtime isolation")
struct ScholiumRuntimeIsolationTests {
    @Test("An explicit isolated home always wins")
    func explicitHomeWins() throws {
        let explicit = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolved = ScholiumRuntimeIsolation.homeURL(
            environment: ["SCHOLIUM_HOME": explicit.path],
            bundleIdentifier: "com.scholium.app"
        )

        #expect(resolved == explicit.standardizedFileURL)
    }

    @Test("A packaged Release accepts an isolated home only for the explicit performance driver")
    func packagedReleaseIsolationIsBounded() {
        let environment = [
            "SCHOLIUM_HOME": "/fixture/home",
            "SCHOLIUM_PERFORMANCE_RUN_ID": "release-smoke",
        ]
        let marker = ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument

        #expect(ScholiumRuntimeIsolation.allowsExplicitHome(
            environment: environment,
            arguments: [marker],
            bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
            isDebugBuild: false
        ))
        #expect(!ScholiumRuntimeIsolation.allowsExplicitHome(
            environment: environment,
            arguments: [],
            bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
            isDebugBuild: false
        ))
        #expect(!ScholiumRuntimeIsolation.allowsExplicitHome(
            environment: ["SCHOLIUM_HOME": "/fixture/home"],
            arguments: [marker],
            bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
            isDebugBuild: false
        ))
        #expect(!ScholiumRuntimeIsolation.allowsExplicitHome(
            environment: environment,
            arguments: [marker],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier,
            isDebugBuild: false
        ))
    }

    @Test("The QA bundle requires an explicit isolated home")
    func qaBundleRequiresExplicitHome() throws {
        #expect(ScholiumRuntimeIsolation.homeURL(
            environment: [:],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)
        #expect(ScholiumRuntimeIsolation.homeURL(
            environment: [:],
            bundleIdentifier: "com.scholium.app"
        ) == nil)
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

    @Test("The Restore Access proof is bounded to the QA bundle and fixture")
    func fileSelectionRecoveryProofIsQABounded() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = [
            "SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY": "1",
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": root.path,
        ]
        let expected = root
            .appendingPathComponent("01-analyses", isDirectory: true)
            .standardizedFileURL

        #expect(ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
            environment: environment,
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == expected)
        #expect(ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
            environment: environment,
            bundleIdentifier: "com.scholium.app"
        ) == nil)
        #expect(ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
            environment: ["SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY": "1"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)
    }

    @Test("Only the QA bundle accepts a deterministic initial window identity")
    func initialWindowIdentityIsQABounded() {
        let id = UUID()
        let environment = ["SCHOLIUM_UI_TEST_SESSION_ID": id.uuidString]

        #expect(ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: environment,
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == id)
        #expect(ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: environment,
            bundleIdentifier: "com.scholium.app"
        ) == nil)
        #expect(ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: ["SCHOLIUM_UI_TEST_SESSION_ID": "invalid"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fallback = ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        )
        #expect(fallback == ScholiumRuntimeIsolation.qaFixtureWindowSessionID)
        #expect(ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == fallback)
        #expect(ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path],
            bundleIdentifier: "com.scholium.app"
        ) == nil)
    }

    @Test("QA viewport control is independent from fixture configuration")
    func qaViewportIsIndependent() {
        let environment = ["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1180"]

        #expect(ScholiumRuntimeIsolation.initialWorkspaceWidth(
            environment: environment,
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == 1_180)
        #expect(ScholiumRuntimeIsolation.initialWorkspaceWidth(
            environment: environment,
            bundleIdentifier: "com.scholium.app"
        ) == nil)
        #expect(ScholiumRuntimeIsolation.initialWorkspaceWidth(
            environment: ["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "invalid"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)
    }

    @Test("Only the QA bundle accepts a deterministic layout direction")
    func qaLayoutDirectionIsBounded() {
        #expect(ScholiumRuntimeIsolation.layoutDirectionOverride(
            environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "rtl"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == .rightToLeft)
        #expect(ScholiumRuntimeIsolation.layoutDirectionOverride(
            environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "LTR"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == .leftToRight)
        #expect(ScholiumRuntimeIsolation.layoutDirectionOverride(
            environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "rtl"],
            bundleIdentifier: "com.scholium.app"
        ) == nil)
        #expect(ScholiumRuntimeIsolation.layoutDirectionOverride(
            environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "unknown"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ) == nil)
    }

    @Test("QA scene restoration is disabled unless one journey explicitly enables it")
    func qaSceneRestorationIsOptIn() {
        #expect(ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
            environment: [:],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ))
        #expect(!ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
            environment: ["SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION": "1"],
            bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
        ))
        #expect(!ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
            environment: [:],
            bundleIdentifier: "com.scholium.app"
        ))
    }
}
