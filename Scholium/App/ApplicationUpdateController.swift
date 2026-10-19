import AppKit
import Combine
import Sparkle
import SwiftUI

/// Owns the process-wide updater. Sparkle requests normal application
/// termination; the App delegate remains the only owner of save/quit admission.
@MainActor
final class ApplicationUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    private(set) var updaterController: SPUStandardUpdaterController?
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // Bare SwiftPM executables, tests and unconfigured development bundles
        // must not start network checks or manufacture a release identity.
        guard Bundle.main.bundleURL.pathExtension == "app",
            Self.hasUpdateConfiguration(Bundle.main.infoDictionary ?? [:])
        else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        if let updaterController {
            updaterController.checkForUpdates(nil)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = ScholiumL10n.string("Updates Unavailable")
        alert.informativeText = ScholiumL10n.string(
            "Updates are unavailable in this build. Download the latest version from Scholium Releases.")
        alert.addButton(withTitle: ScholiumL10n.string("Open Releases"))
        alert.addButton(withTitle: ScholiumL10n.string("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/Aaronlves/Scholium/releases")!)
        }
    }

    static func hasUpdateConfiguration(_ info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String,
            let decoded = Data(base64Encoded: key), decoded.count == 32,
            let feed = info["SUFeedURL"] as? String,
            let url = URL(string: feed), url.host != nil,
            url.user == nil, url.password == nil
        else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
            // Only the isolated QA identity can consume a local test feed.
            return info["CFBundleIdentifier"] as? String == "com.scholium.qa"
                && url.scheme == "http" && url.host == "127.0.0.1"
        #else
            return false
        #endif
    }
}

struct ApplicationUpdateMenuItem: View {
    @ObservedObject var updates: ApplicationUpdateController

    var body: some View {
        Button("Check for Updates…", action: updates.checkForUpdates)
            .disabled(!updates.canCheckForUpdates)
    }
}
