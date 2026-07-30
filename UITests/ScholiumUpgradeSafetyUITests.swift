@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

final class ScholiumUpgradeSafetyUITests: XCTestCase {
    @MainActor
    func testReadOnlyLaunch() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_UPGRADE_DRIVER_APP_PATH"] != nil else {
            throw XCTSkip("The external upgrade-safety driver is not configured.")
        }

        let applicationPath = try required("SCHOLIUM_UPGRADE_DRIVER_APP_PATH", in: environment)
        let fixtureRoot = try required("SCHOLIUM_UPGRADE_DRIVER_FIXTURE_ROOT", in: environment)
        let homeRoot = try required("SCHOLIUM_UPGRADE_DRIVER_HOME_ROOT", in: environment)
        let label = try required("SCHOLIUM_UPGRADE_DRIVER_LABEL", in: environment)
        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = "upgrade-safety-\(label)"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "paper_analysis"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Upgrade Safety/Launch Probe.md"
        application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = "1080"

        defer { application.terminate() }
        application.launch()
        XCTAssertTrue(
            application.windows.firstMatch.waitForExistence(timeout: 30),
            "The \(label) app window did not appear."
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["scholium.librarySurface"]
                .waitForExistence(timeout: 30),
            "The \(label) Library did not become available."
        )
        XCTAssertTrue(
            application.descendants(matching: .any)[
                "scholium.renderedDocument.Upgrade Safety/Launch Probe.md"
            ].waitForExistence(timeout: 30),
            "The \(label) read-only launch probe did not render."
        )

        let screenshot = XCTAttachment(screenshot: application.windows.firstMatch.screenshot())
        screenshot.name = "\(label)-read-only-launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func required(_ key: String, in environment: [String: String]) throws -> String {
        let value = try XCTUnwrap(environment[key], "Missing \(key).")
        return try XCTUnwrap(value.isEmpty ? nil : value, "Empty \(key).")
    }
}
