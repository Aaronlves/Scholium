import AppKit
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Document attachment Quick Look")
struct DocumentAttachmentQuickLookPresenterTests {
    @Test("Closing native Quick Look releases access and restores document focus")
    @MainActor
    func closeReleasesAccessAndRestoresFocus() async throws {
        _ = NSApplication.shared
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Scholium-Quick-Look-\(UUID().uuidString).txt"
        )
        try Data("Synthetic Quick Look fixture.".utf8).write(
            to: fileURL,
            options: .atomic
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let lease = DocumentAttachmentPreviewLease(
            accessToken: UUID(),
            attachmentID: UUID(),
            filename: fileURL.lastPathComponent,
            fileURL: fileURL
        )
        let probe = QuickLookProbe()
        let presenter = DocumentAttachmentQuickLookPresenter()
        presenter.present(
            lease,
            releaseAccess: { token in probe.releasedToken = token },
            restoreFocus: { probe.didRestoreFocus = true }
        )
        let panel = try #require(NSApp.windows.first {
            $0.title == lease.filename && $0.isVisible
        })

        panel.cancelOperation(nil)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while probe.releasedToken == nil || !probe.didRestoreFocus {
            if clock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(probe.releasedToken == lease.accessToken)
        #expect(probe.didRestoreFocus)
        #expect(!panel.isVisible)
    }
}

@MainActor
private final class QuickLookProbe {
    var releasedToken: UUID?
    var didRestoreFocus = false
}
