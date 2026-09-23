import WebKit

/// Process-local WebKit configuration shared by Scholium's read-only HTML
/// surfaces. The store is nonpersistent; CSP and scheme handlers retain
/// their narrower content boundaries on each concrete configuration.
@MainActor
enum ScholiumWebKitRuntime {
    static let nonPersistentDataStore = WKWebsiteDataStore.nonPersistent()
}
