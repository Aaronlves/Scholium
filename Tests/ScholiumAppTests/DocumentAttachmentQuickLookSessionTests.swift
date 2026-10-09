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
        session.prepare(
            isCurrent: { true }, acquire: { .init(lease: first, releaseAccess: { released.append($0) }) },
            onFailure: { _ in Issue.record("First preview failed") }, returnFocus: {})
        await waitUntil { session.url == first.fileURL }
        #expect(session.url == first.fileURL)
        #expect(released.isEmpty)
        session.prepare(
            isCurrent: { true }, acquire: { .init(lease: second, releaseAccess: { released.append($0) }) },
            onFailure: { _ in Issue.record("Second preview failed") }, returnFocus: {})
        await waitUntil { session.url == second.fileURL }
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

    @Test("A superseded acquisition releases late access and cannot replace the current preview")
    func supersededPreparation() async throws {
        let session = DocumentAttachmentQuickLookSession()
        let old = lease("Old.png")
        let current = lease("Current.png")
        var resumeOld: CheckedContinuation<DocumentAttachmentPreviewAccess, Never>?
        var released: [UUID] = []
        var focusReturns = 0
        session.prepare(
            isCurrent: { true },
            acquire: {
                await withCheckedContinuation { resumeOld = $0 }
            },
            onFailure: { _ in
                Issue.record("Cancelled preparation reported an error")
            }, returnFocus: { Issue.record("Superseded preview returned focus") })
        await waitUntil { resumeOld != nil }
        session.prepare(
            isCurrent: { true }, acquire: { .init(lease: current, releaseAccess: { released.append($0) }) },
            onFailure: { _ in Issue.record("Current preview failed") },
            returnFocus: { focusReturns += 1 })
        await waitUntil { session.url == current.fileURL }
        resumeOld?.resume(returning: .init(lease: old, releaseAccess: { released.append($0) }))
        await waitUntil { released.contains(old.accessToken) }
        #expect(session.url == current.fileURL)
        #expect(released == [old.accessToken])
        session.dismiss()
        session.dismiss()
        await waitUntil { released.count == 2 }
        #expect(focusReturns == 1)
        #expect(Set(released) == [old.accessToken, current.accessToken])
    }

    @Test("Dismissal and context changes reject pending previews without focus or error")
    func cancelledPreparation() async throws {
        for dismiss in [true, false] {
            let session = DocumentAttachmentQuickLookSession()
            let pending = lease("Pending.png")
            var resume: CheckedContinuation<DocumentAttachmentPreviewAccess, Never>?
            var isCurrent = true
            var released: [UUID] = []
            session.prepare(
                isCurrent: { isCurrent },
                acquire: {
                    await withCheckedContinuation { resume = $0 }
                }, onFailure: { _ in Issue.record("Stale preview reported an error") },
                returnFocus: { Issue.record("Invisible preview returned focus") })
            await waitUntil { resume != nil }
            if dismiss { session.dismiss() } else { isCurrent = false }
            resume?.resume(returning: .init(lease: pending, releaseAccess: { released.append($0) }))
            await waitUntil { released.count == 1 }
            #expect(session.url == nil)
            #expect(released == [pending.accessToken])
            session.dismiss()
        }
    }

    @Test("Current failures report once and teardown does not restore focus")
    func failureAndTeardown() async throws {
        let session = DocumentAttachmentQuickLookSession()
        var failures = 0
        var released: [UUID] = []
        session.prepare(
            isCurrent: { true }, acquire: { throw CocoaError(.fileReadNoSuchFile) },
            onFailure: { _ in failures += 1 },
            returnFocus: { Issue.record("Failed preview returned focus") })
        await waitUntil { failures == 1 }
        #expect(session.url == nil)
        #expect(released.isEmpty)
        let visible = lease("Visible.png")
        session.prepare(
            isCurrent: { true }, acquire: { .init(lease: visible, releaseAccess: { released.append($0) }) },
            onFailure: { _ in failures += 1 },
            returnFocus: { Issue.record("Teardown stole focus") })
        await waitUntil { session.url != nil }
        session.dismiss(restoringFocus: false)
        await waitUntil { released.count == 1 }
        #expect(failures == 1)
        #expect(released == [visible.accessToken])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline { await Task.yield() }
        #expect(condition())
    }

    private func lease(_ filename: String) -> DocumentAttachmentPreviewLease {
        .init(
            accessToken: UUID(), attachmentID: UUID(), filename: filename,
            fileURL: URL(fileURLWithPath: "/synthetic/\(filename)"))
    }
}
