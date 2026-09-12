import ScholiumContracts
import SwiftUI

/// Presentation-only batch clock. All native rows of a Note receive one sample.
struct ResearchGroupEntrance {
    private var visible: Set<VaultQualifiedNoteID> = []
    private var starts: [VaultQualifiedNoteID: Date] = [:]
    private(set) var deadline: Date?

    mutating func update(_ notes: [VaultQualifiedNoteID], at now: Date, reduceMotion: Bool) {
        let incoming = Set(notes)
        starts = starts.filter { incoming.contains($0.key) }
        let added = notes.filter { !visible.contains($0) }
        visible = incoming
        guard !reduceMotion else {
            finish()
            return
        }
        for (index, note) in added.enumerated() {
            starts[note] = now.addingTimeInterval(Double(index) * 0.06)
        }
        deadline = starts.values.map { $0.addingTimeInterval(0.28) }.max()
        if let deadline, deadline <= now { finish() }
    }

    func progress(for note: VaultQualifiedNoteID, at now: Date) -> CGFloat {
        guard let start = starts[note] else { return 1 }
        let elapsed = min(1, max(0, now.timeIntervalSince(start) / 0.28))
        return 1 - pow(1 - elapsed, 3)
    }

    mutating func finish() {
        starts = [:]
        deadline = nil
    }
}

extension View {
    /// Apply inside native labels: List retains row actions and the final grid.
    func researchGroupEntrance(_ progress: CGFloat) -> some View {
        opacity(progress)
            .offset(y: ScholiumGrid.Spacing.nestedContentInset * (1 - progress))
    }
}
