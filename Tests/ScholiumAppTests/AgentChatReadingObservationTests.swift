import Foundation
import Observation
import Synchronization
import Testing

@testable import ScholiumApp

@Suite("Chat semantic reading observations") @MainActor
struct AgentChatReadingObservationTests {
    @Test("Native anchor offsets retain precision without invalidating the reading-mode subscription")
    func readingModeIgnoresOffsetChanges() {
        let session = AgentChatReadingSession()
        session.anchor = .init(id: "first", offset: -0.0625)
        let invalidations = Mutex(0)
        withObservationTracking {
            #expect(session.isRetainingPosition)
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }

        for step in 1...160 {
            let anchor = AgentChatReadingSession.Anchor(id: "first", offset: -CGFloat(step) / 16)
            session.anchor = anchor
            #expect(session.anchor == anchor)
            #expect(session.position == .retaining(anchor))
        }
        session.anchor = .init(id: "second", offset: 17.8125)
        session.position = .retaining(nil)
        #expect(session.isRetainingPosition && session.anchor == nil)
        #expect(invalidations.withLock { $0 } == 0)

        // The same one-shot subscription must still be armed after every
        // unrelated offset/row change, and fire for the actual mode change.
        session.latest(in: ["first", "second"])
        #expect(!session.isRetainingPosition && session.position == .followingLatest)
        #expect(invalidations.withLock { $0 } == 1)
    }

    @Test("Outline location observes semantic row identity without subscribing to its native offset")
    func readingItemIgnoresOffsetChanges() {
        let session = AgentChatReadingSession()
        session.anchor = .init(id: "first", offset: 0)
        let invalidations = Mutex(0)
        withObservationTracking {
            #expect(session.currentReadingItemID == "first")
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }

        for step in 1...160 {
            let anchor = AgentChatReadingSession.Anchor(id: "first", offset: CGFloat(step) / 32)
            session.position = .retaining(anchor)
            #expect(session.anchor == anchor && session.currentReadingItemID == "first")
        }
        #expect(invalidations.withLock { $0 } == 0)

        session.anchor = .init(id: "second", offset: -193.34375)
        #expect(session.currentReadingItemID == "second")
        #expect(session.anchor == .init(id: "second", offset: -193.34375))
        #expect(invalidations.withLock { $0 } == 1)
    }

    @Test("An unknown retained anchor remains a reading mode, and resolving its row updates only row identity")
    func unknownAnchorAndLatest() {
        let session = AgentChatReadingSession()
        #expect(session.position == .followingLatest && !session.isRetainingPosition)
        #expect(session.anchor == nil && session.currentReadingItemID == nil)
        let modeInvalidations = Mutex(0)
        let itemInvalidations = Mutex(0)
        withObservationTracking {
            _ = session.isRetainingPosition
        } onChange: {
            modeInvalidations.withLock { $0 += 1 }
        }
        withObservationTracking {
            _ = session.currentReadingItemID
        } onChange: {
            itemInvalidations.withLock { $0 += 1 }
        }

        session.pause()
        #expect(session.position == .retaining(nil) && session.isRetainingPosition)
        #expect(session.anchor == nil && session.currentReadingItemID == nil)
        #expect(modeInvalidations.withLock { $0 } == 1)
        #expect(itemInvalidations.withLock { $0 } == 0)

        session.anchor = .init(id: "resolved", offset: -71.15625)
        #expect(session.isRetainingPosition && session.currentReadingItemID == "resolved")
        #expect(itemInvalidations.withLock { $0 } == 1)

        session.latest(in: ["resolved", "newest"])
        #expect(session.position == .followingLatest && !session.isRetainingPosition)
        #expect(session.anchor == nil && session.currentReadingItemID == nil)
        #expect(session.viewportRequest?.target == .latest)
    }
}
