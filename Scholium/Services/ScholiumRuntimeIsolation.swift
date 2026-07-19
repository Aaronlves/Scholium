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

    /// Returns an explicitly requested QA viewport without coupling window
    /// geometry to whether automation preconfigures a fixture workspace.
    static func windowWidth(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> CGFloat? {
#if DEBUG
        guard bundleIdentifier == qaBundleIdentifier,
              let rawWidth = nonempty(environment["SCHOLIUM_UI_TEST_WINDOW_WIDTH"]),
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
