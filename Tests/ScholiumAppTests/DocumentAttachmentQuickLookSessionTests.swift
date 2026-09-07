import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("System Quick Look access")
@MainActor
struct DocumentAttachmentQuickLookSessionTests {
    @Test("Replacing and dismissing system previews releases each lease once")
    func boundedPreviewAccess() async throws {
        let first = lease("First.pdf")
        let second = lease("Second.pdf")
        var released: [UUID] = []
        let session = DocumentAttachmentQuickLookSession()
        session.present(first, releaseAccess: { released.append($0) })
        #expect(session.url == first.fileURL)
        #expect(released.isEmpty)
        session.present(second, releaseAccess: { released.append($0) })
        #expect(session.url == second.fileURL)
        session.dismiss()
        session.dismiss()
        #expect(session.url == nil)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while released.count < 2 && clock.now < deadline { await Task.yield() }
        #expect(released.count == 2)
        #expect(Set(released) == [first.accessToken, second.accessToken])
    }

    private func lease(_ filename: String) -> DocumentAttachmentPreviewLease {
        .init(accessToken: UUID(), attachmentID: UUID(), filename: filename,
              fileURL: URL(fileURLWithPath: "/synthetic/\(filename)"))
    }
}
