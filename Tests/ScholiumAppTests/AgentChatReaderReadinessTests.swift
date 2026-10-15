import Foundation
import Testing

@testable import ScholiumApp

@Suite("Chat mounted reader readiness") @MainActor
struct AgentChatReaderReadinessTests {
    @Test("A native remount renews initial proof and rejects the departed viewport's acknowledgement and detach")
    func nativeViewportOwnership() throws {
        let session = AgentChatReadingSession()
        #expect(!session.isInitialTranscriptReady)
        let oldPresentation = UUID()
        session.beginPresentation(oldPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: oldPresentation)
        reader.ready = true
        reader.hasMeasuredLayout = true
        let old = AgentChatTranscriptViewport.View(session: session, presentationID: oldPresentation)
        session.attachViewport(old)
        let oldRequest = try #require(session.viewportRequest)
        session.acknowledge(oldRequest)
        #expect(session.isInitialTranscriptReady)
        let anchor = AgentChatReadingSession.Anchor(id: "reply", offset: -17)
        session.anchor = anchor
        session.processExpansions["progress"] = true
        session.isScrolling = true

        let currentPresentation = UUID()
        session.beginPresentation(currentPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let currentReader = AgentChatReadReply.Readiness()
        currentReader.mount(in: session, readerID: "reply", presentationID: currentPresentation)
        let current = AgentChatTranscriptViewport.View(session: session, presentationID: currentPresentation)
        session.attachViewport(current)
        #expect(!session.isScrolling)
        let request = try #require(session.viewportRequest)
        #expect(request.id != oldRequest.id && request.target == .anchor(anchor))
        #expect(!session.isInitialTranscriptReady)
        session.acknowledge(oldRequest)
        session.attachViewport(current)
        #expect(session.viewportRequest == request)
        session.isScrolling = true
        old.detach()
        session.endPresentation(oldPresentation)
        #expect(!session.attachViewport(old))
        #expect(session.viewport === current && session.isScrolling)
        #expect(session.anchor == anchor && session.processExpansions["progress"] == true)
        currentReader.ready = true
        currentReader.hasMeasuredLayout = true
        session.acknowledge(request)
        #expect(session.isInitialTranscriptReady)
        current.detach()
        #expect(session.viewport == nil && session.isInitialTranscriptReady && !session.isScrolling)
        session.endPresentation(currentPresentation)
        #expect(!session.isInitialTranscriptReady)

        // Reusing the conversation does not reuse the departed page's receipt.
        reader.unmount()
        let replacementPresentation = UUID()
        session.beginPresentation(replacementPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let replacement = AgentChatReadReply.Readiness()
        replacement.mount(in: session, readerID: "reply", presentationID: replacementPresentation)
        #expect(session.initialTranscriptPhase == .hydrating)
        replacement.ready = true
        #expect(!session.isInitialTranscriptReady)
        replacement.hasMeasuredLayout = true
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isInitialTranscriptReady)
    }

    @Test("Initial geometry includes mounted public progress, and its failure can reveal a readable fallback")
    func mountedProgressHydration() throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let progress = AgentChatReadReply.Readiness()
        progress.mount(in: session, readerID: "public-progress", presentationID: presentationID)
        let reply = AgentChatReadReply.Readiness()
        reply.mount(in: session, readerID: "reply", presentationID: presentationID)
        reply.ready = true
        reply.hasMeasuredLayout = true
        #expect(session.initialTranscriptPhase == .hydrating)
        progress.failure = "Synthetic unreadable progress"
        #expect(session.initialTranscriptPhase == .positioning)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isInitialTranscriptReady)

        let later = AgentChatReadReply.Readiness()
        later.mount(in: session, readerID: "later-progress", presentationID: presentationID)
        #expect(session.isInitialTranscriptReady)
    }

    @Test("An initial pause without a recoverable anchor still has a positioning completion path")
    func initialPauseWithoutAnchor() throws {
        let session = AgentChatReadingSession()
        session.beginPresentation(UUID())
        session.pause()
        #expect(session.position == .retaining(nil))
        session.mount(in: [])
        let request = try #require(session.viewportRequest)
        #expect(request.target == .latest && session.initialTranscriptPhase == .positioning)
        session.acknowledge(request)
        #expect(session.isInitialTranscriptReady && session.isRetainingPosition)
    }

