import Foundation
import Testing

@testable import ScholiumApp

@Suite("QA runtime isolation")
struct ScholiumRuntimeIsolationTests {
    private let restorationBundleIdentifier =
        "com.scholium.qa.restoration.a7304eb3-ca16-468a-80cc-be313aee0aef"

    @Test("Restoration QA identities require an exact prefix and canonical lowercase UUID")
    func restorationBundleIdentityIsStrict() {
        #expect(ScholiumRuntimeIsolation.isQABundleIdentifier(ScholiumRuntimeIsolation.qaBundleIdentifier))
        #expect(ScholiumRuntimeIsolation.isQABundleIdentifier(restorationBundleIdentifier))
        let rejected: [String?] = [
            nil, "", "com.scholium.app", "com.scholium.qa.other",
            "com.scholium.qa.restoration", "com.scholium.qa.restoration.",
            "com.scholium.qa.restoration.invalid",
            "com.scholium.qa.restoration.A7304EB3-CA16-468A-80CC-BE313AEE0AEF",
            "com.scholium.qa.restoration.a7304eb3ca16468a80ccbe313aee0aef",
            "com.scholium.qa.restoration.{a7304eb3-ca16-468a-80cc-be313aee0aef}",
            restorationBundleIdentifier + ".other", restorationBundleIdentifier + " ",
            "other." + restorationBundleIdentifier,
        ]
        for identifier in rejected {
            #expect(!ScholiumRuntimeIsolation.isQABundleIdentifier(identifier))
        }
    }

