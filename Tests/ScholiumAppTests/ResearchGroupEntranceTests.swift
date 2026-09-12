import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research group entrance") @MainActor
struct ResearchGroupEntranceTests {
    private let vault = UUID()
    private func note(_ name: String) -> VaultQualifiedNoteID {
        .init(vaultID: vault, relativePath: name)
    }

    @Test func staggerUsesNoteIdentityAndOneBatchClock() {
        let now = Date(timeIntervalSince1970: 100)
        let notes = (0..<6).map { note("\($0).md") }
        var entrance = ResearchGroupEntrance()
        entrance.update(notes, at: now, reduceMotion: false)
        #expect(entrance.progress(for: notes[0], at: now) == 0)
        #expect(entrance.progress(for: notes[0], at: now.addingTimeInterval(0.03)) > 0)
        #expect(entrance.progress(for: notes[1], at: now.addingTimeInterval(0.03)) == 0)
        #expect(entrance.progress(for: notes[5], at: now.addingTimeInterval(0.59)) == 1)
        #expect(abs(entrance.deadline!.timeIntervalSince(now) - 0.58) < 0.00001)
    }

    @Test func updatingExistingNotesDoesNotRestartTheirEntrance() {
        let now = Date(timeIntervalSince1970: 100)
        let a = note("A.md")
        let b = note("B.md")
        var entrance = ResearchGroupEntrance()
        entrance.update([a], at: now, reduceMotion: false)
        let later = now.addingTimeInterval(0.12)
        let before = entrance.progress(for: a, at: later)
        entrance.update([a, b], at: later, reduceMotion: false)
        #expect(entrance.progress(for: a, at: later) == before)
        #expect(entrance.progress(for: b, at: later) == 0)
        entrance.finish()
        entrance.update([a, b], at: later.addingTimeInterval(1), reduceMotion: false)
        #expect(entrance.deadline == nil)
        #expect(entrance.progress(for: a, at: later) == 1)
    }

    @Test func reduceMotionCompletesWithoutReplayingOnTheSameResults() {
        let now = Date(timeIntervalSince1970: 100)
        let a = note("A.md")
        var entrance = ResearchGroupEntrance()
        entrance.update([a], at: now, reduceMotion: false)
        entrance.finish()
        entrance.update([a], at: now, reduceMotion: true)
        entrance.update([a], at: now, reduceMotion: false)
        #expect(entrance.deadline == nil)
        #expect(entrance.progress(for: a, at: now) == 1)
    }
}
