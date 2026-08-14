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
        return bundleIdentifier == productionBundleIdentifier
            && arguments.contains(packagedPerformanceIsolationArgument)
            && nonempty(environment["SCHOLIUM_PERFORMANCE_RUN_ID"]) != nil
    }

    static func fixtureRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicit = nonempty(environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"]) {
            return URL(
                fileURLWithPath: (explicit as NSString).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL
        }
        return nil
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

    /// Resolves the one deterministic native-window identity requested by UI
    /// automation. The bootstrap scene installs this identity in the initial
    /// workspace route; later windows keep their independently generated IDs.
    static func initialWindowSessionID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> UUID? {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier,
              let rawID = nonempty(environment["SCHOLIUM_UI_TEST_SESSION_ID"])
        else { return nil }
        return UUID(uuidString: rawID)
#else
        return nil
#endif
    }

    /// Returns an explicitly requested QA scene default without correcting a
    /// native window after it opens or coupling the value to fixture setup.
    static func initialWorkspaceWidth(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> CGFloat? {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier,
              let rawWidth = nonempty(environment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"]),
              let width = Double(rawWidth),
              width > 0 else {
            return nil
        }
        return CGFloat(width)
#else
        return nil
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
