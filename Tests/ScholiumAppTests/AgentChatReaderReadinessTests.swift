import Foundation
import Testing

@testable import ScholiumApp

@Suite("Chat mounted reader readiness") @MainActor
struct AgentChatReaderReadinessTests {
    @Test("Loaded and measured callbacks both reach the owning session in either order", arguments: [false, true])
    func callbackOrder(readyFirst: Bool) throws {
        let session = AgentChatReadingSession()
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply")

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
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.hasMeasuredLayout = true
        reader.ready = true
        #expect(!session.areReadersHydrated(["reply"]))
        reader.mount(in: session, readerID: "reply")
        #expect(session.initialTranscriptPhase == .positioning)

        reader.unmount()
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)
        reader.ready = false
        reader.updateOwner(session, readerID: "reply")
        #expect(!session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .hydrating)

        // Remount must publish the reader's current state, not the old receipt.
        reader.mount(in: session, readerID: "reply")
        #expect(!session.areReadersHydrated(["reply"]))
        reader.ready = true
        #expect(session.areReadersHydrated(["reply"]))
        #expect(session.initialTranscriptPhase == .positioning)

        // A retained finalized page can remount with its existing proof. A new
        // native page's loading callback resets it before both callbacks return.
        reader.unmount()
        reader.mount(in: session, readerID: "reply")
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
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let old = AgentChatReadReply.Readiness()
        old.mount(in: session, readerID: "reply")
        old.ready = true
        old.hasMeasuredLayout = true
        #expect(session.initialTranscriptPhase == .positioning)

        let current = AgentChatReadReply.Readiness()
        current.mount(in: session, readerID: "reply")
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
        session.mount(in: ["reply"], readerIDs: ["reply"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: session, readerID: "reply")
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

    @Test("Rebinding a mounted reader removes only its own old receipt and keeps sessions independent")
    func ownerAndIdentityChanges() {
        let first = AgentChatReadingSession()
        let second = AgentChatReadingSession()
        first.mount(in: ["old"], readerIDs: ["old"])
        second.mount(in: ["new"], readerIDs: ["new"])
        let reader = AgentChatReadReply.Readiness()
        reader.mount(in: first, readerID: "old")
        reader.ready = true
        reader.hasMeasuredLayout = true
        #expect(first.areReadersHydrated(["old"]))

        reader.updateOwner(second, readerID: "new")
        #expect(!first.areReadersHydrated(["old"]))
        #expect(first.initialTranscriptPhase == .hydrating)
        #expect(second.areReadersHydrated(["new"]))
        reader.updateOwner(second, readerID: "renamed")
        #expect(!second.areReadersHydrated(["new"]))
        #expect(second.areReadersHydrated(["renamed"]))
        #expect(second.initialTranscriptPhase == .hydrating)
        reader.unmount()
        #expect(!second.areReadersHydrated(["renamed"]))
    }
}
