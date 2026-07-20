import Foundation

/// Resolves explicit test isolation first, then a safe home for the disposable
/// QA bundle. A fixture is opened only when automation supplies it explicitly.
enum ScholiumRuntimeIsolation {
    static let qaBundleIdentifier = "com.scholium.qa"
    // Keep this exact path synchronized with build-qa-app.sh so every rebuild
    // clears the state that a manually launched QA bundle will actually use.
    static let defaultQAHomeURL = URL(
        fileURLWithPath: "/tmp/scholium-workbench-home",
        isDirectory: true
    )

    static func homeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        qaHomeURL: URL = defaultQAHomeURL
    ) -> URL? {
        if let explicit = nonempty(environment["SCHOLIUM_HOME"]) {
            return URL(
                fileURLWithPath: (explicit as NSString).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL
        }
#if DEBUG
        if bundleIdentifier == qaBundleIdentifier {
            return qaHomeURL.standardizedFileURL
        }
#endif
        return nil
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

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
