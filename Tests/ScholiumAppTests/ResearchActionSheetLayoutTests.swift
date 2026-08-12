@testable import ScholiumApp
import ScholiumContracts
import Testing

@Suite("Research Action sheet layout")
struct ResearchActionSheetLayoutTests {
    @Test("Action capabilities resolve into primary and additional modules")
    func capabilityModules() throws {
        let discuss = try #require(PlatformActionCatalog.definition(for: .discuss))
        #expect(ResearchActionSheetLayout.resolve(
            selectors: Set(discuss.requiredSelectors + discuss.optionalSelectors),
            passageIsAvailable: false,
            selectedFocalNoteCount: 0
        ) == ResearchActionSheetLayout(
            primaryModules: [],
            additionalContextModules: [.focalNotes],
            expandsAdditionalContext: false
        ))

        let discussWithPassage = ResearchActionSheetLayout.resolve(
            selectors: Set(discuss.requiredSelectors + discuss.optionalSelectors),
            passageIsAvailable: true,
            selectedFocalNoteCount: 0
        )
        #expect(discussWithPassage.additionalContextModules == [.passage, .focalNotes])
        #expect(discussWithPassage.expandsAdditionalContext)

        let analyze = try #require(PlatformActionCatalog.definition(for: .analyze))
        #expect(ResearchActionSheetLayout.resolve(
            selectors: Set(analyze.requiredSelectors + analyze.optionalSelectors),
            passageIsAvailable: false,
            selectedFocalNoteCount: 0
        ).primaryModules == [.source])

        let fidelity = try #require(
            PlatformActionCatalog.definition(for: .checkFidelity)
        )
        #expect(ResearchActionSheetLayout.resolve(
            selectors: Set(fidelity.requiredSelectors + fidelity.optionalSelectors),
            passageIsAvailable: false,
            selectedFocalNoteCount: 0
        ).primaryModules == [.fidelityChecks])
    }

    @Test("Code-owned selectors contain only real sheet inputs")
    func realSelectorsOnly() throws {
        let write = try #require(PlatformActionCatalog.definition(for: .write))
        #expect(write.optionalSelectors == [.focalNotes, .passage])

        let fidelity = try #require(
            PlatformActionCatalog.definition(for: .checkFidelity)
        )
        #expect(fidelity.optionalSelectors == [
            .focalNotes, .passage, .fidelityChecks,
        ])

        let manuscript = try #require(
            PlatformActionCatalog.definition(for: .manuscript)
        )
        #expect(manuscript.optionalSelectors == [.focalNotes])
    }
}
