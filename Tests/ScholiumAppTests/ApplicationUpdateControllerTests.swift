import Foundation
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Application updates")
struct ApplicationUpdateControllerTests {
    private let publicKey = Data(repeating: 7, count: 32).base64EncodedString()

    @Test(
        "An unconfigured or malformed release cannot start an updater",
        arguments: [
            nil, "", "not-a-public-key", Data(repeating: 7, count: 31).base64EncodedString(),
        ] as [String?])
    func missingReleaseIdentity(key: String?) {
        var info: [String: Any] = ["SUFeedURL": "https://aaronlves.github.io/Scholium/appcast.xml"]
        info["SUPublicEDKey"] = key
        #expect(!ApplicationUpdateController.hasUpdateConfiguration(info))
    }

    @Test(
        "Release updates require HTTPS without embedded credentials",
        arguments: [
            "http://example.com/appcast.xml", "file:///appcast.xml",
            "https://user:password@example.com/appcast.xml", "not a URL",
        ])
    func rejectsUnsafeFeed(feed: String) {
        #expect(
            !ApplicationUpdateController.hasUpdateConfiguration([
                "SUPublicEDKey": publicKey, "SUFeedURL": feed, "CFBundleIdentifier": "com.scholium.app",
            ]))
    }

    @Test("A configured release supports HTTPS updates")
    func configuredRelease() {
        #expect(
            ApplicationUpdateController.hasUpdateConfiguration([
                "SUPublicEDKey": publicKey, "SUFeedURL": "https://aaronlves.github.io/Scholium/appcast.xml",
            ]))
    }

    @Test("Only the isolated QA identity can use a loopback HTTP feed")
    func isolatedFixtureFeed() {
        let info: [String: Any] = [
            "SUPublicEDKey": publicKey, "SUFeedURL": "http://127.0.0.1:8765/appcast.xml",
            "CFBundleIdentifier": "com.scholium.qa",
        ]
        #if DEBUG
            #expect(ApplicationUpdateController.hasUpdateConfiguration(info))
        #else
            #expect(!ApplicationUpdateController.hasUpdateConfiguration(info))
        #endif
        var remote = info
        remote["SUFeedURL"] = "http://example.com/appcast.xml"
        #expect(!ApplicationUpdateController.hasUpdateConfiguration(remote))
    }

    @Test("Bare test executables never start Sparkle or scheduled network checks")
    func noUpdaterInTestProcess() {
        let updates = ApplicationUpdateController()
        updates.start()
        updates.start()
        #expect(updates.updaterController == nil)
        // The menu can still explain unavailability and offer Releases.
        #expect(updates.canCheckForUpdates)
    }
}
