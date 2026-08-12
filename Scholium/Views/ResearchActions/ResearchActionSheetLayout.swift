import ScholiumContracts

enum ResearchActionSheetModule: Hashable {
    case source
    case fidelityChecks
    case passage
    case focalNotes
}

struct ResearchActionSheetLayout: Equatable {
    let primaryModules: [ResearchActionSheetModule]
    let additionalContextModules: [ResearchActionSheetModule]
    let expandsAdditionalContext: Bool

    static func resolve(
        selectors: Set<PlatformActionSelector>,
        passageIsAvailable: Bool,
        selectedFocalNoteCount: Int
    ) -> Self {
        var primaryModules: [ResearchActionSheetModule] = []
        if selectors.contains(.source) {
            primaryModules.append(.source)
        }
        if selectors.contains(.fidelityChecks) {
            primaryModules.append(.fidelityChecks)
        }

        var additionalContextModules: [ResearchActionSheetModule] = []
        if selectors.contains(.passage), passageIsAvailable {
            additionalContextModules.append(.passage)
        }
        if selectors.contains(.focalNotes) {
            additionalContextModules.append(.focalNotes)
        }

        return Self(
            primaryModules: primaryModules,
            additionalContextModules: additionalContextModules,
            expandsAdditionalContext: passageIsAvailable || selectedFocalNoteCount > 0
        )
    }
}
