import ScholiumApplication
import Testing

@Suite("Workspace event generation gate")
struct WorkspaceEventGenerationGateTests {
    @Test("Older and duplicate generations are rejected")
    func staleGenerationRejection() {
        var gate = WorkspaceEventGenerationGate()

        let acceptedSeven = gate.accept(generation: 7)
        #expect(acceptedSeven)
        #expect(gate.latestAcceptedGeneration == 7)
        let duplicateSeven = gate.accept(generation: 7)
        #expect(!duplicateSeven)
        let staleSix = gate.accept(generation: 6)
        #expect(!staleSix)
        #expect(gate.latestAcceptedGeneration == 7)
        let acceptedEight = gate.accept(generation: 8)
        #expect(acceptedEight)
        #expect(gate.latestAcceptedGeneration == 8)

        gate.reset()
        #expect(gate.latestAcceptedGeneration == nil)
        let acceptedZero = gate.accept(generation: 0)
        #expect(acceptedZero)
    }
}
