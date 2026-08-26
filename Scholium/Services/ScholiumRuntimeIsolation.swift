import Foundation

/// Resolves an explicit Debug/QA root or the bounded packaged-performance
/// driver root. Ordinary Release launches never accept an environment override
/// or invent a fallback.
enum ScholiumRuntimeIsolation {
    enum LayoutDirectionOverride: Equatable {
        case leftToRight
        case rightToLeft
    }

    static let productionBundleIdentifier = "com.scholium.app"
    static let qaBundleIdentifier = "com.scholium.qa"
    /// One fallback identity per QA process. Reusing it inside the process
    /// prevents repeated bootstrap tasks from opening new scenes, while a new
    /// launch receives a fresh value and cannot collide with stale native
    /// scene bookkeeping from an earlier QA process.
    static let qaFixtureWindowSessionID = UUID()
    static let packagedPerformanceWindowSessionID = UUID()
    static let packagedPerformanceIsolationArgument =
        "--scholium-performance-driver-isolation"

    static func homeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL? {
        guard let explicit = nonempty(environment["SCHOLIUM_HOME"]) else {
            return nil
        }
#if DEBUG
        let isDebugBuild = true
#else
        let isDebugBuild = false
#endif
        guard allowsExplicitHome(
            environment: environment,
            arguments: arguments,
            bundleIdentifier: bundleIdentifier,
            isDebugBuild: isDebugBuild
        ) else { return nil }
        return URL(
            fileURLWithPath: (explicit as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
    }

    static func allowsExplicitHome(
        environment: [String: String],
        arguments: [String],
        bundleIdentifier: String?,
        isDebugBuild: Bool
    ) -> Bool {
        if isDebugBuild { return true }
        return allowsPackagedPerformanceIsolation(
            environment: environment,
            arguments: arguments,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func allowsPackagedPerformanceIsolation(
        environment: [String: String],
        arguments: [String],
        bundleIdentifier: String?
    ) -> Bool {
        bundleIdentifier == productionBundleIdentifier
            && arguments.contains(packagedPerformanceIsolationArgument)
            && nonempty(environment["SCHOLIUM_PERFORMANCE_RUN_ID"]) != nil
    }

    static func fixtureRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isDebugBuild: Bool? = nil
    ) -> URL? {
        guard let explicit = nonempty(
            environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"]
        ) else { return nil }
        let debugBuild = isDebugBuild ?? currentBuildIsDebug
        guard debugBuild || allowsPackagedPerformanceIsolation(
            environment: environment,
            arguments: arguments,
            bundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        return URL(
            fileURLWithPath: (explicit as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
    }

    /// Supplies one synthetic existing vault path so XCUITest can exercise the
    /// real Restore Access sheet without corrupting a persisted registration.
    static func fileSelectionRecoveryProofURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL? {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier,
              environment["SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY"] == "1",
              let root = fixtureRootURL(environment: environment) else {
            return nil
        }
        return root
            .appendingPathComponent("01-analyses", isDirectory: true)
            .standardizedFileURL
#else
        return nil
#endif
    }

    /// Resolves the one deterministic native-window identity requested by
    /// isolated QA or packaged-performance automation. The bootstrap scene
    /// installs this identity in the initial workspace route; later windows
    /// keep their independently generated IDs.
    static func initialWindowSessionID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isDebugBuild: Bool? = nil
    ) -> UUID? {
        let debugBuild = isDebugBuild ?? currentBuildIsDebug
        if debugBuild {
            guard bundleIdentifier == qaBundleIdentifier else { return nil }
            if let rawID = nonempty(environment["SCHOLIUM_UI_TEST_SESSION_ID"]) {
                return UUID(uuidString: rawID)
            }
            guard fixtureRootURL(
                environment: environment,
                arguments: arguments,
                bundleIdentifier: bundleIdentifier,
                isDebugBuild: true
            ) != nil else { return nil }
            return qaFixtureWindowSessionID
        }
        guard allowsPackagedPerformanceIsolation(
            environment: environment,
            arguments: arguments,
            bundleIdentifier: bundleIdentifier
        ), fixtureRootURL(
            environment: environment,
            arguments: arguments,
            bundleIdentifier: bundleIdentifier,
            isDebugBuild: false
        ) != nil else { return nil }
        return packagedPerformanceWindowSessionID
    }

    /// Returns an explicitly requested isolated-automation scene default
    /// without correcting a native window after it opens or coupling the value
    /// to fixture setup.
    static func initialWorkspaceWidth(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isDebugBuild: Bool? = nil
    ) -> CGFloat? {
        let debugBuild = isDebugBuild ?? currentBuildIsDebug
        let allowsWidth = debugBuild
            ? bundleIdentifier == qaBundleIdentifier
            : allowsPackagedPerformanceIsolation(
                environment: environment,
                arguments: arguments,
                bundleIdentifier: bundleIdentifier
            )
        guard allowsWidth,
              let rawWidth = nonempty(
                  environment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"]
              ),
              let width = Double(rawWidth),
              width > 0 else {
            return nil
        }
        return CGFloat(width)
    }

    private static var currentBuildIsDebug: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    /// Provides a deterministic interface direction only to the isolated QA
    /// executable. Locale launch arguments do not reliably update SwiftUI's
    /// layout environment when the app has no localization for that locale.
    static func layoutDirectionOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> LayoutDirectionOverride? {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier,
              let value = nonempty(
                  environment["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION"]
              )?.lowercased()
        else { return nil }

        switch value {
        case "ltr":
            return .leftToRight
        case "rtl":
            return .rightToLeft
        default:
            return nil
        }
#else
        return nil
#endif
    }

    /// Prevents AppKit's process-wide saved scene state from leaking between
    /// isolated QA journeys. Scholium's own `WindowSession` snapshots remain
    /// active; the one journey that verifies native multiwindow restoration
    /// opts back in explicitly.
    static func disablesSystemWindowRestoration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier else { return false }
        return environment["SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION"] != "1"
#else
        return false
#endif
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