    @Test("An unavailable anchor cannot override valid initial positioning in either native attachment order", arguments: [false, true])
    func unavailableAnchor(attachFirst: Bool) throws {
        let session = AgentChatReadingSession()
        session.anchor = .init(id: "removed-message", offset: -17)
        let presentationID = UUID()
        let viewport = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
        if attachFirst { session.attachViewport(viewport) }
        session.beginPresentation(presentationID)
        session.mount(in: ["current-message"])
        if !attachFirst { session.attachViewport(viewport) }
        let request = try #require(session.viewportRequest)
        #expect(request.target == .latest && session.position == .retaining(nil))
        session.acknowledge(request)
        #expect(session.isInitialTranscriptReady)
    }

    @Test("Loaded and measured callbacks both reach the owning session in either order", arguments: [false, true])
    func callbackOrder(readyFirst: Bool) throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)

        if readyFirst { reader.ready = true } else { reader.hasMeasuredLayout = true }
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        if readyFirst { reader.hasMeasuredLayout = true } else { reader.ready = true }
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        #expect(!session.isInitialTranscriptReady)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isInitialTranscriptReady)
    }

    @Test("Readiness before appearance is published at mount, and departure rejects subsequent callbacks")
    func callbacksBeforeMountAndAfterDeparture() {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.hasMeasuredLayout = true
        reader.ready = true
        #expect(!session.areReadersHydrated(["reply"]))
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        #expect(session.initialTranscriptPhase == .positioning)

        reader.unmount()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        reader.ready = false
        reader.updateOwner(session, readerID: "reply", presentationID: presentationID)
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)

        // Remount must publish the reader's current state, not the old receipt.
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        #expect(!session.areReadersHydrated(["reply"]))
        reader.ready = true
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)

        // A retained finalized page can remount with its existing proof. A new
        // native page's loading callback resets it before both callbacks return.
        reader.unmount()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        #expect(session.areReadersHydrated(["reply"]))
        reader.reset()
        #expect(!session.areReadersHydrated(["reply"]))
        reader.ready = true
        #expect(!session.areReadersHydrated(["reply"]))
        reader.hasMeasuredLayout = true
        #expect(session.initialTranscriptPhase == .positioning)
    }

    @Test("A replaced reader cannot publish readiness, revoke readiness, or remove its successor")
    func replacementRejectsDepartedPublisher() {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let old = AgentChatReadReply.Readiness()
        old.mount(in: session, readerID: "reply", presentationID: presentationID)
        old.ready = true
        old.hasMeasuredLayout = true
        #expect(session.initialTranscriptPhase == .positioning)

        let current = AgentChatReadReply.Readiness()
        current.mount(in: session, readerID: "reply", presentationID: presentationID)
        #expect(session.initialTranscriptPhase == .hydrating)
        old.reset()
        old.ready = true
        old.hasMeasuredLayout = true
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)

        current.hasMeasuredLayout = true
        current.ready = true
        #expect(session.areReadersHydrated(["reply"]))
        old.reset()
        old.unmount()
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        current.unmount()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
    }

    @Test("Failure fallback can hydrate, but retry and loading revoke readiness until both callbacks return")
    func failureAndReload() throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        reader.failure = "Synthetic unavailable reader"
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        let request = try #require(session.viewportRequest)

        reader.reset()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        #expect(session.viewportRequest == request)
        reader.hasMeasuredLayout = true
        #expect(!session.areReadersHydrated(["reply"]))
        reader.ready = true
        #expect(session.initialTranscriptPhase == .positioning)
        session.acknowledge(request)
        #expect(session.isInitialTranscriptReady)

        // A later reload keeps the readable transcript mounted, while its
        // current reader receipt must still report that it is not hydrated.
        reader.reset()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.isInitialTranscriptReady)
    }

    @Test("DOM measurement and applied reader size must agree, and reset requires a fresh measurement", arguments: [false, true])
    func appliedReaderLayout(measureFirst: Bool) {
        let reader = AgentChatReadReply.Readiness()
        let initial = CGSize(width: 320, height: 180)
        reader.ready = true
        if measureFirst {
            reader.measureLayout(height: initial.height, viewportWidth: initial.width)
        } else {
            reader.applyLayout(initial)
        }
        #expect(!reader.layoutIsApplied, "Neither a DOM measurement nor a SwiftUI size alone proves the final reader layout")

        if measureFirst {
            reader.applyLayout(initial)
        } else {
            reader.measureLayout(height: initial.height, viewportWidth: initial.width)
        }
        #expect(reader.isHydrated && reader.layoutIsApplied)
        reader.applyLayout(CGSize(width: 288, height: initial.height))
        #expect(!reader.layoutIsApplied, "A height match cannot authorize a page measured at another width")
        reader.applyLayout(CGSize(width: initial.width, height: 220))
        #expect(!reader.layoutIsApplied, "A width match cannot authorize a height that SwiftUI has not applied")
        reader.applyLayout(initial)
        #expect(reader.layoutIsApplied)

        reader.reset()
        #expect(!reader.isHydrated && !reader.layoutIsApplied)
        reader.ready = true
        reader.applyLayout(initial)
        #expect(!reader.isHydrated && !reader.layoutIsApplied, "A retained applied size must not replace the new page's DOM measurement")
        let resized = CGSize(width: 288, height: 240)
        reader.measureLayout(height: resized.height, viewportWidth: resized.width)
        #expect(reader.isHydrated && !reader.layoutIsApplied)
        reader.applyLayout(resized)
        #expect(reader.layoutIsApplied)
        reader.clearAppliedLayout()
        reader.measureLayout(height: resized.height, viewportWidth: resized.width)
        #expect(reader.isHydrated && !reader.layoutIsApplied, "A fresh native mount must receive its own applied layout receipt")
        reader.applyLayout(resized)
        #expect(reader.layoutIsApplied)
    }

    @Test("Fitted readers wait for their intended short width while long content may wrap at the parent width")
    func fittedReaderLayout() {
        let reader = AgentChatReadReply.Readiness()
        reader.ready = true
        reader.applyLayout(CGSize(width: 300, height: 60))
        reader.measureLayout(height: 60, viewportWidth: 300, maximumWidth: 36)
        #expect(reader.isHydrated && !reader.layoutIsApplied, "Matching old full-width receipts cannot reveal a reader that still needs to shrink")

        reader.measureLayout(height: 60, viewportWidth: 36, maximumWidth: 36)
        #expect(!reader.layoutIsApplied, "The narrow DOM measurement must also reach the native frame")
        reader.applyLayout(CGSize(width: 36, height: 60))
        #expect(reader.layoutIsApplied)

        reader.measureLayout(height: 180, viewportWidth: 300, maximumWidth: 900)
        reader.applyLayout(CGSize(width: 300, height: 180))
        #expect(reader.layoutIsApplied, "Content wider than its parent may settle at the available width with wrapping")
    }

    enum HistoryPageExit: String, CaseIterable, Sendable {
        case latest
        case navigate
        case endPresentation
        case newPresentation
        case removeStagedItem
    }

    @Test("Cancelling prepared history restores its presented range before applying the next action", arguments: HistoryPageExit.allCases)
    func pendingHistoryCancellation(exit: HistoryPageExit) throws {
        let ids = (0..<80).map { "message-\($0)" }
        let presentationID = UUID()
        let session = AgentChatReadingSession()
        session.beginPresentation(presentationID)
        session.mount(in: ids)
        session.acknowledge(try #require(session.viewportRequest))
        let presented = Array(ids.suffix(4))
        let previous = session.history
        let anchor = AgentChatReadingSession.Anchor(id: ids[78], offset: -17)
        session.anchor = anchor
        session.page(earlier: true, in: ids, readerIDs: Set(ids))
        let pending = try #require(session.pendingHistoryPage)
        #expect(pending.previous == previous)
        #expect(pending.itemIDs == Set(ids[52..<76]))
        #expect(pending.readerIDs == pending.itemIDs)
        #expect(Array(ids[session.pagingRange(in: ids)]) == presented)
        #expect(Array(ids[session.history.range(in: ids)]) == Array(ids[52..<80]))

        switch exit {
        case .latest:
            session.latest(in: ids)
            #expect(Array(ids[session.history.range(in: ids)]) == presented)
            #expect(session.position == .followingLatest && session.viewportRequest?.target == .latest)
        case .navigate:
            // The target belongs to the uncommitted page. Restore the old
            // window before revealing it, rather than exposing that whole page.
            session.navigate(to: ids[60], in: ids)
            #expect(Array(ids[session.history.range(in: ids)]) == Array(ids[48..<72]))
            let target = AgentChatReadingSession.Anchor(id: ids[60], offset: 0)
            #expect(session.anchor == target && session.viewportRequest?.target == .anchor(target))
        case .endPresentation:
            session.endPresentation(presentationID)
            #expect(session.history == previous)
            #expect(session.initialTranscriptPhase == .unmounted && session.viewportRequest == nil)
        case .newPresentation:
            let successor = UUID()
            session.beginPresentation(successor)
            #expect(session.history == previous && session.ownsPresentation(successor))
            session.endPresentation(presentationID)
            #expect(session.history == previous && session.ownsPresentation(successor))
        case .removeStagedItem:
            let remaining = ids.filter { $0 != ids[60] }
            session.contentDidChange(in: remaining, readerIDs: Set(remaining))
            #expect(session.history == previous)
            #expect(Array(remaining[session.history.range(in: remaining)]) == presented)
            #expect(session.anchor == anchor)
        }
        #expect(session.pendingHistoryPage == nil, "The cancelled page must not survive to publish a late preparation receipt")
    }

    @Test("A retained root preserves uncommitted history, while content revisions refresh only its expected readers")
    func retainedPendingHistory() throws {
        let ids = (0..<60).map { "message-\($0)" }
        let presentationID = UUID()
        let session = AgentChatReadingSession()
        session.beginPresentation(presentationID)
        session.mount(in: ids)
        session.acknowledge(try #require(session.viewportRequest))
        let previous = session.history
        let anchor = AgentChatReadingSession.Anchor(id: ids[58], offset: -23)
        session.anchor = anchor
        session.page(earlier: true, in: ids, readerIDs: Set(ids))
        let pending = try #require(session.pendingHistoryPage)
        let requested = session.history

        session.setPresentationActive(false, for: presentationID)
        session.endUserScroll()
        #expect(session.ownsPresentation(presentationID) && session.isPresentationReady(presentationID))
        #expect(session.pendingHistoryPage?.itemIDs == pending.itemIDs)
        #expect(session.history == requested && session.anchor == anchor)
        #expect(Array(ids[session.pagingRange(in: ids)]) == Array(ids[previous.range(in: ids)]))
        session.setPresentationActive(true, for: presentationID)
        #expect(session.pendingHistoryPage?.itemIDs == pending.itemIDs && session.history == requested)

        let revisedReaderIDs = Set(ids.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
        session.contentDidChange(in: ids, readerIDs: revisedReaderIDs)
        #expect(session.pendingHistoryPage?.itemIDs == pending.itemIDs)
        #expect(session.pendingHistoryPage?.readerIDs == revisedReaderIDs.intersection(pending.itemIDs))
        #expect(session.history == requested && session.anchor == anchor)
    }

    @Test("Rebinding a mounted reader removes only its own old receipt and keeps sessions independent")
    func ownerAndIdentityChanges() {
        let first = AgentChatReadingSession()
        let second = AgentChatReadingSession()
        let firstPresentation = UUID()
        let secondPresentation = UUID()
        first.beginPresentation(firstPresentation)
        second.beginPresentation(secondPresentation)
        first.mount(in: ["old"], readerIDs: ["old"])
        second.mount(in: ["new"], readerIDs: ["new"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: first, readerID: "old", presentationID: firstPresentation)
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(first.areReadersHydrated(["old"]))

        reader.updateOwner(second, readerID: "new", presentationID: secondPresentation)
        #expect(!first.areReadersHydrated(["old"]))
        #expect(first.initialTranscriptPhase == .hydrating)
        #expect(second.areReadersHydrated(["new"]))
        reader.updateOwner(second, readerID: "renamed", presentationID: secondPresentation)
        #expect(!second.areReadersHydrated(["new"]))
        #expect(second.areReadersHydrated(["renamed"]))
        #expect(second.initialTranscriptPhase == .hydrating)
        reader.unmount()
        #expect(!second.areReadersHydrated(["renamed"]))
    }

    @Test("A reader registered before or after its parent begins belongs to that presentation", arguments: [false, true])
    func registrationBeforeOrAfterParent(registerFirst: Bool) throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        let reader = AgentChatReadReply.Readiness()
        reader.ready = true
        reader.hasMeasuredLayout = true
        if registerFirst {
            reader.mount(in: session, readerID: "reply", presentationID: presentationID)
            #expect(!session.isInitialTranscriptReady)
            #expect(!session.areReadersHydrated(["reply"]), "A receipt cannot authorize a page that has not begun")
        }
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        if !registerFirst {
            #expect(session.initialTranscriptPhase == .hydrating)
            reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        }
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isPresentationReady(presentationID))
    }

    @Test("A departed root's late mount, update and removal cannot affect its successor's readers")
    func successorRejectsDepartedRootReceipts() throws {
        let session = AgentChatReadingSession()
        let oldPresentation = UUID()
        session.beginPresentation(oldPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let old = AgentChatReadReply.Readiness()
        old.mount(in: session, readerID: "reply", presentationID: oldPresentation)
        old.ready = true
        old.hasMeasuredLayout = true
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isPresentationReady(oldPresentation))

        let currentPresentation = UUID()
        session.beginPresentation(currentPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        #expect(!session.areReadersHydrated(["reply"]), "The old root's valid reader cannot hydrate a new root")
        let current = AgentChatReadReply.Readiness()
        current.mount(in: session, readerID: "reply", presentationID: currentPresentation)
        old.mount(in: session, readerID: "reply", presentationID: oldPresentation)
        old.reset()
        old.ready = true
        old.hasMeasuredLayout = true
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)

        let departedOnly = AgentChatReadReply.Readiness()
        departedOnly.mount(in: session, readerID: "departed-public-progress", presentationID: oldPresentation)
        current.ready = true
        current.hasMeasuredLayout = true
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning, "An unready reader belonging to another root cannot block current geometry")
        let lateReplacement = AgentChatReadReply.Readiness()
        lateReplacement.mount(in: session, readerID: "reply", presentationID: oldPresentation)
        #expect(session.areReadersHydrated(["reply"]), "An old root's fresh instance cannot replace the current root's receipt")
        lateReplacement.failure = "Synthetic departed failure"
        old.unmount()
        lateReplacement.unmount()
        departedOnly.unmount()
        session.endPresentation(oldPresentation)
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isPresentationReady(currentPresentation))
    }

    @Test("Ending a root revokes its reader receipts and late callbacks cannot revive initial proof")
    func presentationEndRevokesReceipts() throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        reader.ready = true
        reader.hasMeasuredLayout = true
        session.acknowledge(try #require(session.viewportRequest))
        session.endPresentation(presentationID)
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .unmounted && session.viewportRequest == nil)
        reader.reset()
        reader.failure = "Synthetic late failure"
        reader.ready = true
        reader.hasMeasuredLayout = true
        reader.updateOwner(session, readerID: "reply", presentationID: presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .unmounted, "Mounting messages alone does not begin a new presentation")

        let successor = UUID()
        session.beginPresentation(successor)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        reader.reset()
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        reader.unmount()
        session.endPresentation(presentationID)
        #expect(session.initialTranscriptPhase == .hydrating)
    }

    @Test("Hiding and reattaching the same retained root preserves its mounted reader proof")
    func retainedRootPreservesReceipts() throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        reader.ready = true
        reader.hasMeasuredLayout = true
        let viewport = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
        #expect(session.attachViewport(viewport))
        session.acknowledge(try #require(session.viewportRequest))
        viewport.detach()
        #expect(session.viewport == nil)
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))

        // Back retains this root. It does not execute endPresentation, nor does
        // native attachment renew the already measured page's reader lifetime.
        session.beginPresentation(presentationID)
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        #expect(session.attachViewport(viewport))
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))
        #expect(reader.ready && reader.hasMeasuredLayout)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isPresentationReady(presentationID))
        viewport.detach()
    }

    @Test("A missing presentation identity cannot register or publish a transcript reader")
    func missingPresentationIsNonAuthorizing() {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: nil)
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(reader.isHydrated && !session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        reader.updateOwner(session, readerID: "reply", presentationID: presentationID)
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        reader.updateOwner(session, readerID: "reply", presentationID: nil)
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        reader.updateOwner(session, readerID: nil, presentationID: presentationID)
        #expect(!session.areReadersHydrated(["reply"]))
        reader.unmount()
    }

    @Test("Changing only the presentation identity rebinds a mounted reader within its retained conversation")
    func readerRebindsWithinConversation() {
        let session = AgentChatReadingSession()
        let oldPresentation = UUID()
        session.beginPresentation(oldPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: oldPresentation)
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(session.areReadersHydrated(["reply"]))
        let currentPresentation = UUID()
        reader.updateOwner(session, readerID: "reply", presentationID: currentPresentation)
        #expect(!session.areReadersHydrated(["reply"]), "Rebinding must withdraw the old root's receipt")
        session.beginPresentation(currentPresentation)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)
        session.endPresentation(oldPresentation)
        #expect(session.areReadersHydrated(["reply"]))
        reader.unmount()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
    }

    @Test("Queued reader interaction is admitted only by its current mounted and enabled owner")
    func queuedInteractionRequiresCurrentOwner() {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(!reader.acceptsInteraction, "Mounting alone does not enable a queued menu")
        reader.interactionIsEnabled = true
        #expect(reader.acceptsInteraction)

        // Back keeps the native page and its receipt. Work already queued by
        // that page must still check the current interaction gate at execution.
        reader.interactionIsEnabled = false
        #expect(!reader.acceptsInteraction)
        #expect(session.areReadersHydrated(["reply"]))
        reader.interactionIsEnabled = true
        #expect(reader.acceptsInteraction && session.areReadersHydrated(["reply"]))

        let sameRootReplacement = AgentChatReadReply.Readiness()
        sameRootReplacement.mount(in: session, readerID: "reply", presentationID: presentationID)
        sameRootReplacement.ready = true
        sameRootReplacement.hasMeasuredLayout = true
        sameRootReplacement.interactionIsEnabled = true
        #expect(!reader.acceptsInteraction, "The replaced native reader cannot reuse its successor's matching root identity")
        #expect(sameRootReplacement.acceptsInteraction && session.areReadersHydrated(["reply"]))

        let successor = UUID()
        session.beginPresentation(successor)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        #expect(!reader.acceptsInteraction, "An enabled reader belonging to the departed root cannot open its queued menu")
        #expect(!sameRootReplacement.acceptsInteraction, "The departed root's latest native reader cannot act in the successor")
        let current = AgentChatReadReply.Readiness()
        current.mount(in: session, readerID: "reply", presentationID: successor)
        current.interactionIsEnabled = true
        #expect(current.acceptsInteraction)
        reader.unmount()
        sameRootReplacement.unmount()
        #expect(!reader.acceptsInteraction && current.acceptsInteraction)
        current.unmount()
        #expect(!current.acceptsInteraction, "A queued callback cannot authorize interaction after native departure")

        let standalone = AgentChatReadReply.Readiness()
        standalone.mount(in: nil, readerID: nil, presentationID: nil)
        #expect(!standalone.acceptsInteraction)
        standalone.interactionIsEnabled = true
        #expect(standalone.acceptsInteraction, "A mounted standalone preview has no transcript owner to require")
        standalone.unmount()
        #expect(!standalone.acceptsInteraction)

        let missingScope = AgentChatReadReply.Readiness()
        missingScope.mount(in: session, readerID: "reply", presentationID: nil)
        missingScope.interactionIsEnabled = true
        #expect(!missingScope.acceptsInteraction, "A transcript with missing scope cannot acquire standalone permission")
        missingScope.mount(in: nil, readerID: "reply", presentationID: successor)
        #expect(!missingScope.acceptsInteraction, "A transcript with a missing session cannot acquire standalone permission")
        missingScope.unmount()
    }

    @Test("A same-root native viewport replacement retires only the departed instance")
    func sameRootViewportHandoffRetiresDepartedInstance() throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply", presentationID: presentationID)
        reader.ready = true
        reader.hasMeasuredLayout = true
        let old = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
        #expect(session.attachViewport(old))
        session.acknowledge(try #require(session.viewportRequest))
        let current = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
        #expect(session.attachViewport(current))
        #expect(old.isRetired && !current.isRetired)
        let currentRequest = try #require(session.viewportRequest)
        #expect(!session.attachViewport(old), "The same root token cannot revive a replaced native viewport")
        old.connectIfNeeded()
        old.detach()
        #expect(session.viewport === current && session.viewportRequest == currentRequest)
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))

        current.detach()
        #expect(!current.isRetired && session.viewport == nil)
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))
        #expect(session.attachViewport(current), "Ordinary native reparenting preserves the reusable instance")
        #expect(session.viewport === current && !current.isRetired)
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))

        AgentChatTranscriptViewport.dismantleNSView(current, coordinator: ())
        #expect(current.isRetired && session.viewport == nil)
        let replacement = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
        #expect(session.attachViewport(replacement))
        let replacementRequest = try #require(session.viewportRequest)
        #expect(!session.attachViewport(current), "Dismantled representables cannot reacquire their former root")
        current.connectIfNeeded()
        current.detach()
        #expect(session.viewport === replacement && session.viewportRequest == replacementRequest)
        #expect(session.isPresentationReady(presentationID) && session.areReadersHydrated(["reply"]))
        replacement.detach()
        reader.unmount()
        session.endPresentation(presentationID)
    }
}