    @Test("A restoration QA home is explicit and never synthesized from the bundle identity")
    func restorationHomeRequiresExplicitPath() {
        for environment in [[:], ["SCHOLIUM_HOME": " \n\t"]] {
            #expect(
                ScholiumRuntimeIsolation.homeURL(
                    environment: environment, bundleIdentifier: restorationBundleIdentifier) == nil)
        }
        let home = URL(fileURLWithPath: "/fixture/restoration/home", isDirectory: true)
        #expect(
            ScholiumRuntimeIsolation.homeURL(
                environment: ["SCHOLIUM_HOME": home.path],
                bundleIdentifier: restorationBundleIdentifier) == home)
    }

    @Test("Restoration QA uses the fixture session owner and explicitly opts into native restoration")
    func restorationJourneyAdmissionIsBounded() {
        let windowID = UUID()
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: ["SCHOLIUM_UI_TEST_SESSION_ID": windowID.uuidString],
                bundleIdentifier: restorationBundleIdentifier) == windowID)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": "/fixture/Triptych"],
                bundleIdentifier: restorationBundleIdentifier) == ScholiumRuntimeIsolation.qaFixtureWindowSessionID)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: [:], bundleIdentifier: restorationBundleIdentifier) == nil)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: ["SCHOLIUM_UI_TEST_SESSION_ID": windowID.uuidString],
                bundleIdentifier: restorationBundleIdentifier + ".other") == nil)
        #expect(
            ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: [:], bundleIdentifier: restorationBundleIdentifier))
        #expect(
            ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: ["SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION": "true"],
                bundleIdentifier: restorationBundleIdentifier))
        #expect(
            !ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: ["SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION": "1"],
                bundleIdentifier: restorationBundleIdentifier))
    }

    @Test("A restoration QA identity grants no packaged Release isolation")
    func restorationIdentityDoesNotAuthorizeReleaseIsolation() {
        let environment = [
            "SCHOLIUM_HOME": "/fixture/home",
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": "/fixture/Triptych",
            "SCHOLIUM_UI_TEST_SESSION_ID": UUID().uuidString,
            "SCHOLIUM_PERFORMANCE_RUN_ID": "restoration",
        ]
        let arguments = [ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument]
        #expect(
            !ScholiumRuntimeIsolation.allowsExplicitHome(
                environment: environment, arguments: arguments,
                bundleIdentifier: restorationBundleIdentifier, isDebugBuild: false))
        #expect(
            ScholiumRuntimeIsolation.fixtureRootURL(
                environment: environment, arguments: arguments,
                bundleIdentifier: restorationBundleIdentifier, isDebugBuild: false) == nil)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: environment, arguments: arguments,
                bundleIdentifier: restorationBundleIdentifier, isDebugBuild: false) == nil)
    }

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

        #expect(
            ScholiumRuntimeIsolation.allowsExplicitHome(
                environment: environment,
                arguments: [marker],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ))
        #expect(
            !ScholiumRuntimeIsolation.allowsExplicitHome(
                environment: environment,
                arguments: [],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ))
        #expect(
            !ScholiumRuntimeIsolation.allowsExplicitHome(
                environment: ["SCHOLIUM_HOME": "/fixture/home"],
                arguments: [marker],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ))
        #expect(
            !ScholiumRuntimeIsolation.allowsExplicitHome(
                environment: environment,
                arguments: [marker],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier,
                isDebugBuild: false
            ))
    }

    @Test("The QA bundle requires an explicit isolated home")
    func qaBundleRequiresExplicitHome() throws {
        #expect(
            ScholiumRuntimeIsolation.homeURL(
                environment: [:],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.homeURL(
                environment: [:],
                bundleIdentifier: "com.scholium.app"
            ) == nil)
    }

    @Test("A fixture opens only when the test explicitly supplies its root")
    func fixtureRequiresExplicitEnvironment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(
            ScholiumRuntimeIsolation.fixtureRootURL(
                environment: [:]
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.fixtureRootURL(
                environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": root.path]
            ) == root.standardizedFileURL)

        let releaseEnvironment = [
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": root.path,
            "SCHOLIUM_PERFORMANCE_RUN_ID": "release-fixture",
        ]
        #expect(
            ScholiumRuntimeIsolation.fixtureRootURL(
                environment: releaseEnvironment,
                arguments: [
                    ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument
                ],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ) == root.standardizedFileURL)
        #expect(
            ScholiumRuntimeIsolation.fixtureRootURL(
                environment: releaseEnvironment,
                arguments: [],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ) == nil)
    }

    @Test("The Restore Access proof is bounded to the QA bundle and fixture")
    func fileSelectionRecoveryProofIsQABounded() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = [
            "SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY": "1",
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": root.path,
        ]
        let expected =
            root
            .appendingPathComponent("01-analyses", isDirectory: true)
            .standardizedFileURL

        #expect(
            ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
                environment: environment,
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == expected)
        #expect(
            ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
                environment: environment,
                bundleIdentifier: "com.scholium.app"
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL(
                environment: ["SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY": "1"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == nil)
    }

    @Test("Only isolated automation accepts a deterministic initial window identity")
    func initialWindowIdentityIsIsolationBounded() {
        let id = UUID()
        let environment = ["SCHOLIUM_UI_TEST_SESSION_ID": id.uuidString]

        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: environment,
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == id)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: environment,
                bundleIdentifier: "com.scholium.app"
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
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
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == fallback)
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: ["SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path],
                bundleIdentifier: "com.scholium.app"
            ) == nil)

        let releaseEnvironment = [
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixtureRoot.path,
            "SCHOLIUM_PERFORMANCE_RUN_ID": "release-window",
        ]
        let releaseFallback = ScholiumRuntimeIsolation.initialWindowSessionID(
            environment: releaseEnvironment,
            arguments: [
                ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument
            ],
            bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
            isDebugBuild: false
        )
        #expect(
            releaseFallback
                == ScholiumRuntimeIsolation.packagedPerformanceWindowSessionID
        )
        #expect(
            ScholiumRuntimeIsolation.initialWindowSessionID(
                environment: releaseEnvironment,
                arguments: [],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ) == nil)
    }

    @Test("QA and packaged-performance viewport controls stay bounded")
    func isolatedViewportIsBounded() {
        let environment = ["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1180"]

        #expect(
            ScholiumRuntimeIsolation.initialWorkspaceWidth(
                environment: environment,
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == 1_180)
        #expect(
            ScholiumRuntimeIsolation.initialWorkspaceWidth(
                environment: environment,
                bundleIdentifier: "com.scholium.app"
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.initialWorkspaceWidth(
                environment: ["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "invalid"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == nil)

        let releaseEnvironment = [
            "SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1380",
            "SCHOLIUM_PERFORMANCE_RUN_ID": "release-width",
        ]
        #expect(
            ScholiumRuntimeIsolation.initialWorkspaceWidth(
                environment: releaseEnvironment,
                arguments: [
                    ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument
                ],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ) == 1_380)
        #expect(
            ScholiumRuntimeIsolation.initialWorkspaceWidth(
                environment: releaseEnvironment,
                arguments: [],
                bundleIdentifier: ScholiumRuntimeIsolation.productionBundleIdentifier,
                isDebugBuild: false
            ) == nil)
    }

    @Test("Only the QA bundle accepts a deterministic layout direction")
    func qaLayoutDirectionIsBounded() {
        #expect(
            ScholiumRuntimeIsolation.layoutDirectionOverride(
                environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "rtl"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == .rightToLeft)
        #expect(
            ScholiumRuntimeIsolation.layoutDirectionOverride(
                environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "LTR"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == .leftToRight)
        #expect(
            ScholiumRuntimeIsolation.layoutDirectionOverride(
                environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "rtl"],
                bundleIdentifier: "com.scholium.app"
            ) == nil)
        #expect(
            ScholiumRuntimeIsolation.layoutDirectionOverride(
                environment: ["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION": "unknown"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ) == nil)
    }

    @Test("QA scene restoration is disabled unless one journey explicitly enables it")
    func qaSceneRestorationIsOptIn() {
        #expect(
            ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: [:],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ))
        #expect(
            !ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: ["SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION": "1"],
                bundleIdentifier: ScholiumRuntimeIsolation.qaBundleIdentifier
            ))
        #expect(
            !ScholiumRuntimeIsolation.disablesSystemWindowRestoration(
                environment: [:],
                bundleIdentifier: "com.scholium.app"
            ))
    }
}
